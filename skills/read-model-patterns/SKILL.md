---
name: read-model-patterns
description: Read Model and CQRS patterns - PostgreSQL materialized views, read replicas, and projection models that separate read concerns from writes. Use for expensive aggregation queries, financial summaries, and dashboards.
allowed-tools: Read, Write, Edit, Bash
---

# Read Model Patterns (CQRS Read Side)

## Overview

The Read Model pattern separates **read concerns** from **write concerns** (CQRS — Command Query Responsibility Segregation). Instead of running expensive aggregation queries against your write tables on every request, you build a pre-computed projection:

```
Write Side                        Read Side
─────────────────────             ──────────────────────────
Controller                        Dashboard Controller
    │                                     │
Service Object                    Query Object
    │                                     │
ActiveRecord write          ←──── Materialized View (Postgres)
(ledger_events, orders)           (user_balance_summaries)
    │                                     ▲
    ▼                                     │
Postgres (source of truth)    RefreshBalanceSummaryJob (async)
```

**Key Insight:** Accept 1–5 seconds of staleness on reads in exchange for fast, non-blocking dashboards.

## When to Use

| Scenario | Use Read Model? |
|----------|-----------------|
| SUM/COUNT/GROUP BY across large tables | Yes |
| Financial balance dashboard | Yes |
| Reporting pages with multiple JOINs | Yes |
| Read-heavy dashboard competing with writes | Yes |
| Simple filtered list (no aggregation) | No — use Query Object with indexes |
| Real-time data (0s staleness required) | No — query primary DB directly |
| Single model CRUD | No — not needed |

## Workflow Checklist

```
Read Model Implementation Progress:
- [ ] Step 1: Identify the expensive query driving the need
- [ ] Step 2: Write materialized view SQL
- [ ] Step 3: Create migration (execute SQL, add unique index)
- [ ] Step 4: Create read-only projection model
- [ ] Step 5: Create refresh service (CONCURRENT refresh)
- [ ] Step 6: Create refresh job (thin delegator)
- [ ] Step 7: Trigger refresh after writes
- [ ] Step 8: Configure read replica routing (optional, for heavy load)
- [ ] Step 9: Schedule periodic full refresh (safety net)
- [ ] Step 10: Write specs — projection accuracy, staleness tolerance
```

## Step 1: Identify the Expensive Query

Before building a materialized view, benchmark the query:

```ruby
# Slow query driving the read model need:
User.joins(:ledger_events)
    .where(ledger_events: { status: :reconciled })
    .select("users.id, SUM(CASE WHEN type='deposit' THEN amount ELSE -amount END) AS balance")
    .group("users.id")
# → 800ms on 2M rows, runs on every dashboard load
```

## Step 2: Materialized View SQL

```sql
-- The view encodes the expensive aggregation once, pre-computed
CREATE MATERIALIZED VIEW user_balance_summaries AS
SELECT
  e.user_id,
  SUM(CASE WHEN e.type = 'deposit'    THEN e.amount ELSE 0 END)    AS total_deposits,
  SUM(CASE WHEN e.type = 'withdrawal' THEN e.amount ELSE 0 END)    AS total_withdrawals,
  SUM(CASE WHEN e.type = 'deposit'    THEN e.amount ELSE -e.amount END) AS balance,
  COUNT(*) FILTER (WHERE e.status = 'reconciled')                   AS reconciled_count,
  COUNT(*) FILTER (WHERE e.status = 'unreconciled')                 AS unreconciled_count,
  COUNT(*) FILTER (WHERE e.duplicate = true)                        AS duplicate_count,
  MAX(e.created_at)                                                 AS last_transaction_at,
  NOW()                                                             AS refreshed_at
FROM ledger_events e
WHERE e.status IN ('reconciled', 'unreconciled')
GROUP BY e.user_id
WITH DATA;
```

## Step 3: Migration

```ruby
# db/migrate/20240101000002_create_user_balance_summaries.rb
class CreateUserBalanceSummaries < ActiveRecord::Migration[8.1]
  def up
    execute <<-SQL
      CREATE MATERIALIZED VIEW user_balance_summaries AS
      SELECT
        e.user_id,
        SUM(CASE WHEN e.type = 'deposit'    THEN e.amount ELSE 0 END)         AS total_deposits,
        SUM(CASE WHEN e.type = 'withdrawal' THEN e.amount ELSE 0 END)         AS total_withdrawals,
        SUM(CASE WHEN e.type = 'deposit'    THEN e.amount ELSE -e.amount END) AS balance,
        COUNT(*) FILTER (WHERE e.status = 'reconciled')                        AS reconciled_count,
        COUNT(*) FILTER (WHERE e.status = 'unreconciled')                      AS unreconciled_count,
        COUNT(*) FILTER (WHERE e.duplicate = true)                             AS duplicate_count,
        MAX(e.created_at)                                                      AS last_transaction_at,
        NOW()                                                                  AS refreshed_at
      FROM ledger_events e
      WHERE e.status IN ('reconciled', 'unreconciled')
      GROUP BY e.user_id
      WITH DATA;
    SQL

    # UNIQUE index on user_id is REQUIRED for CONCURRENT refresh
    add_index :user_balance_summaries, :user_id, unique: true
    add_index :user_balance_summaries, :balance
    add_index :user_balance_summaries, :last_transaction_at
  end

  def down
    execute "DROP MATERIALIZED VIEW IF EXISTS user_balance_summaries"
  end
end
```

## Step 4: Projection Model (Read-Only)

```ruby
# app/models/user_balance_summary.rb
class UserBalanceSummary < ApplicationRecord
  self.table_name = "user_balance_summaries"

  belongs_to :user

  # Prevent accidental writes — this is a projection, never a write target
  def readonly?
    true
  end

  # Convenience: money amounts in dollars (stored as cents)
  def balance_dollars
    balance.to_f / 100
  end

  def stale?(threshold: 5.minutes)
    refreshed_at < threshold.ago
  end
end
```

## Step 5: Refresh Service

```ruby
# app/services/read_models/refresh_balance_summary_service.rb
module ReadModels
  class RefreshBalanceSummaryService < ApplicationService
    def call
      # CONCURRENT = holds only a ShareUpdateExclusiveLock, reads continue
      # Requires a UNIQUE index on the view
      ActiveRecord::Base.connection.execute(
        "REFRESH MATERIALIZED VIEW CONCURRENTLY user_balance_summaries"
      )
      Success(:refreshed)
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.error("Materialized view refresh failed: #{e.message}")
      Failure(e.message)
    end
  end
end
```

## Step 6: Refresh Job

```ruby
# app/jobs/refresh_balance_summary_job.rb
class RefreshBalanceSummaryJob < ApplicationJob
  queue_as :read_models
  discard_on ActiveJob::DeserializationError

  def perform
    result = ReadModels::RefreshBalanceSummaryService.call
    Rails.logger.warn("Refresh failed: #{result.failure}") if result.failure?
  end
end
```

## Step 7: Trigger Refresh After Writes

```ruby
# app/controllers/ledger_events_controller.rb
def create
  result = LedgerEvents::ReconcileService.call(
    user: current_user,
    params: ledger_params
  )

  if result.success?
    # Async refresh — dashboard sees new data within ~1-2 seconds
    RefreshBalanceSummaryJob.perform_later
    render json: result.value!, status: :created
  else
    render json: { error: result.failure }, status: :unprocessable_entity
  end
end
```

## Step 8: Read Replica Routing (Optional)

For heavy read load, route read model queries to a replica:

```yaml
# config/database.yml
production:
  primary: &primary
    url: <%= ENV["DATABASE_URL"] %>
    migrations_paths: db/migrate
  replica:
    <<: *primary
    url: <%= ENV["DATABASE_REPLICA_URL"] %>
    replica: true
```

```ruby
# app/models/application_record.rb
class ApplicationRecord < ActiveRecord::Base
  connects_to database: { writing: :primary, reading: :replica }
end
```

```ruby
# app/queries/user_balance_query.rb
class UserBalanceQuery
  def call(user_id:)
    ActiveRecord::Base.connected_to(role: :reading) do
      UserBalanceSummary.find_by(user_id: user_id)
    end
  end
end
```

## Step 9: Periodic Full Refresh (Safety Net)

```yaml
# config/recurring.yml
refresh_balance_summaries:
  class: RefreshBalanceSummaryJob
  schedule: every 5 minutes
  queue: read_models
```

This catches cases where a write didn't trigger a refresh (failed job, missed event, data import).

## Testing

```ruby
RSpec.describe UserBalanceSummary do
  let(:user) { create(:user) }

  def refresh!
    ActiveRecord::Base.connection.execute(
      "REFRESH MATERIALIZED VIEW CONCURRENTLY user_balance_summaries"
    )
  end

  describe "projection accuracy" do
    before do
      create(:ledger_event, user: user, type: "deposit",    amount: 10_000, status: :reconciled)
      create(:ledger_event, user: user, type: "withdrawal", amount: 3_000,  status: :reconciled)
      create(:ledger_event, user: user, type: "deposit",    amount: 500,    status: :unreconciled)
      create(:ledger_event, user: user, type: "deposit",    amount: 200,    status: :pending)  # excluded
      refresh!
    end

    it "calculates correct balance from reconciled and unreconciled events" do
      summary = UserBalanceSummary.find_by(user_id: user.id)
      expect(summary.balance).to          eq(7_500)   # 10000 - 3000 + 500
      expect(summary.total_deposits).to   eq(10_500)  # 10000 + 500
      expect(summary.total_withdrawals).to eq(3_000)
    end

    it "is read-only" do
      summary = UserBalanceSummary.find_by(user_id: user.id)
      expect { summary.update!(balance: 0) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end
end
```

```ruby
RSpec.describe ReadModels::RefreshBalanceSummaryService do
  it "returns Success after refresh" do
    result = described_class.call
    expect(result).to be_success
  end

  it "returns Failure when view does not exist" do
    allow(ActiveRecord::Base.connection).to receive(:execute)
      .and_raise(ActiveRecord::StatementInvalid, "view does not exist")

    result = described_class.call
    expect(result).to be_failure
    expect(result.failure).to include("view does not exist")
  end
end
```

## CQRS Quick Reference

```
Write Side                          Read Side
──────────────────────────          ─────────────────────────────
Controller receives command         Controller renders projection
    │                                       │
Service Object executes             Query Object fetches from
(creates, updates, deletes)         materialized view / replica
    │                                       │
Writes to primary DB                Reads from view / replica
    │
Triggers async refresh →→→→→→→→→→→→ Materialized view updated
```

## Anti-Patterns to Avoid

1. **Non-concurrent refresh** — `REFRESH MATERIALIZED VIEW` (without CONCURRENT) locks all reads; always use CONCURRENT in production
2. **No unique index on view** — CONCURRENT refresh requires a unique index
3. **Refreshing on every read** — defeats the purpose; refresh after writes, not reads
4. **Writing to the projection model** — projection models must be `readonly?`; writes go to source tables
5. **No periodic safety-net refresh** — missed writes leave the projection stale indefinitely
6. **Querying complex join logic inline in controllers** — always use a Query Object to consume the projection
7. **Using materialized view for real-time data** — if you need 0s staleness, query the primary DB directly
