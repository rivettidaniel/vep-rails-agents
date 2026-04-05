---
name: event-sourcing-rails
description: Event Sourcing with RailsEventStore - immutable event streams, AggregateRoot, projections, and subscribers. Use when domain state must be derived from an append-only event log (financial ledgers, audit trails, inventory).
allowed-tools: Read, Write, Edit, Bash
---

# Event Sourcing with RailsEventStore

## Overview

Event Sourcing replaces mutable state with an **append-only log of domain events**. Instead of storing "the current balance is $7,000", you store every event that led to that balance:

```
LedgerEventDeposited  +10,000
LedgerEventWithdrawn  -3,000
LedgerEventDeposited  +500
──────────────────────────────
Balance: 7,500  (derived, not stored)
```

This is the write side of CQRS. The read side (balance dashboards, projections) is built by `read-model-patterns`.

**Core vocabulary:**

| Term | Meaning |
|------|---------|
| **Event** | Immutable fact that happened (`OrderCreated`, `PaymentProcessed`) |
| **Stream** | Ordered sequence of events for one aggregate (`Order$uuid`) |
| **Aggregate** | Domain object that validates rules and emits events |
| **Command** | Intent to change state (handled by service object) |
| **Projection** | Read model built from events (via subscribers) |
| **Subscriber** | Reacts to events to update projections or trigger side effects |

## When to Use

| Scenario | Use Event Sourcing? |
|----------|---------------------|
| Financial ledger / balance | Yes — canonical use case |
| Full audit trail required | Yes |
| Replay state from history | Yes |
| Multiple downstream consumers per event | Yes (with Kafka integration) |
| Simple CRUD with no history requirement | No — regular ActiveRecord |
| Notification-only side effects | No — Event Dispatcher is enough |
| Adding to existing mutable models | Caution — hybrid needs clear boundaries |

## Workflow Checklist

```
Event Sourcing Implementation Progress:
- [ ] Step 1: Install rails_event_store and aggregate_root gems
- [ ] Step 2: Run generator, configure initializer
- [ ] Step 3: Create domain event classes
- [ ] Step 4: Create Aggregate Root class with on() handlers
- [ ] Step 5: Create command services (load → call → store)
- [ ] Step 6: Create subscribers (projections, side effects)
- [ ] Step 7: Register subscribers in initializer
- [ ] Step 8: Write aggregate specs (event assertions)
- [ ] Step 9: Write subscriber specs
- [ ] Step 10: Write command service specs
```

## Step 1: Gems

```ruby
# Gemfile
gem "rails_event_store", "~> 2.15"
gem "aggregate_root",    "~> 2.15"
```

```bash
bundle install
bin/rails generate rails_event_store:install
bin/rails db:migrate
```

This creates the `event_store_events` and `event_store_events_in_streams` tables.

## Step 2: Initializer

```ruby
# config/initializers/event_store.rb
module MyApp
  EventStore = RailsEventStore::Client.new

  # Register all subscribers here
  EventStore.subscribe(
    Orders::UpdateBalanceProjectionSubscriber.new,
    to: [Orders::OrderCreated, Orders::OrderPaid, Orders::OrderCancelled]
  )

  EventStore.subscribe(
    Orders::SendConfirmationEmailSubscriber.new,
    to: [Orders::OrderPaid]
  )

  EventStore.subscribe(
    Payments::FraudDetectionSubscriber.new,
    to: [Orders::OrderCreated, Payments::PaymentProcessed]
  )
end

# Make client accessible from Rails.configuration
Rails.application.config.event_store = MyApp::EventStore
```

## Step 3: Domain Events

```ruby
# app/events/orders/order_created.rb
module Orders
  class OrderCreated < RailsEventStore::Event
    # data schema (documentation — RES doesn't enforce schema by default)
    # {
    #   order_id:   String (UUID),
    #   user_id:    Integer,
    #   amount:     Integer (cents),
    #   items:      Array<{ product_id:, quantity:, unit_price: }>,
    #   created_at: ISO8601 String
    # }
  end
end

# app/events/orders/order_paid.rb
module Orders
  class OrderPaid < RailsEventStore::Event
    # data: { order_id:, payment_method:, amount:, paid_at: }
  end
end

# app/events/orders/order_cancelled.rb
module Orders
  class OrderCancelled < RailsEventStore::Event
    # data: { order_id:, reason:, cancelled_at: }
  end
end

# app/events/ledger/deposit_recorded.rb
module Ledger
  class DepositRecorded < RailsEventStore::Event
    # data: { event_id:, user_id:, amount:, reference_id:, recorded_at: }
  end
end

# app/events/ledger/withdrawal_recorded.rb
module Ledger
  class WithdrawalRecorded < RailsEventStore::Event
    # data: { event_id:, user_id:, amount:, reference_id:, recorded_at: }
  end
end
```

## Step 4: Aggregate Root

```ruby
# app/aggregates/order.rb
class Order
  include AggregateRoot

  InvalidTransition = Class.new(StandardError)

  attr_reader :id, :status, :user_id, :amount

  def initialize(id)
    @id     = id
    @status = :new
    @items  = []
  end

  # --- Commands (validate rules, then apply events) ---

  def create(user_id:, amount:, items:)
    raise InvalidTransition, "Order already created" unless status == :new
    raise InvalidTransition, "Amount must be positive" unless amount.positive?
    raise InvalidTransition, "Items cannot be empty" if items.empty?

    apply Orders::OrderCreated.new(data: {
      order_id:   id,
      user_id:    user_id,
      amount:     amount,
      items:      items,
      created_at: Time.current.iso8601
    })
  end

  def pay(payment_method:)
    raise InvalidTransition, "Cannot pay a #{status} order" unless status == :pending

    apply Orders::OrderPaid.new(data: {
      order_id:       id,
      payment_method: payment_method,
      amount:         amount,
      paid_at:        Time.current.iso8601
    })
  end

  def cancel(reason:)
    raise InvalidTransition, "Cannot cancel a #{status} order" if status == :cancelled

    apply Orders::OrderCancelled.new(data: {
      order_id:     id,
      reason:       reason,
      cancelled_at: Time.current.iso8601
    })
  end

  private

  # --- State mutations: ONLY here, one per event type ---

  on Orders::OrderCreated do |event|
    @user_id = event.data[:user_id]
    @amount  = event.data[:amount]
    @items   = event.data[:items]
    @status  = :pending
  end

  on Orders::OrderPaid do |_event|
    @status = :paid
  end

  on Orders::OrderCancelled do |_event|
    @status = :cancelled
  end
end
```

```ruby
# app/aggregates/ledger_account.rb
class LedgerAccount
  include AggregateRoot

  attr_reader :id, :balance, :user_id

  def initialize(id)
    @id      = id
    @balance = 0
    @events  = []
  end

  def record_deposit(user_id:, amount:, reference_id:)
    raise ArgumentError, "Amount must be positive" unless amount.positive?

    apply Ledger::DepositRecorded.new(data: {
      event_id:     SecureRandom.uuid,
      user_id:      user_id,
      amount:       amount,
      reference_id: reference_id,
      recorded_at:  Time.current.iso8601
    })
  end

  def record_withdrawal(user_id:, amount:, reference_id:)
    raise ArgumentError, "Amount must be positive" unless amount.positive?
    raise ArgumentError, "Insufficient funds" if balance < amount

    apply Ledger::WithdrawalRecorded.new(data: {
      event_id:     SecureRandom.uuid,
      user_id:      user_id,
      amount:       amount,
      reference_id: reference_id,
      recorded_at:  Time.current.iso8601
    })
  end

  private

  on Ledger::DepositRecorded do |event|
    @user_id  = event.data[:user_id]
    @balance += event.data[:amount]
  end

  on Ledger::WithdrawalRecorded do |event|
    @balance -= event.data[:amount]
  end
end
```

## Step 5: Command Services

```ruby
# app/services/application_aggregate_service.rb
class ApplicationAggregateService < ApplicationService
  private

  def repository
    @repository ||= AggregateRoot::Repository.new(event_store)
  end

  def event_store
    Rails.configuration.event_store
  end

  def load_aggregate(klass, id)
    repository.load("#{klass.name}$#{id}", klass.new(id))
  end

  def store_aggregate(stream_name, aggregate)
    repository.store(stream_name, aggregate)
  end
end
```

```ruby
# app/services/ledger/record_deposit_service.rb
module Ledger
  class RecordDepositService < ApplicationAggregateService
    def initialize(user_id:, amount:, reference_id:)
      @user_id      = user_id
      @amount       = amount
      @reference_id = reference_id
    end

    def call
      account = load_aggregate(LedgerAccount, user_id)
      account.record_deposit(user_id: user_id, amount: amount, reference_id: reference_id)
      store_aggregate("LedgerAccount$#{user_id}", account)
      Success(account.balance)
    rescue ArgumentError => e
      Failure(e.message)
    rescue StandardError => e
      Rails.logger.error("RecordDepositService failed: #{e.message}")
      Failure(e.message)
    end

    private

    attr_reader :user_id, :amount, :reference_id
  end
end
```

## Step 6: Subscribers

```ruby
# app/subscribers/orders/update_balance_projection_subscriber.rb
module Orders
  class UpdateBalanceProjectionSubscriber
    # Called synchronously after event is stored
    def call(event)
      RefreshBalanceSummaryJob.perform_later(event.data[:user_id])
    end
  end
end
```

```ruby
# app/subscribers/ledger/reconciliation_subscriber.rb
module Ledger
  class ReconciliationSubscriber
    def call(event)
      Ledger::UpdateReconciliationJob.perform_later(
        user_id:      event.data[:user_id],
        reference_id: event.data[:reference_id]
      )
    end
  end
end
```

## Step 7: Reading Event Streams

```ruby
# Read all events for an aggregate
events = Rails.configuration.event_store
              .read
              .stream("LedgerAccount$#{user_id}")
              .to_a

# Read events of a specific type globally
deposits = Rails.configuration.event_store
                .read
                .of_type([Ledger::DepositRecorded])
                .to_a

# Rebuild aggregate state from stream (for debugging or projections)
repository = AggregateRoot::Repository.new(Rails.configuration.event_store)
account    = repository.load("LedgerAccount$#{user_id}", LedgerAccount.new(user_id))
puts account.balance
```

## Testing

### Aggregate Specs (test events, not state)

```ruby
# spec/aggregates/ledger_account_spec.rb
require "rails_helper"

RSpec.describe LedgerAccount do
  subject(:account) { described_class.new(user_id) }

  let(:user_id) { 42 }

  describe "#record_deposit" do
    it "applies DepositRecorded event" do
      account.record_deposit(user_id: user_id, amount: 10_000, reference_id: "ref_1")

      expect(account.unpublished_events.last).to be_a(Ledger::DepositRecorded)
      expect(account.unpublished_events.last.data[:amount]).to eq(10_000)
    end

    it "increases balance" do
      account.record_deposit(user_id: user_id, amount: 10_000, reference_id: "ref_1")
      account.record_deposit(user_id: user_id, amount: 3_000, reference_id: "ref_2")

      expect(account.balance).to eq(13_000)
    end

    it "raises when amount is not positive" do
      expect {
        account.record_deposit(user_id: user_id, amount: 0, reference_id: "ref_1")
      }.to raise_error(ArgumentError, "Amount must be positive")
    end
  end

  describe "#record_withdrawal" do
    before { account.record_deposit(user_id: user_id, amount: 10_000, reference_id: "ref_1") }

    it "raises when balance insufficient" do
      expect {
        account.record_withdrawal(user_id: user_id, amount: 20_000, reference_id: "ref_2")
      }.to raise_error(ArgumentError, "Insufficient funds")
    end

    it "decreases balance" do
      account.record_withdrawal(user_id: user_id, amount: 3_000, reference_id: "ref_2")
      expect(account.balance).to eq(7_000)
    end
  end
end
```

### Subscriber Specs

```ruby
# spec/subscribers/ledger/reconciliation_subscriber_spec.rb
require "rails_helper"

RSpec.describe Ledger::ReconciliationSubscriber do
  subject(:subscriber) { described_class.new }

  it "enqueues UpdateReconciliationJob for the event's user and reference" do
    event = Ledger::DepositRecorded.new(data: { user_id: 42, reference_id: "ref_1", amount: 100 })

    expect {
      subscriber.call(event)
    }.to have_enqueued_job(Ledger::UpdateReconciliationJob).with(
      user_id: 42,
      reference_id: "ref_1"
    )
  end
end
```

### Command Service Specs

```ruby
# spec/services/ledger/record_deposit_service_spec.rb
require "rails_helper"

RSpec.describe Ledger::RecordDepositService do
  let(:user_id)      { 42 }
  let(:event_store)  { RailsEventStore::Client.new }

  before do
    allow(Rails.configuration).to receive(:event_store).and_return(event_store)
  end

  it "returns Success with new balance" do
    result = described_class.call(user_id: user_id, amount: 10_000, reference_id: "ref_1")
    expect(result).to be_success
    expect(result.value!).to eq(10_000)
  end

  it "publishes DepositRecorded event to the stream" do
    described_class.call(user_id: user_id, amount: 10_000, reference_id: "ref_1")

    events = event_store.read.stream("LedgerAccount$#{user_id}").to_a
    expect(events.last).to be_a(Ledger::DepositRecorded)
  end

  it "returns Failure for non-positive amount" do
    result = described_class.call(user_id: user_id, amount: 0, reference_id: "ref_1")
    expect(result).to be_failure
    expect(result.failure).to include("Amount must be positive")
  end
end
```

## File Structure

```
app/
├── events/
│   ├── orders/
│   │   ├── order_created.rb
│   │   ├── order_paid.rb
│   │   └── order_cancelled.rb
│   └── ledger/
│       ├── deposit_recorded.rb
│       └── withdrawal_recorded.rb
├── aggregates/
│   ├── order.rb
│   └── ledger_account.rb
├── services/
│   ├── application_aggregate_service.rb
│   ├── orders/
│   │   ├── create_service.rb
│   │   └── pay_service.rb
│   └── ledger/
│       ├── record_deposit_service.rb
│       └── record_withdrawal_service.rb
└── subscribers/
    ├── orders/
    │   ├── update_balance_projection_subscriber.rb
    │   └── send_confirmation_email_subscriber.rb
    └── ledger/
        └── reconciliation_subscriber.rb

spec/
├── aggregates/
│   ├── order_spec.rb
│   └── ledger_account_spec.rb
├── subscribers/
│   └── ledger/
│       └── reconciliation_subscriber_spec.rb
└── services/
    └── ledger/
        ├── record_deposit_service_spec.rb
        └── record_withdrawal_service_spec.rb

config/
└── initializers/
    └── event_store.rb
```

## Anti-Patterns to Avoid

1. **Commands instead of events** — `CreateOrder` (command) vs `OrderCreated` (event). Events are facts.
2. **State mutations outside `on` handlers** — only `on` blocks mutate aggregate state
3. **Reading aggregate from DB** — load from event stream only; DB writes are for projections
4. **Business logic in subscribers** — subscribers trigger side effects (jobs, refresh); logic stays in aggregates
5. **Changing event data schema** — existing events are immutable; create a new event version (`OrderCreatedV2`) and a migration strategy
6. **One giant aggregate** — split by bounded context (`Order`, `LedgerAccount`, `Inventory` are separate aggregates)
7. **Mixing event-sourced and AR models without boundaries** — if `LedgerAccount` is event-sourced, don't also have a `ledger_accounts` DB table that code writes to directly
