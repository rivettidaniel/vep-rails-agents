---
name: outbox-pattern
description: Transactional Outbox Pattern - atomic event persistence alongside domain writes, with a polling relay job. Use when publishing to Kafka, webhooks, or external systems must be guaranteed even on process crash.
allowed-tools: Read, Write, Edit, Bash
---

# Transactional Outbox Pattern

## Overview

The Outbox pattern solves the **dual-write problem**: when you need to write to your database AND publish an event to an external system (Kafka, webhook, notification service), one can fail while the other succeeds, leaving your system in an inconsistent state.

**Solution:** Write the event to an `outbox_messages` table **inside the same database transaction** as your domain change. A separate relay job polls the outbox and publishes to the external system.

```
Controller/Service
       │
       ▼
┌─────────────────────────────────┐  ← Single ACID transaction
│  Domain write (e.g. Order.create)│
│  OutboxMessage.create!(event)   │
└─────────────────────────────────┘
             │
             ▼ (async — OutboxPublisherJob, every 5s)
       External System
       (Kafka / webhook / etc.)
```

## When to Use

| Scenario | Use Outbox? |
|----------|-------------|
| Publishing to Kafka after a DB write | Yes — dual-write problem |
| Calling a webhook after order creation | Yes — webhook may fail |
| Sending to external notification service | Yes |
| In-process side effects (email, job) | No — use Event Dispatcher or direct call |
| Sidekiq/Solid Queue job enqueue | No — `perform_later` is already atomic with DB in Rails 7.1+ |

## Workflow Checklist

```
Outbox Implementation Progress:
- [ ] Step 1: Create outbox_messages table migration
- [ ] Step 2: Create OutboxMessage model
- [ ] Step 3: Write business service — append OutboxMessage inside transaction
- [ ] Step 4: Create Outbox::RelayService (FOR UPDATE SKIP LOCKED)
- [ ] Step 5: Create OutboxPublisherJob (thin delegator)
- [ ] Step 6: Configure EventBus adapter (Kafka, webhook, etc.)
- [ ] Step 7: Schedule OutboxPublisherJob in config/recurring.yml
- [ ] Step 8: Write specs — atomicity, relay, failure paths
```

## Step 1: Migration

```ruby
# db/migrate/20240101000000_create_outbox_messages.rb
class CreateOutboxMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :outbox_messages do |t|
      t.string   :event_type,     null: false
      t.string   :aggregate_type, null: false
      t.bigint   :aggregate_id,   null: false
      t.jsonb    :payload,        null: false, default: {}
      t.string   :status,         null: false, default: "pending"
      t.integer  :attempts,       null: false, default: 0
      t.text     :last_error
      t.datetime :published_at
      t.timestamps
    end

    add_index :outbox_messages, [:status, :created_at]
    add_index :outbox_messages, [:aggregate_type, :aggregate_id]
  end
end
```

## Step 2: OutboxMessage Model

```ruby
# app/models/outbox_message.rb
class OutboxMessage < ApplicationRecord
  MAX_ATTEMPTS = 3

  enum :status, {
    pending:   "pending",
    published: "published",
    failed:    "failed"
  }

  validates :event_type, :aggregate_type, :aggregate_id, :payload, presence: true

  scope :publishable, -> {
    pending.or(where(status: :failed, attempts: ...MAX_ATTEMPTS))
           .order(:created_at)
  }

  def self.append!(event_type:, aggregate_type:, aggregate_id:, payload:)
    create!(
      event_type:     event_type,
      aggregate_type: aggregate_type,
      aggregate_id:   aggregate_id,
      payload:        payload
    )
  end
end
```

## Step 3: Business Service — Append Inside Transaction

```ruby
# app/services/orders/create_service.rb
module Orders
  class CreateService < ApplicationService
    def initialize(user:, params:)
      @user   = user
      @params = params
    end

    def call
      ActiveRecord::Base.transaction do
        order = Order.create!(order_attributes)

        OutboxMessage.append!(
          event_type:     "order_created",
          aggregate_type: "Order",
          aggregate_id:   order.id,
          payload:        order_payload(order)
        )

        Success(order)
      end
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors.full_messages.join(", "))
    end

    private

    attr_reader :user, :params

    def order_attributes
      params.merge(user: user, status: :pending)
    end

    def order_payload(order)
      {
        event_id:     SecureRandom.uuid,
        order_id:     order.id,
        user_id:      order.user_id,
        amount:       order.total,
        published_at: Time.current.iso8601
      }
    end
  end
end
```

## Step 4: Relay Service

```ruby
# app/services/outbox/relay_service.rb
module Outbox
  class RelayService < ApplicationService
    BATCH_SIZE = 100

    def call
      messages = OutboxMessage
        .publishable
        .limit(BATCH_SIZE)
        .lock("FOR UPDATE SKIP LOCKED")

      published = 0
      messages.each do |msg|
        publish(msg)
        published += 1
      end

      Success(published)
    rescue StandardError => e
      Rails.logger.error("Outbox relay error: #{e.message}")
      Failure(e.message)
    end

    private

    def publish(msg)
      EventBus.publish(msg.event_type, msg.payload)
      msg.update!(status: :published, published_at: Time.current)
    rescue StandardError => e
      msg.increment!(:attempts)
      new_status = msg.attempts >= OutboxMessage::MAX_ATTEMPTS ? :failed : :pending
      msg.update!(status: new_status, last_error: e.message)
      Rails.logger.error("Failed to publish outbox message #{msg.id}: #{e.message}")
    end
  end
end
```

## Step 5: OutboxPublisherJob

```ruby
# app/jobs/outbox_publisher_job.rb
class OutboxPublisherJob < ApplicationJob
  queue_as :outbox
  retry_on StandardError, wait: :exponentially_longer, attempts: 5

  def perform
    result = Outbox::RelayService.call
    Rails.logger.info("Outbox relay: #{result.value!} messages published") if result.success?
  end
end
```

## Step 6: Schedule as Recurring Job

```yaml
# config/recurring.yml
outbox_publisher:
  class: OutboxPublisherJob
  schedule: every 5 seconds
  queue: outbox
```

## Step 7: EventBus Adapter

```ruby
# app/services/event_bus.rb
class EventBus
  def self.publish(event_type, payload)
    adapter.publish(event_type, payload)
  end

  def self.adapter
    @adapter ||= Rails.env.test? ? TestAdapter.new : KafkaAdapter.new
  end

  class KafkaAdapter
    def publish(event_type, payload)
      Karafka.producer.produce_async(
        topic: event_type.tr("_", "-"),
        payload: payload.to_json,
        partition_key: payload["aggregate_id"].to_s
      )
    end
  end

  class TestAdapter
    def publish(event_type, payload)
      published_events << { event_type: event_type, payload: payload }
    end

    def published_events
      @published_events ||= []
    end
  end
end
```

## Testing

### Atomicity

```ruby
RSpec.describe Orders::CreateService do
  let(:user) { create(:user) }

  describe "outbox atomicity" do
    it "creates order and outbox message together" do
      expect {
        Orders::CreateService.call(user: user, params: valid_params)
      }.to change(Order, :count).by(1).and change(OutboxMessage, :count).by(1)
    end

    it "creates neither order nor outbox message when order is invalid" do
      expect {
        Orders::CreateService.call(user: user, params: invalid_params)
      }.to not_change(Order, :count).and not_change(OutboxMessage, :count)
    end

    it "saves correct event_type and payload" do
      Orders::CreateService.call(user: user, params: valid_params)
      msg = OutboxMessage.last
      expect(msg.event_type).to eq("order_created")
      expect(msg.payload["user_id"]).to eq(user.id)
    end
  end
end
```

### Relay Service

```ruby
RSpec.describe Outbox::RelayService do
  let(:event_bus) { instance_double(EventBus::KafkaAdapter) }

  before { allow(EventBus).to receive(:adapter).and_return(event_bus) }

  it "publishes pending messages and marks them published" do
    msg = create(:outbox_message, status: :pending)
    allow(event_bus).to receive(:publish)

    result = described_class.call

    expect(result).to be_success
    expect(msg.reload.status).to eq("published")
    expect(msg.reload.published_at).to be_present
  end

  it "marks message as failed after MAX_ATTEMPTS" do
    msg = create(:outbox_message, status: :pending, attempts: OutboxMessage::MAX_ATTEMPTS - 1)
    allow(event_bus).to receive(:publish).and_raise(StandardError, "Kafka down")

    described_class.call

    expect(msg.reload.status).to eq("failed")
    expect(msg.reload.last_error).to include("Kafka down")
  end
end
```

## Anti-Patterns to Avoid

1. **Writing to outbox AFTER the transaction** — if the process crashes between the domain write and the outbox write, the event is lost
2. **Deleting published messages** — keep them for audit trail and replay capability
3. **Refreshing without `SKIP LOCKED`** — two relay workers will process the same message
4. **Refreshing without batching** — `find_each` or `limit` prevents memory exhaustion
5. **Putting publishing logic in the relay** — use an EventBus adapter so the relay is transport-agnostic
