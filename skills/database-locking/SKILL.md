---
name: database-locking
description: PostgreSQL locking patterns in Rails - pessimistic row locks, SELECT FOR UPDATE SKIP LOCKED, advisory locks, serializable isolation, and optimistic locking. Use inside service objects when concurrent writes risk race conditions or double-processing.
allowed-tools: Read, Write, Edit, Bash
---

# Database Locking Patterns

## Overview

Race conditions happen when two concurrent requests read and modify the same row simultaneously. Rails + PostgreSQL provides several locking mechanisms — choose based on contention level, failure tolerance, and whether you need to wait or skip.

```
High contention, must wait     → Pessimistic lock (FOR UPDATE)
High contention, skip if busy  → SKIP LOCKED (queue pattern)
Low contention, detect conflict → Optimistic lock (lock_version)
Cross-process coordination     → Advisory lock
Critical financial operations  → Serializable isolation
```

## Locking Patterns Reference

### 1. Pessimistic Locking — `with_lock` / `lock!`

Acquires a row-level `SELECT FOR UPDATE` lock. Other transactions block until you release.

**Use when:** Balance updates, inventory decrements, any "read-modify-write" that cannot see stale data.

```ruby
# Option A: with_lock (wraps in transaction automatically)
def call
  account = LedgerAccount.find(user_id)
  account.with_lock do
    # No other transaction can read/write this row until block exits
    new_balance = account.balance - amount

    raise InsufficientFunds if new_balance.negative?

    account.update!(balance: new_balance)
    LedgerEvent.create!(type: :withdrawal, amount: amount, user_id: user_id)
  end
  Success(account.reload.balance)
rescue InsufficientFunds => e
  Failure(e.message)
end

# Option B: lock! inside an existing transaction
ActiveRecord::Base.transaction do
  account = LedgerAccount.find(user_id)
  account.lock!   # SELECT ... FOR UPDATE — blocks until acquired
  account.update!(balance: account.balance - amount)
end

# Option C: lock at query time (multiple rows)
ActiveRecord::Base.transaction do
  accounts = LedgerAccount.where(user_id: user_ids).lock
  # ... process accounts
end
```

**Important:** `with_lock` / `lock!` always require an active transaction. Rails wraps automatically with `with_lock`.

---

### 2. NOWAIT — Fail Fast Instead of Waiting

Raises immediately if lock cannot be acquired, instead of blocking.

**Use when:** Non-critical operations where you prefer to retry later over waiting.

```ruby
ActiveRecord::Base.transaction do
  account = LedgerAccount.find(user_id)
  account.lock!("FOR UPDATE NOWAIT")  # Raises PG::LockNotAvailable immediately
  account.update!(balance: account.balance - amount)
rescue ActiveRecord::LockWaitTimeout, ActiveRecord::StatementInvalid => e
  # Can retry or return a busy signal to caller
  raise Concurrent::RetryableLockError, "Account is being modified — try again"
end
```

---

### 3. SKIP LOCKED — Queue Processing Pattern

Skips rows already locked by other workers. Enables parallel job processing from a DB-backed queue.

**Use when:** Outbox relay, job queues, any "process next available item" pattern.

```ruby
# app/services/outbox/relay_service.rb — canonical SKIP LOCKED usage
def call
  OutboxMessage
    .pending
    .order(:created_at)
    .limit(100)
    .lock("FOR UPDATE SKIP LOCKED")
    .each { |msg| publish(msg) }
end

# Pattern: multiple workers can run simultaneously, each gets different rows
# Worker 1 locks rows 1-100, Worker 2 skips those and gets rows 101-200
```

---

### 4. Optimistic Locking — `lock_version`

No DB lock acquired. Instead, Rails adds a `WHERE lock_version = N` clause on UPDATE. If another transaction changed the row first, the update affects 0 rows and Rails raises `ActiveRecord::StaleObjectError`.

**Use when:** Low contention, long-lived forms, version conflicts that users should resolve explicitly.

```ruby
# Migration
add_column :orders, :lock_version, :integer, default: 0, null: false

# Model — nothing needed, Rails detects lock_version automatically
class Order < ApplicationRecord
  # lock_version handled automatically
end

# Service — catch StaleObjectError
def call
  order = Order.find(order_id)
  order.update!(status: :processing, lock_version: order.lock_version)
  Success(order)
rescue ActiveRecord::StaleObjectError
  Failure("Order was modified by another process — please reload and retry")
end

# Form — pass lock_version as a hidden field
# <%= f.hidden_field :lock_version %>
```

---

### 5. Advisory Locks — Application-Level Coordination

PostgreSQL session-level or transaction-level locks identified by an integer key. Not tied to a specific row — used for arbitrary distributed coordination.

**Use when:** Preventing concurrent execution of a task identified by a non-row ID (e.g., prevent two workers from running the same report simultaneously).

```ruby
# app/services/advisory_lock_service.rb
class AdvisoryLockService
  def self.with_lock(key, &block)
    lock_key = key.hash & 0x7FFFFFFF  # Positive integer

    ActiveRecord::Base.connection.execute("SELECT pg_advisory_lock(#{lock_key})")
    block.call
  ensure
    ActiveRecord::Base.connection.execute("SELECT pg_advisory_unlock(#{lock_key})")
  end

  # Try-and-skip variant: returns false if lock unavailable
  def self.try_lock(key, &block)
    lock_key = key.hash & 0x7FFFFFFF
    result   = ActiveRecord::Base.connection.execute(
      "SELECT pg_try_advisory_lock(#{lock_key})"
    ).first["pg_try_advisory_lock"]

    return false unless result

    begin
      block.call
      true
    ensure
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_unlock(#{lock_key})")
    end
  end
end

# Usage
AdvisoryLockService.with_lock("refresh_balance_user_#{user_id}") do
  RefreshBalanceSummaryService.call(user_id: user_id)
end

# Skip if another worker is already refreshing
acquired = AdvisoryLockService.try_lock("monthly_report_#{report_id}") do
  Reports::GenerateMonthlyService.call(report_id: report_id)
end

Rails.logger.info("Report already being generated — skipped") unless acquired
```

---

### 6. Serializable Isolation — Strongest Guarantee

PostgreSQL's `SERIALIZABLE` isolation level detects any read/write conflicts between concurrent transactions and raises `PG::TRSerializationFailure` if a conflict is detected — even for rows you only read.

**Use when:** Complex financial operations where the outcome depends on multiple rows being consistent (e.g., transfer that reads both account balances).

```ruby
def call
  retries = 0

  begin
    ActiveRecord::Base.transaction(isolation: :serializable) do
      source = LedgerAccount.find(source_id)
      target = LedgerAccount.find(target_id)

      raise InsufficientFunds if source.balance < amount

      source.update!(balance: source.balance - amount)
      target.update!(balance: target.balance + amount)
    end
    Success(:transferred)
  rescue ActiveRecord::SerializationFailure
    retries += 1
    retry if retries < 3
    Failure("Transfer failed due to concurrent operations — please retry")
  rescue InsufficientFunds
    Failure("Insufficient funds")
  end
end
```

---

## Decision Guide

```
Two concurrent requests could both decrement the same balance?
└─ YES → Pessimistic lock (with_lock / lock!)

Multiple workers should each get different items from a queue?
└─ YES → FOR UPDATE SKIP LOCKED

User submits a form that could conflict with another user's edit?
└─ YES → Optimistic lock (lock_version)

Two processes should never run the same task simultaneously?
└─ YES → Advisory lock (pg_advisory_lock)

Multiple rows must be read and updated atomically (transfer between accounts)?
└─ YES → Serializable isolation

One request runs fast and lock contention is acceptable?
└─ YES → Pessimistic lock (simple, correct)

One request may wait a long time and blocking is unacceptable?
└─ YES → NOWAIT or SKIP LOCKED depending on intent
```

## Locking in Service Objects — Full Example

```ruby
# app/services/ledger/process_transfer_service.rb
module Ledger
  class ProcessTransferService < ApplicationService
    InsufficientFunds = Class.new(StandardError)

    def initialize(from_user_id:, to_user_id:, amount:)
      @from_user_id = from_user_id
      @to_user_id   = to_user_id
      @amount       = amount
    end

    def call
      ActiveRecord::Base.transaction do
        # Lock BOTH accounts in consistent order (lower ID first) to prevent deadlocks
        accounts = LedgerAccount
          .where(user_id: [from_user_id, to_user_id])
          .order(:id)
          .lock("FOR UPDATE")

        source = accounts.find { |a| a.user_id == from_user_id }
        target = accounts.find { |a| a.user_id == to_user_id }

        raise InsufficientFunds if source.balance < amount

        source.update!(balance: source.balance - amount)
        target.update!(balance: target.balance + amount)

        LedgerTransfer.create!(
          from_user_id: from_user_id,
          to_user_id:   to_user_id,
          amount:       amount,
          processed_at: Time.current
        )

        Success({ from_balance: source.balance, to_balance: target.balance })
      end
    rescue InsufficientFunds
      Failure("Insufficient funds for transfer")
    rescue ActiveRecord::LockWaitTimeout
      Failure("Transfer could not be processed — account is busy, retry shortly")
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.message)
    end

    private

    attr_reader :from_user_id, :to_user_id, :amount
  end
end
```

## Deadlock Prevention

Always acquire multiple locks **in the same order** across all code paths:

```ruby
# ❌ WRONG — Transaction A locks user 1 then 2, Transaction B locks user 2 then 1 → deadlock
def transfer_a_to_b
  account_a.lock!
  account_b.lock!
end

# ✅ CORRECT — always lock in ascending ID order
def lock_accounts_for_transfer(user_id_a, user_id_b)
  LedgerAccount
    .where(user_id: [user_id_a, user_id_b])
    .order(:id)         # Consistent ordering prevents deadlocks
    .lock("FOR UPDATE")
end
```

## Testing Locking

```ruby
RSpec.describe Ledger::ProcessTransferService do
  let(:source) { create(:ledger_account, user_id: 1, balance: 10_000) }
  let(:target) { create(:ledger_account, user_id: 2, balance: 0) }

  it "transfers amount between accounts atomically" do
    result = described_class.call(
      from_user_id: source.user_id,
      to_user_id:   target.user_id,
      amount:       3_000
    )

    expect(result).to be_success
    expect(source.reload.balance).to eq(7_000)
    expect(target.reload.balance).to eq(3_000)
  end

  it "returns Failure when source has insufficient funds" do
    result = described_class.call(
      from_user_id: source.user_id,
      to_user_id:   target.user_id,
      amount:       50_000
    )

    expect(result).to be_failure
    expect(result.failure).to include("Insufficient funds")
    # Verify nothing changed
    expect(source.reload.balance).to eq(10_000)
    expect(target.reload.balance).to eq(0)
  end
end
```

## Anti-Patterns to Avoid

1. **`lock!` outside a transaction** — raises `ActiveRecord::TransactionIsolationError`; always wrap in `transaction` or use `with_lock`
2. **Locking in controller** — locking belongs in service objects; controllers should only call services
3. **Long locks around external API calls** — acquire lock, do DB work, release lock, THEN call the API
4. **Missing lock ordering** — acquiring multiple locks in inconsistent order causes deadlocks
5. **Optimistic lock on high-contention rows** — `StaleObjectError` storms under high load; use pessimistic lock instead
6. **Advisory lock key collisions** — use namespaced keys (`"balance_refresh_user_#{id}"`) hashed to integers; document key space
