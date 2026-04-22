---
name: queue-concurrency-throttling
description: Queue-level concurrency controls in Solid Queue to respect external API rate limits. Use when a job calls a third-party API with burst or concurrency limits, or when you need to cap how many instances of a job type run in parallel across all workers.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Queue Concurrency Throttling

## Overview

**Concurrency** and **rate** are different constraints:

- **Rate limit** — max calls per second/minute (e.g. 100 req/s)
- **Concurrency limit** — max simultaneous in-flight requests (e.g. 30 at once)

Most external APIs publish a burst concurrency limit. The goal is to ensure that at no point in time more than N workers are calling that API simultaneously.

Solid Queue controls this via **per-queue thread limits**: each queue gets its own worker pool, so capping threads on a dedicated queue caps the concurrency of all jobs that use it.

```
config/solid_queue.yml
  partner_sync queue → threads: 30
       ↓
  Max 30 SyncUserJob running simultaneously across all processes
       ↓
  External API burst limit is never reached
```

## When to Use

| Scenario | Throttle? |
|----------|-----------|
| Job calls external API with published rate/burst limit | ✅ Yes |
| Multiple job types call the same external API | ✅ Yes — shared queue |
| Internal DB-only job with no external dependencies | ❌ No |
| One-off admin task | ❌ No — inline is fine |

## Solid Queue Configuration

Create a dedicated queue for each external API you need to throttle:

```yaml
# config/solid_queue.yml
default: &default
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: [critical, default]
      threads: 5
      processes: 2
    - queues: [low]
      threads: 2
      processes: 1
    # Dedicated queue — capped at 30 concurrent workers
    - queues: [partner_sync]
      threads: 30
      processes: 1   # ⚠️ keep processes: 1 on throttled queues (see anti-patterns)

development:
  <<: *default

production:
  <<: *default
```

**Key principle:** `threads: 30` means a maximum of 30 job instances run at the same time on that queue — regardless of how many Solid Queue processes are running.

## Job Configuration

```ruby
# app/jobs/partners/sync_user_job.rb
class Partners::SyncUserJob < ApplicationJob
  # 1. Dedicated queue — threads capped in solid_queue.yml
  queue_as :partner_sync

  # 2. Retry on rate limit with increasing backoff
  retry_on Partners::Errors::RateLimitExceeded,
           wait: :polynomially_longer,
           attempts: 10

  # 3. Retry on transient errors (5xx, timeouts, infrastructure)
  retry_on Partners::Errors::RetryableError,
           wait: :polynomially_longer,
           attempts: 5

  # 4. Discard — don't retry unrecoverable logic errors
  discard_on Partners::Errors::PermanentError

  def perform(external_id, partner_id)
    result = Partners::SyncUser.new.call(external_id, partner_id:)
    handle_failure(result.failure, external_id) if result.failure?
  end

  private

  def handle_failure(error_type, external_id)
    case error_type
    when :rate_limit
      # 429: raise so Solid Queue retries with backoff
      # The queue concurrency limit prevented most 429s — this is the safety net
      raise Partners::Errors::RateLimitExceeded, "429 from partner API — #{external_id}"
    when :api_error, :timeout
      raise Partners::Errors::RetryableError, "Transient error (#{error_type}) — #{external_id}"
    when :user_not_found
      nil  # expected race condition — discard silently
    else
      raise StandardError, "Unexpected error: #{error_type} for #{external_id}"
    end
  end
end
```

## Two-Layer Defense

The concurrency limit alone is not sufficient. Even with 30 concurrent workers, if each makes a call in under 10ms you can still generate thousands of req/s. The second layer catches any 429 that leaks through:

```
Layer 1: Queue concurrency limit (solid_queue.yml threads: 30)
  → Prevents most rate limit hits under normal load

Layer 2: retry_on RateLimitExceeded + polynomially_longer
  → Handles 429s from other callers or sudden API tightening
  → Backs off: ~3s → ~10s → ~30s → ~90s → ...

Layer 3: discard_on after max attempts
  → Logs permanently failed jobs for investigation
```

## Custom Error Classes

Define structured error classes so retry and discard rules are explicit:

```ruby
# app/errors/partners/errors.rb
module Partners
  module Errors
    # Raised on HTTP 429 — retried with backoff
    class RateLimitExceeded < StandardError; end

    # Raised on HTTP 5xx, timeouts, queue failures — retried
    class RetryableError < StandardError; end

    # Raised on unrecoverable logic errors — discarded
    class PermanentError < StandardError; end
  end
end
```

## Multiple Job Types on the Same API

If several job types call the same external API, put them all on the same dedicated queue. The thread cap applies to the combined concurrency:

```ruby
# All three share the partner_sync queue → combined concurrency ≤ 30
class Partners::SyncUserJob < ApplicationJob
  queue_as :partner_sync
end

class Partners::CancelSubscriptionJob < ApplicationJob
  queue_as :partner_sync
end

class Partners::UpdatePlanJob < ApplicationJob
  queue_as :partner_sync
end
```

```yaml
# config/solid_queue.yml — one worker pool for all three
workers:
  - queues: [partner_sync]
    threads: 30   # ≤ 30 total across SyncUser + CancelSubscription + UpdatePlan
    processes: 1
```

## Staggered Scheduling Alternative

When you control the enqueue time (scheduler job), staggering is an alternative — spread the load over time instead of capping simultaneous execution:

```ruby
# ✅ Stagger: one job every 2 seconds instead of all at once
records.each_with_index do |record, index|
  delay = index * 2.seconds
  Partners::SyncUserJob.set(wait: delay).perform_later(record.external_id, partner_id)
end
```

**Stagger vs. Concurrency limit — when to use each:**

| Approach | Best For |
|----------|----------|
| Queue concurrency limit | API with burst/concurrent limit, many jobs |
| Staggered scheduling | API with req/s limit, predictable job duration |
| Both together | High-volume syncs against strict rate-limited APIs |

## Sidekiq Migration Reference

| Sidekiq | Solid Queue |
|---------|-------------|
| `include Sidekiq::Throttled::Worker` | Queue concurrency in `solid_queue.yml` |
| `sidekiq_throttle concurrency: { limit: 30 }` | `threads: 30` on dedicated queue |
| `sidekiq_options queue: :partner_sync` | `queue_as :partner_sync` |
| `sidekiq_options retry: 10` | `retry_on Error, attempts: 10` |
| `sidekiq_retries_exhausted` | `discard_on` + optional `after_discard` callback |

## Testing

```ruby
# spec/jobs/partners/sync_user_job_spec.rb
RSpec.describe Partners::SyncUserJob, type: :job do
  subject(:perform) { described_class.perform_now(external_id, partner_id) }

  let(:external_id) { "ext_001" }
  let(:partner_id)  { 42 }
  let(:service)     { instance_double(Partners::SyncUser) }

  before { allow(Partners::SyncUser).to receive(:new).and_return(service) }

  it "uses the partner_sync queue" do
    expect(described_class.new.queue_name).to eq("partner_sync")
  end

  it "retries on RateLimitExceeded" do
    expect(described_class).to have_retry_on(Partners::Errors::RateLimitExceeded)
  end

  it "discards on PermanentError" do
    expect(described_class).to have_discard_on(Partners::Errors::PermanentError)
  end

  context "when service returns :rate_limit failure" do
    before do
      allow(service).to receive(:call)
        .and_return(Dry::Monads::Failure(:rate_limit))
    end

    it "raises RateLimitExceeded to trigger retry" do
      expect { perform }.to raise_error(Partners::Errors::RateLimitExceeded)
    end
  end

  context "when service returns :user_not_found" do
    before do
      allow(service).to receive(:call)
        .and_return(Dry::Monads::Failure(:user_not_found))
    end

    it "does not raise — discards silently" do
      expect { perform }.not_to raise_error
    end
  end

  context "when service succeeds" do
    before do
      allow(service).to receive(:call)
        .and_return(Dry::Monads::Success(:synced))
    end

    it "completes without error" do
      expect { perform }.not_to raise_error
    end
  end
end
```

## Anti-Patterns to Avoid

1. **Putting throttled jobs on the default queue** — they compete with all other jobs and the thread cap is meaningless
2. **Handling 429s silently (swallowing the error)** — the job appears to succeed but no work happened; always raise on rate limit
3. **`retry_on StandardError`** — too broad; retries bugs that should be fixed, not retried; use explicit error classes
4. **Setting threads too high to "be safe"** — if the API limit is 50 and other services also call it, use a margin (e.g. 30); document why in a comment
5. **`processes: 2` on a throttled queue** — `processes: 2` with `threads: 30` gives 60 concurrent workers; for throttled queues keep `processes: 1`
6. **No custom error classes** — `retry_on` and `discard_on` can't meaningfully coexist on `StandardError`; define explicit classes
7. **Staggering without a concurrency limit** — 10,000 jobs at 2s each takes 5.5 hours; combine staggering with a reasonable thread cap

## Related Skills

| Need | Use |
|------|-----|
| Fan-out scheduler that bulk-enqueues these throttled jobs | `job-fan-out-pattern` skill |
| Full Solid Queue setup (queues, recurring, workers) | `solid-queue-setup` skill |
| Service the worker delegates to (dry-monads result) | `rails-service-object` skill |
| External API gateway with error mapping | `external-api-integration` skill |
| Preventing duplicate processing on retry | `idempotency-keys` skill |
