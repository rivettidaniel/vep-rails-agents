---
name: job-fan-out-pattern
description: Fan-out scheduler pattern - one orchestrator job dispatches many worker jobs efficiently using perform_all_later and Set-based filtering. Use when processing large external datasets, scheduled syncs, or any operation that reads N records and needs to dispatch N background jobs without blocking.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Job Fan-Out Pattern

## Overview

When you need to process a large dataset asynchronously, a single job that does everything sequentially is fragile: it blocks for minutes, can't be parallelised, and a single failure kills the entire batch.

The fan-out pattern splits the work into two layers:

```
SchedulerJob (one)
  └─ reads dataset, filters, bulk-enqueues
       └─ WorkerJob × N (many, run in parallel)
            └─ processes one record, calls service
```

**Key benefits:**
- Each worker fails and retries independently
- Workers run in parallel across all processes
- Bulk enqueuing uses a single queue write for N jobs
- Set-based filtering keeps DB queries to one per batch

**When to use:**

| Scenario | Fan-Out? |
|----------|----------|
| Syncing N records from external API daily | ✅ Yes |
| Sending N notifications to N users | ✅ Yes |
| Processing N rows from a CSV import | ✅ Yes |
| Single record update triggered by user action | ❌ No — direct `perform_later` |
| < 20 records | ❌ No — loop with `perform_later` is fine |

## Workflow Checklist

```
Fan-Out Implementation:
- [ ] Create SchedulerJob (thin orchestrator)
- [ ] Define BATCH_SIZE constant (500–2000 is typical)
- [ ] Fetch dataset (external API, data warehouse, DB query)
- [ ] Use each_slice to iterate in memory-safe batches
- [ ] Extract candidate IDs from batch
- [ ] One DB query per batch to filter existing records (Set lookup)
- [ ] Build args array only for valid records
- [ ] Bulk-enqueue with perform_all_later
- [ ] Create WorkerJob (thin delegator to service)
- [ ] Configure dedicated queue with concurrency limit
- [ ] Write specs for both jobs
```

## Scheduler Job — The Orchestrator

```ruby
# app/jobs/partners/sync_scheduler_job.rb
class Partners::SyncSchedulerJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 1_000

  def perform
    partner = Partner.find_by(name: "acme")
    return Rails.logger.error("Partner 'acme' not found") if partner.nil?

    records = DataWarehouseClient.new.execute(QUERY)

    records.each_slice(BATCH_SIZE) do |batch|
      # A. Extract candidate IDs from this batch
      candidate_ids = batch.filter_map { |r| r["external_id"] }
      next if candidate_ids.empty?

      # B. One DB query per batch — never one per record
      existing_ids = Set.new(User.where(external_id: candidate_ids).pluck(:external_id))

      # C. Build job instances only for records that exist locally
      jobs = batch.filter_map do |record|
        ext_id = record["external_id"]
        Partners::SyncUserJob.new(ext_id, partner.id) if existing_ids.include?(ext_id)
      end

      next if jobs.empty?

      # D. Single queue write for the entire batch
      ActiveJob::Base.perform_all_later(*jobs)
    end
  end
end
```

## Worker Job — The Leaf

```ruby
# app/jobs/partners/sync_user_job.rb
class Partners::SyncUserJob < ApplicationJob
  queue_as :partner_sync   # dedicated queue — see queue-concurrency-throttling skill

  retry_on Partners::Errors::RateLimitExceeded, wait: :polynomially_longer, attempts: 10
  retry_on Partners::Errors::RetryableError,    wait: :polynomially_longer, attempts: 5
  discard_on Partners::Errors::PermanentError

  def perform(external_id, partner_id)
    result = Partners::SyncUser.new.call(external_id, partner_id:)

    handle_failure(result.failure, external_id) if result.failure?
  end

  private

  def handle_failure(error_type, external_id)
    case error_type
    when :rate_limit
      raise Partners::Errors::RateLimitExceeded, "429 from partner API — #{external_id}"
    when :api_error, :timeout
      raise Partners::Errors::RetryableError, "Transient error (#{error_type}) — #{external_id}"
    when :user_not_found
      nil  # expected race condition — discard silently
    else
      raise StandardError, "Unknown sync error: #{error_type}"
    end
  end
end
```

## perform_all_later — Bulk Enqueue

`perform_all_later` is the ActiveJob equivalent of Sidekiq's `push_bulk`: it writes N jobs to the queue backend in a single operation instead of N individual writes.

```ruby
# ❌ WRONG — N separate queue writes
records.each do |r|
  Partners::SyncUserJob.perform_later(r.external_id, partner_id)
end

# ✅ CORRECT — one queue write for all N jobs
jobs = records.map { |r| Partners::SyncUserJob.new(r.external_id, partner_id) }
ActiveJob::Base.perform_all_later(*jobs)
```

**Sidekiq migration reference:**

| Sidekiq | ActiveJob / Solid Queue |
|---------|------------------------|
| `Sidekiq::Client.push_bulk("class" => MyWorker, "args" => args_array)` | `ActiveJob::Base.perform_all_later(*jobs)` |
| `MyWorker.perform_async(id)` | `MyJob.perform_later(id)` |

## Set-Based Filtering — O(1) Lookups

The pre-filter before enqueuing prevents creating jobs for records that don't exist locally. Without it you get `user_not_found` failures in every worker.

```ruby
# ❌ WRONG — N+1 queries (one DB hit per record)
batch.each do |record|
  user = User.find_by(external_id: record["external_id"])
  Partners::SyncUserJob.perform_later(user.id, partner_id) if user
end

# ✅ CORRECT — one query per batch, O(1) lookup per record
existing_ids = Set.new(
  User.where(external_id: candidate_ids).pluck(:external_id)
)

jobs = batch.filter_map do |record|
  ext_id = record["external_id"]
  Partners::SyncUserJob.new(ext_id, partner_id) if existing_ids.include?(ext_id)
end
```

`Set#include?` is O(1). `Array#include?` is O(n). For a batch of 1,000 records the difference is negligible, but `Set` makes the intent explicit and scales without concern.

## BATCH_SIZE — Why It Matters

`each_slice` controls two things at once:

1. **SQL IN clause size** — `WHERE external_id IN (...)` with 10,000 values can be slow or hit DB limits; 500–2,000 is safe for PostgreSQL
2. **perform_all_later payload size** — each call serialises N job payloads; keep it bounded

```ruby
BATCH_SIZE = 1_000  # sweet spot for most cases

# For very large payloads per job (e.g. embedded data), drop to 500
# For simple ID-only jobs with fast DB lookups, can go up to 2_000
```

## Full Example — Recurring Sync

```ruby
# config/recurring.yml
production:
  partner_daily_sync:
    class: Partners::SyncSchedulerJob
    schedule: every day at 3am
    queue: default
```

```ruby
# app/jobs/partners/sync_scheduler_job.rb
class Partners::SyncSchedulerJob < ApplicationJob
  queue_as :default

  QUERY      = "SELECT external_id FROM reporting.partner_active_users".freeze
  BATCH_SIZE = 1_000

  def perform
    partner = Partner.find_by!(name: "acme")
    records = DataWarehouseClient.new.execute(QUERY)
    total_enqueued = 0

    records.each_slice(BATCH_SIZE) do |batch|
      candidate_ids = batch.filter_map { |r| r["external_id"] }
      next if candidate_ids.empty?

      existing_ids = Set.new(
        User.where(external_id: candidate_ids).pluck(:external_id)
      )

      jobs = batch.filter_map do |record|
        ext_id = record["external_id"]
        Partners::SyncUserJob.new(ext_id, partner.id) if existing_ids.include?(ext_id)
      end

      next if jobs.empty?

      ActiveJob::Base.perform_all_later(*jobs)
      total_enqueued += jobs.size
    end

    Rails.logger.info("[SyncScheduler] Enqueued #{total_enqueued} of #{records.size} records")
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error("[SyncScheduler] Partner 'acme' not found — aborting")
  end
end
```

## Testing

```ruby
# spec/jobs/partners/sync_scheduler_job_spec.rb
RSpec.describe Partners::SyncSchedulerJob, type: :job do
  let(:partner)   { create(:partner, name: "acme") }
  let(:user)      { create(:user, external_id: "ext_001") }
  let(:client)    { instance_double(DataWarehouseClient) }

  before do
    partner
    allow(DataWarehouseClient).to receive(:new).and_return(client)
  end

  describe "#perform" do
    context "when records exist locally" do
      before do
        user
        allow(client).to receive(:execute).and_return([{ "external_id" => "ext_001" }])
      end

      it "enqueues a worker job for each matching user" do
        expect {
          described_class.perform_now
        }.to have_enqueued_job(Partners::SyncUserJob)
          .with("ext_001", partner.id)
      end
    end

    context "when external_id does not exist locally" do
      before do
        allow(client).to receive(:execute).and_return([{ "external_id" => "ghost_id" }])
      end

      it "does not enqueue any jobs" do
        expect {
          described_class.perform_now
        }.not_to have_enqueued_job(Partners::SyncUserJob)
      end
    end

    context "when partner is missing" do
      before do
        Partner.delete_all
        allow(client).to receive(:execute).and_return([])
      end

      it "does not raise — logs and aborts" do
        expect { described_class.perform_now }.not_to raise_error
      end
    end
  end
end

# spec/jobs/partners/sync_user_job_spec.rb
RSpec.describe Partners::SyncUserJob, type: :job do
  let(:service) { instance_double(Partners::SyncUser) }

  before { allow(Partners::SyncUser).to receive(:new).and_return(service) }

  it "calls the service with correct args" do
    allow(service).to receive(:call).and_return(Dry::Monads::Success(:synced))
    described_class.perform_now("ext_001", 42)
    expect(service).to have_received(:call).with("ext_001", partner_id: 42)
  end

  it "raises RateLimitExceeded on :rate_limit failure" do
    allow(service).to receive(:call).and_return(Dry::Monads::Failure(:rate_limit))
    expect {
      described_class.perform_now("ext_001", 42)
    }.to raise_error(Partners::Errors::RateLimitExceeded)
  end

  it "discards silently on :user_not_found" do
    allow(service).to receive(:call).and_return(Dry::Monads::Failure(:user_not_found))
    expect { described_class.perform_now("ext_001", 42) }.not_to raise_error
  end
end
```

## Anti-Patterns to Avoid

1. **Scheduler job doing the actual work** — if the scheduler crashes after 3,000 of 10,000 records, all progress is lost; split scheduler from worker
2. **One `perform_later` per record in a loop** — N queue writes instead of 1; use `perform_all_later`
3. **`User.find_by` inside the batch loop** — N+1 queries; query once per batch and use a Set
4. **No BATCH_SIZE limit** — `WHERE external_id IN (10_000 values)` can be slow and hit parameter limits
5. **Scheduler without idempotency guard on the worker** — if the scheduler runs twice (overlapping crons), workers process duplicates; add a guard in the worker or service
6. **Raising for `:user_not_found`** — this is an expected race condition (record deleted between scheduler and worker), not an error; discard silently
7. **`perform_all_later` with thousands of jobs in one call** — serialises everything into one operation; keep it bounded with `each_slice`

## Related Skills

| Need | Use |
|------|-----|
| Solid Queue queue config, recurring jobs, worker setup | `solid-queue-setup` skill |
| Limiting concurrent workers to respect API rate limits | `queue-concurrency-throttling` skill |
| Business logic inside the worker job | `rails-service-object` skill |
| Preventing duplicate processing across retries | `idempotency-keys` skill |
| Guaranteed event publishing alongside DB write | `outbox-pattern` skill |
| Bulk DB operations inside the worker service | `bulk-operations` skill |
