---
name: kafka-karafka
description: Kafka integration for Rails via Karafka - producers, consumers, dead letter queues, consumer groups, and testing. Use when building event-driven Rails services that publish or consume Kafka topics.
allowed-tools: Read, Write, Edit, Bash
---

# Kafka + Karafka Integration

## Overview

Karafka is the standard Kafka library for Ruby/Rails. It provides:
- **Producer** — publish messages to Kafka topics
- **Consumer** — process messages from Kafka topics (each consumer class handles one topic)
- **Consumer Groups** — parallel processing across multiple workers
- **Dead Letter Queue (DLQ)** — route failed messages for inspection
- **Testing helpers** — `karafka-testing` for unit testing consumers without a real broker

**Core architectural principle:** Kafka is the source of truth — Postgres is a projection (read model) built from Kafka events.

```
HTTP Request → Controller → Kafka (202 Accepted)
                                │
                                ▼ (async)
                         Kafka Consumer
                                │
                                ▼
                        Service Object
                                │
                                ▼
                           Postgres
```

## When to Use

| Scenario | Use Karafka? |
|----------|--------------|
| Cross-service event publishing | Yes |
| Infinite replay of domain events | Yes |
| Multiple consumers per event (fan-out) | Yes |
| Per-user causal ordering of events | Yes |
| Simple async work within one Rails app | No — use Solid Queue |
| In-process side effects after controller save | No — use Event Dispatcher |
| Fire-and-forget push notifications | No — use ActionCable or a simple queue |

## Workflow Checklist

```
Karafka Integration Progress:
- [ ] Step 1: Add gems (karafka, karafka-testing, waterdrop)
- [ ] Step 2: Run karafka install
- [ ] Step 3: Configure karafka.rb (broker URL, consumer groups, routing)
- [ ] Step 4: Create ApplicationConsumer base class
- [ ] Step 5: Create consumer classes (one per topic)
- [ ] Step 6: Create producer service objects
- [ ] Step 7: Configure DLQ for each critical topic
- [ ] Step 8: Write consumer specs with karafka-testing
- [ ] Step 9: Write producer specs
- [ ] Step 10: Configure topics with karafka topics migrate
```

## Step 1: Gemfile

```ruby
gem "karafka", "~> 2.4"
gem "waterdrop", "~> 2.7"   # Included with karafka — explicit for clarity

group :test do
  gem "karafka-testing", "~> 2.4"
end
```

## Step 2: Install

```bash
bundle exec karafka install
```

## Step 3: karafka.rb

```ruby
# karafka.rb
class KarafkaApp < Karafka::App
  setup do |config|
    config.kafka = {
      "bootstrap.servers": ENV.fetch("KAFKA_BROKERS", "localhost:9092"),
      "security.protocol": ENV.fetch("KAFKA_SECURITY_PROTOCOL", "plaintext")
    }
    config.client_id = Rails.application.class.module_parent_name.underscore
    config.consumer_persistence = true   # Reuse consumer instances across batches
    config.max_wait_time        = 1_000  # ms to wait for a full batch
  end

  routes.draw do
    consumer_group :orders do
      topic "orders-created" do
        consumer Orders::CreatedConsumer
        dead_letter_queue(topic: "orders-created-dlq", max_retries: 3)
      end

      topic "orders-cancelled" do
        consumer Orders::CancelledConsumer
        dead_letter_queue(topic: "orders-cancelled-dlq", max_retries: 3)
      end
    end

    consumer_group :payments do
      topic "payments-processed" do
        consumer Payments::ProcessedConsumer
        dead_letter_queue(topic: "payments-processed-dlq", max_retries: 3)
      end
    end

    # DLQ inspection consumers
    consumer_group :dlq_monitor do
      topic "orders-created-dlq" do
        consumer Dlq::MonitorConsumer
      end
    end
  end
end
```

## Step 4: ApplicationConsumer

```ruby
# app/consumers/application_consumer.rb
class ApplicationConsumer < Karafka::BaseConsumer
  # Shared behavior: logging, error handling, metrics

  private

  def log_processing(message)
    Rails.logger.info(
      "Processing #{self.class.name} | " \
      "topic=#{topic.name} partition=#{partition} offset=#{message.offset}"
    )
  end

  def log_failure(message, error)
    Rails.logger.error(
      "Consumer failure #{self.class.name} | " \
      "topic=#{topic.name} offset=#{message.offset} error=#{error.message}"
    )
  end
end
```

## Step 5: Consumer Classes

```ruby
# app/consumers/orders/created_consumer.rb
module Orders
  class CreatedConsumer < ApplicationConsumer
    def consume
      messages.each do |message|
        log_processing(message)

        result = Idempotent::ExecuteService.call(
          key:            message.payload["event_id"],
          ttl:            48.hours,
          requester_type: "KafkaOrderCreated"
        ) { Orders::CreateService.call(payload: message.payload) }

        log_failure(message, StandardError.new(result.failure)) if result.failure?
      end
    end
  end
end
```

```ruby
# app/consumers/dlq/monitor_consumer.rb
module Dlq
  class MonitorConsumer < ApplicationConsumer
    def consume
      messages.each do |message|
        # Alert on-call — DLQ messages require manual intervention
        DlqAlertJob.perform_later(
          topic:   topic.name,
          payload: message.raw_payload,
          offset:  message.offset
        )
      end
    end
  end
end
```

## Step 6: Producer Service Objects

```ruby
# app/producers/application_producer.rb
class ApplicationProducer < ApplicationService
  private

  def produce_async(topic:, payload:, partition_key:)
    Karafka.producer.produce_async(
      topic:         topic,
      payload:       serialize(payload),
      partition_key: partition_key.to_s
    )
  rescue WaterDrop::Errors::ProducerNotConnectedError => e
    raise # Let caller handle connection errors
  end

  def serialize(payload)
    payload.merge(published_at: Time.current.iso8601).to_json
  end
end
```

```ruby
# app/producers/order_producer.rb
class OrderProducer < ApplicationProducer
  def initialize(order:)
    @order = order
  end

  def call
    produce_async(
      topic:         "orders-created",
      payload:       order_payload,
      partition_key: order.user_id   # Per-user causal ordering
    )
    Success(order.id)
  rescue StandardError => e
    Failure("Kafka publish failed: #{e.message}")
  end

  private

  attr_reader :order

  def order_payload
    {
      event_id:   SecureRandom.uuid,
      event_type: "order_created",
      order_id:   order.id,
      user_id:    order.user_id,
      amount:     order.total,
      status:     order.status,
      items:      order.order_items.map(&:as_json)
    }
  end
end
```

## Step 7: Producer + Outbox (Guaranteed Delivery)

When delivery must be guaranteed, use the Outbox pattern — never produce directly from a service:

```ruby
# app/services/orders/publish_create_service.rb
module Orders
  class PublishCreateService < ApplicationService
    def initialize(params:)
      @params = params
    end

    def call
      # Write event to outbox — the relay job publishes to Kafka asynchronously
      OutboxMessage.append!(
        event_type:     "order_created",
        aggregate_type: "Order",
        aggregate_id:   SecureRandom.uuid,  # Optimistic ID before DB write
        payload:        params.to_h
      )
      Success(:accepted)
    rescue StandardError => e
      Failure(e.message)
    end

    private

    attr_reader :params
  end
end
```

## Step 8: Consumer Specs (karafka-testing)

```ruby
# spec/consumers/orders/created_consumer_spec.rb
require "rails_helper"
require "karafka/testing/rspec/helpers"

RSpec.describe Orders::CreatedConsumer do
  include Karafka::Testing::RSpec::Helpers

  subject(:consumer) { karafka_consumer_for("orders-created") }

  let(:payload) do
    {
      "event_id"   => SecureRandom.uuid,
      "event_type" => "order_created",
      "order_id"   => 1,
      "user_id"    => 42,
      "amount"     => 10_000
    }
  end

  before do
    allow(Orders::CreateService).to receive(:call).and_return(Success(build(:order)))
  end

  it "calls CreateService for each message" do
    publish_for_consumer(consumer, payload.to_json)
    consumer.consume

    expect(Orders::CreateService).to have_received(:call).with(payload: payload)
  end

  it "wraps execution in idempotency" do
    publish_for_consumer(consumer, payload.to_json)
    2.times { consumer.consume }

    expect(Orders::CreateService).to have_received(:call).once
  end
end
```

## Step 9: Producer Specs

```ruby
# spec/producers/order_producer_spec.rb
RSpec.describe OrderProducer do
  let(:order) { create(:order, user_id: 42, total: 10_000) }

  describe "#call" do
    before do
      allow(Karafka.producer).to receive(:produce_async)
    end

    it "publishes to orders-created topic" do
      result = described_class.call(order: order)

      expect(result).to be_success
      expect(Karafka.producer).to have_received(:produce_async).with(
        hash_including(
          topic:         "orders-created",
          partition_key: "42"
        )
      )
    end

    it "returns Failure when Kafka is unavailable" do
      allow(Karafka.producer).to receive(:produce_async)
        .and_raise(WaterDrop::Errors::ProducerNotConnectedError)

      result = described_class.call(order: order)

      expect(result).to be_failure
      expect(result.failure).to include("Kafka publish failed")
    end
  end
end
```

## Step 10: Topic Management

```bash
# Create / update topics to match karafka.rb routing
bundle exec karafka topics migrate

# Verify connection and routing
bundle exec karafka info

# Start consumers (development)
bundle exec karafka server

# Start specific consumer groups only
bundle exec karafka server --consumer-groups orders payments
```

## Kafka vs Other Approaches

| | Kafka (Karafka) | Solid Queue | Event Dispatcher |
|---|---|---|---|
| **Scope** | Cross-service | Within one Rails app | Within one request |
| **Delivery** | At-least-once | Exactly-once (DB) | Synchronous |
| **Replay** | Yes (infinite) | No | No |
| **Fan-out** | Yes (consumer groups) | No | Yes (multiple handlers) |
| **Ordering** | Per-partition | Per-queue | No guarantee |
| **Use when** | Microservices, audit log | Background jobs | 3+ controller side effects |

## Anti-Patterns to Avoid

1. **Producing without partition key** — events for same entity may be processed out of order
2. **Business logic in consumers** — consumers delegate to service objects
3. **Skipping DLQ** — failed messages are silently dropped without it
4. **Synchronous produce from request thread** — use `produce_async` to avoid blocking
5. **No idempotency in consumers** — at-least-once means your consumer WILL see duplicates
6. **Changing partition key on existing topic** — reorders historical messages; requires migration plan
7. **One consumer class for all events** — each topic gets its own consumer class
