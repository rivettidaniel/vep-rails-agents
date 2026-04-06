---
name: webhooks-receiving
description: Receiving and processing webhooks from third-party services (Stripe, GitHub, etc.) — signature verification, raw body preservation, idempotent processing, async handling with jobs. Use when integrating any service that sends HTTP callbacks.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Receiving Webhooks in Rails

## Overview

Webhooks arrive as HTTP POST requests from external services. Three non-negotiable rules:

1. **Verify the signature** — reject anything unsigned or tampered
2. **Respond fast** — return `200 OK` immediately, process async in a job
3. **Process idempotently** — the same event can arrive more than once

## Architecture

```
External Service → POST /webhooks/stripe
                      ↓
               WebhooksController
               1. Verify signature    → 401 if invalid
               2. Persist raw event   → idempotency guard
               3. Enqueue job         → 200 OK immediately
                      ↓
               ProcessWebhookJob
               4. Route by event type
               5. Call domain service
```

## Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  namespace :webhooks do
    post "stripe",  to: "stripe#receive"
    post "github",  to: "github#receive"
  end
end
```

## Preserve Raw Body (CRITICAL)

Rails parses JSON bodies and discards the raw string. Signature verification needs the **original raw bytes**. Configure middleware before parsing:

```ruby
# config/application.rb
config.middleware.insert_before ActionDispatch::ParamsParser,
  Rack::RawUpload, paths: %w[/webhooks]

# OR — simpler approach with a custom middleware
```

Simpler: store raw body in a before_action:

```ruby
# app/controllers/webhooks/base_controller.rb
module Webhooks
  class BaseController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :store_raw_body

    private

    def store_raw_body
      request.body.rewind
      @raw_body = request.body.read
      request.body.rewind
    end

    def render_unauthorized
      head :unauthorized
    end

    def render_ok
      head :ok
    end
  end
end
```

## Stripe Webhooks

```ruby
# app/controllers/webhooks/stripe_controller.rb
module Webhooks
  class StripeController < BaseController
    def receive
      event = verify_stripe_signature
      return render_unauthorized unless event

      # Guard against duplicates BEFORE enqueuing
      return render_ok if WebhookEvent.exists?(external_id: event.id)

      WebhookEvent.create!(
        provider:    "stripe",
        external_id: event.id,
        event_type:  event.type,
        payload:     event.to_json,
        status:      "pending"
      )

      ProcessStripeWebhookJob.perform_later(event.id)
      render_ok
    end

    private

    def verify_stripe_signature
      Stripe::Webhook.construct_event(
        @raw_body,
        request.headers["Stripe-Signature"],
        webhook_secret
      )
    rescue Stripe::SignatureVerificationError
      nil
    end

    def webhook_secret
      Rails.application.credentials.dig(:stripe, :webhook_secret)
    end
  end
end
```

## GitHub Webhooks

```ruby
# app/controllers/webhooks/github_controller.rb
module Webhooks
  class GithubController < BaseController
    def receive
      return render_unauthorized unless valid_signature?

      event_type = request.headers["X-GitHub-Event"]
      delivery   = request.headers["X-GitHub-Delivery"]

      return render_ok if WebhookEvent.exists?(external_id: delivery)

      WebhookEvent.create!(
        provider:    "github",
        external_id: delivery,
        event_type:  event_type,
        payload:     @raw_body,
        status:      "pending"
      )

      ProcessGithubWebhookJob.perform_later(delivery)
      render_ok
    end

    private

    def valid_signature?
      secret   = Rails.application.credentials.dig(:github, :webhook_secret)
      expected = "sha256=#{OpenSSL::HMAC.hexdigest('sha256', secret, @raw_body)}"
      received = request.headers["X-Hub-Signature-256"].to_s
      ActiveSupport::SecurityUtils.secure_compare(expected, received)
    end
  end
end
```

## WebhookEvent Model (idempotency store)

```ruby
# Migration
class CreateWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_events do |t|
      t.string  :provider,    null: false
      t.string  :external_id, null: false
      t.string  :event_type,  null: false
      t.text    :payload,     null: false
      t.string  :status,      null: false, default: "pending"
      t.text    :error_message
      t.timestamps
    end

    add_index :webhook_events, [:provider, :external_id], unique: true
  end
end

# app/models/webhook_event.rb
class WebhookEvent < ApplicationRecord
  enum :status, { pending: "pending", processed: "processed", failed: "failed" }

  validates :provider, :external_id, :event_type, :payload, presence: true
end
```

## Processing Job

```ruby
# app/jobs/process_stripe_webhook_job.rb
class ProcessStripeWebhookJob < ApplicationJob
  queue_as :webhooks

  def perform(event_id)
    webhook_event = WebhookEvent.find_by!(provider: "stripe", external_id: event_id)

    # Guard: already processed (job may be retried by Solid Queue)
    return if webhook_event.processed?

    event  = Stripe::Event.construct_from(JSON.parse(webhook_event.payload))
    result = route_event(event)

    if result&.failure?
      webhook_event.update!(status: "failed", error_message: result.failure)
      raise result.failure  # re-raise so Solid Queue retries
    else
      webhook_event.update!(status: "processed")
    end
  end

  private

  # Returns a dry-monads Result from the service, or nil for unhandled events
  def route_event(event)
    case event.type
    when "payment_intent.succeeded"
      Payments::ConfirmService.call(stripe_payment_intent_id: event.data.object.id)
    when "payment_intent.payment_failed"
      Payments::FailService.call(stripe_payment_intent_id: event.data.object.id)
    when "customer.subscription.deleted"
      Subscriptions::CancelService.call(stripe_subscription_id: event.data.object.id)
    else
      Rails.logger.info "Unhandled Stripe event: #{event.type}"
      nil
    end
  end
end
```

## Testing

```ruby
RSpec.describe Webhooks::StripeController, type: :request do
  let(:secret) { "whsec_test_secret" }
  let(:payload) { { id: "evt_123", type: "payment_intent.succeeded", data: { object: {} } }.to_json }
  let(:timestamp) { Time.now.to_i }
  let(:signature) do
    signed_payload = "#{timestamp}.#{payload}"
    hmac = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
    "t=#{timestamp},v1=#{hmac}"
  end

  before do
    allow(Rails.application.credentials).to receive(:dig)
      .with(:stripe, :webhook_secret).and_return(secret)
  end

  it "processes valid webhook and returns 200" do
    expect {
      post "/webhooks/stripe",
           params: payload,
           headers: {
             "Content-Type"     => "application/json",
             "Stripe-Signature" => signature
           }
    }.to change(WebhookEvent, :count).by(1)
       .and have_enqueued_job(ProcessStripeWebhookJob)

    expect(response).to have_http_status(:ok)
  end

  it "rejects invalid signature with 401" do
    post "/webhooks/stripe",
         params: payload,
         headers: {
           "Content-Type"     => "application/json",
           "Stripe-Signature" => "invalid"
         }

    expect(response).to have_http_status(:unauthorized)
    expect(WebhookEvent.count).to eq(0)
  end

  it "ignores duplicate events (idempotency)" do
    create(:webhook_event, provider: "stripe", external_id: "evt_123")

    post "/webhooks/stripe",
         params: payload,
         headers: { "Content-Type" => "application/json", "Stripe-Signature" => signature }

    expect(response).to have_http_status(:ok)
    expect(WebhookEvent.count).to eq(1)  # no duplicate
    expect(ProcessStripeWebhookJob).not_to have_been_enqueued
  end
end
```

## Checklist

- [ ] `skip_before_action :verify_authenticity_token` on webhook controllers
- [ ] Raw body preserved before JSON parsing
- [ ] Signature verified with `secure_compare` (timing-safe)
- [ ] `WebhookEvent` table with `unique index` on `[provider, external_id]`
- [ ] Controller returns `200 OK` immediately — no processing inline
- [ ] Job guards against already-processed events (idempotency)
- [ ] Job re-raises errors so Solid Queue retries
- [ ] Specs cover: valid, invalid signature, duplicate event
- [ ] Webhook secret stored in Rails credentials (never hardcoded)
