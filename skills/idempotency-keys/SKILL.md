---
name: idempotency-keys
description: Idempotency key pattern - deduplicate requests via DB-persisted keys and Redis locks so payments, webhooks, and Kafka consumers are safe to retry. Use when an operation must execute exactly once regardless of retries.
allowed-tools: Read, Write, Edit, Bash
---

# Idempotency Keys Pattern

## Overview

Idempotency makes an operation safe to execute multiple times with the same result. It's essential for:

- **Payment processing** — network timeout retried by client should not double-charge
- **Webhook handlers** — Stripe, GitHub, and other services retry on timeout
- **Kafka consumers** — at-least-once delivery means the same message may arrive twice
- **Background job retries** — `retry_on` reruns the job on failure

**Three-layer defense:**

```
Layer 1: Redis lock          → Prevent concurrent execution of same key
             │
             ▼
Layer 2: DB lookup           → Return cached result if already processed
             │
             ▼
Layer 3: DB unique constraint → Last-resort protection against race conditions
```

## When to Use

| Scenario | Use Idempotency Keys? |
|----------|-----------------------|
| Payment charge endpoint | Yes — critical |
| Webhook handler (Stripe, GitHub) | Yes |
| Kafka consumer (at-least-once) | Yes |
| Background job with retry_on | No — guard with early return (`return if already_done?`) |
| Read (GET) requests | No — reads are inherently idempotent |
| Simple create with unique DB constraint | Maybe — DB constraint alone may suffice |

## Workflow Checklist

```
Idempotency Implementation Progress:
- [ ] Step 1: Create idempotency_records migration
- [ ] Step 2: Create IdempotencyRecord model
- [ ] Step 3: Create Idempotent::ExecuteService
- [ ] Step 4: Add RedisLock utility
- [ ] Step 5: Add middleware to extract Idempotency-Key header (for API endpoints)
- [ ] Step 6: Wrap target service call with Idempotent::ExecuteService
- [ ] Step 7: Schedule cleanup job (IdempotencyRecordsCleanupJob)
- [ ] Step 8: Write specs — first call, duplicate, concurrent, expiry
```

## Step 1: Migration

```ruby
# db/migrate/20240101000001_create_idempotency_records.rb
class CreateIdempotencyRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :idempotency_records do |t|
      t.string   :idempotency_key, null: false
      t.string   :status,          null: false, default: "locked"
      t.text     :cached_result
      t.datetime :completed_at
      t.datetime :expires_at,      null: false
      t.string   :requester_type   # optional: "Payment", "Webhook", etc.
      t.timestamps
    end

    add_index :idempotency_records, :idempotency_key, unique: true
    add_index :idempotency_records, :expires_at
  end
end
```

## Step 2: IdempotencyRecord Model

```ruby
# app/models/idempotency_record.rb
class IdempotencyRecord < ApplicationRecord
  enum :status, {
    locked:    "locked",
    completed: "completed"
  }

  validates :idempotency_key, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :expired, -> { where("expires_at < ?", Time.current) }

  # Atomic lock creation — safe under race conditions
  def self.create_lock!(key, ttl:, requester_type: nil)
    create!(
      idempotency_key: key,
      status:          :locked,
      expires_at:      ttl.from_now,
      requester_type:  requester_type
    )
  rescue ActiveRecord::RecordNotUnique
    find_by!(idempotency_key: key)
  end
end
```

## Step 3: Idempotent::ExecuteService

```ruby
# app/services/idempotent/execute_service.rb
module Idempotent
  class ExecuteService < ApplicationService
    DEFAULT_TTL      = 24.hours
    DEFAULT_LOCK_TTL = 30.seconds

    def initialize(key:, ttl: DEFAULT_TTL, lock_ttl: DEFAULT_LOCK_TTL, requester_type: nil)
      @key            = key
      @ttl            = ttl
      @lock_ttl       = lock_ttl
      @requester_type = requester_type
    end

    def call(&block)
      # Fast path — already processed
      existing = IdempotencyRecord.find_by(idempotency_key: key)
      return deserialize(existing.cached_result) if existing&.completed?

      # Slow path — acquire Redis lock, then re-check under lock
      with_redis_lock do
        record = IdempotencyRecord.find_by(idempotency_key: key)

        if record&.completed?
          deserialize(record.cached_result)
        else
          record ||= IdempotencyRecord.create_lock!(key, ttl: ttl, requester_type: requester_type)
          execute_and_cache(record, &block)
        end
      end
    rescue RedisLockError
      Failure("Request already in progress — retry after #{lock_ttl} seconds")
    rescue StandardError => e
      Rails.logger.error("Idempotent::ExecuteService error [#{key}]: #{e.message}")
      Failure(e.message)
    end

    private

    attr_reader :key, :ttl, :lock_ttl, :requester_type

    def execute_and_cache(record)
      result = yield
      record.update!(
        status:        :completed,
        cached_result: serialize(result),
        completed_at:  Time.current
      )
      result
    end

    def with_redis_lock(&block)
      RedisLock.acquire("idempotency:#{key}", ttl: lock_ttl, &block)
    end

    def serialize(result)
      {
        success: result.success?,
        value:   result.success? ? result.value! : result.failure
      }.to_json
    end

    def deserialize(json)
      data = JSON.parse(json, symbolize_names: true)
      data[:success] ? Success(data[:value]) : Failure(data[:value])
    end
  end
end
```

## Step 4: RedisLock Utility

```ruby
# app/services/redis_lock.rb
class RedisLock
  class LockError < StandardError; end

  def self.acquire(key, ttl: 30.seconds, &block)
    redis = Redis.new(url: ENV.fetch("REDIS_URL"))
    lock_key = "lock:#{key}"

    acquired = redis.set(lock_key, "1", nx: true, ex: ttl.to_i)
    raise LockError, "Could not acquire lock for #{key}" unless acquired

    begin
      block.call
    ensure
      redis.del(lock_key)
    end
  end
end

RedisLockError = RedisLock::LockError
```

## Step 5: API Middleware (for REST endpoints)

```ruby
# app/middleware/idempotency_key_middleware.rb
class IdempotencyKeyMiddleware
  HEADER = "HTTP_IDEMPOTENCY_KEY"

  def initialize(app)
    @app = app
  end

  def call(env)
    env["idempotency_key"] = env[HEADER].presence
    @app.call(env)
  end
end

# config/application.rb
config.middleware.use IdempotencyKeyMiddleware
```

```ruby
# app/controllers/application_controller.rb
def idempotency_key
  request.env["idempotency_key"]
end
```

## Step 6: Usage in Controller or Consumer

**API endpoint (client sends Idempotency-Key header):**

```ruby
# app/controllers/payments_controller.rb
def create
  key = idempotency_key || SecureRandom.uuid

  result = Idempotent::ExecuteService.call(
    key:            key,
    ttl:            24.hours,
    requester_type: "Payment"
  ) { Payments::ChargeService.call(user: current_user, params: payment_params) }

  if result.success?
    render json: result.value!, status: :created
  else
    render json: { error: result.failure }, status: :unprocessable_entity
  end
end
```

**Kafka consumer (message arrives more than once):**

```ruby
# app/consumers/payments_consumer.rb
class PaymentsConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      event_id = message.payload["event_id"]

      result = Idempotent::ExecuteService.call(
        key:            event_id,
        ttl:            48.hours,
        requester_type: "KafkaPayment"
      ) { Payments::ProcessService.call(payload: message.payload) }

      Rails.logger.warn("Payment processing failed: #{result.failure}") if result.failure?
    end
  end
end
```

## Step 7: Cleanup Job

```ruby
# app/jobs/idempotency_records_cleanup_job.rb
class IdempotencyRecordsCleanupJob < ApplicationJob
  queue_as :maintenance

  def perform
    deleted = IdempotencyRecord.expired.delete_all
    Rails.logger.info("Idempotency cleanup: #{deleted} expired records removed")
  end
end
```

```yaml
# config/recurring.yml
idempotency_cleanup:
  class: IdempotencyRecordsCleanupJob
  schedule: every day at midnight
  queue: maintenance
```

## Testing

```ruby
RSpec.describe Idempotent::ExecuteService do
  include Dry::Monads[:result]

  let(:key) { SecureRandom.uuid }

  def call_service(&block)
    described_class.call(key: key, ttl: 1.hour, &block)
  end

  it "executes the block on first call and returns Success" do
    result = call_service { Success("payment_id_123") }
    expect(result).to be_success
    expect(result.value!).to eq("payment_id_123")
  end

  it "does not re-execute on duplicate call — returns cached result" do
    counter = 0
    2.times { call_service { counter += 1; Success("done") } }
    expect(counter).to eq(1)
  end

  it "returns the same result on duplicate call" do
    call_service { Success("first_result") }
    result = call_service { Success("this_should_not_run") }
    expect(result.value!).to eq("first_result")
  end

  it "caches Failure results too — does not re-execute failed operations" do
    counter = 0
    2.times { call_service { counter += 1; Failure("invalid card") } }
    expect(counter).to eq(1)
  end

  it "persists an IdempotencyRecord on first call" do
    expect { call_service { Success("ok") } }
      .to change(IdempotencyRecord, :count).by(1)
  end

  it "does not create a second record on duplicate call" do
    call_service { Success("ok") }
    expect { call_service { Success("ok") } }
      .not_to change(IdempotencyRecord, :count)
  end
end
```

## Anti-Patterns to Avoid

1. **Idempotency without TTL** — records accumulate forever; always set `expires_at`
2. **Storing sensitive data in `cached_result`** — tokens, passwords, full card numbers must never be cached
3. **Skipping Redis lock** — two concurrent requests with same key will both execute before either writes the DB record
4. **Using job's `retry_on` as idempotency** — jobs need early-return guards, not this pattern
5. **Re-raising inside the idempotent block** — catch and return `Failure()` so the result can be cached
6. **Idempotency key from untrusted input without validation** — validate UUID format to prevent cache poisoning
