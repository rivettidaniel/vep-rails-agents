---
name: external-api-integration
description: Structuring Rails services that call external APIs — gateway layer separation, response normalization, error message extraction with dig fallback chains, token refresh management, and transaction coordination with external cleanup on DB failure.
allowed-tools: Read, Write, Edit, Bash
---

# External API Integration

## Overview

External API calls in Rails need a clear three-layer architecture to stay maintainable and testable:

```
Gateway / Client Layer    — HTTP mechanics, auth headers, response normalization
       ↓
Service Layer             — business logic, token management, error mapping
       ↓
Orchestrator / Job        — transaction coordination, retry strategy, side effects
```

Without this separation, API calls end up scattered across models, controllers, and jobs with no consistent error handling.

## Layer 1: Gateway (ApiClient)

The gateway owns everything HTTP: authentication headers, body serialization, error rescue, and response normalization. It never contains business logic.

```ruby
# app/services/cal_com/api_client.rb
module CalCom
  class ApiClient
    BASE_URL = "https://api.cal.com/v2"

    def get(path, headers: {})
      execute(:get, path, headers:)
    end

    def post(path, body:, headers: {})
      execute(:post, path, body:, headers:)
    end

    def patch(path, body:, headers: {})
      execute(:patch, path, body:, headers:)
    end

    def delete(path, headers: {})
      execute(:delete, path, headers:)
    end

    private

    def execute(method, path, body: nil, headers: {})
      response = HTTParty.send(method, "#{BASE_URL}#{path}",
        headers: build_headers(headers),
        body:    prepare_body(body),
        timeout: 10
      )
      response
    rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout => e
      Rails.logger.error("[CalCom] HTTP error: #{e.message}")
      { "error" => e.message, "success?" => false }
    rescue StandardError => e
      Rails.logger.error("[CalCom] Unexpected error: #{e.message}")
      { "error" => I18n.t("errors.external_service_unavailable"), "success?" => false }
    end

    def build_headers(custom_headers)
      default = {
        "Content-Type"  => "application/json",
        "cal-api-version" => "2024-08-13"
      }
      # Custom Authorization header overrides default auth
      custom_headers.key?("Authorization") ? default.merge(custom_headers) : default.merge(auth_header).merge(custom_headers)
    end

    def auth_header
      { "Authorization" => "Bearer #{Settings.cal_com.client_secret}" }
    end

    def prepare_body(body)
      return nil unless body
      body.is_a?(Hash) ? body.to_json : body
    end
  end
end
```

**Key principles:**
- Always set a timeout (never block indefinitely)
- Rescue HTTP errors at this layer, return a normalized error structure
- Never raise from the gateway — callers use monads

## Layer 2: Response Normalization

HTTParty can return different object types depending on the request. Normalize early.

```ruby
# Safe parsed response — never raises
def safe_parse(response)
  return response if response.is_a?(Hash)
  response.respond_to?(:parsed_response) ? response.parsed_response : {}
rescue StandardError
  {}
end

# Successful response check
def api_success?(response)
  parsed = safe_parse(response)
  response.respond_to?(:success?) ? response.success? : parsed["success?"] == true
end
```

**Response shape from Cal.com (example):**
```json
{ "status": "success", "data": { ... } }
{ "status": "error",   "error": { "message": "Not found", "code": "ERROR_CODE" } }
```

## Layer 3: Error Message Extraction

External APIs nest error messages inconsistently. Use a fallback chain:

```ruby
def extract_error_message(response)
  parsed = safe_parse(response)

  parsed.dig("error", "message")           ||
    parsed.dig("error", "details", "message") ||
    parsed["error"]                          ||
    parsed["message"]                        ||
    "Unknown error from external service"
end

# Usage in service
unless api_success?(response)
  return Failure([:external_service, extract_error_message(response)])
end
```

## Token Management and Refresh

OAuth tokens expire. Manage refresh transparently before every API call that needs auth.

```ruby
# app/services/cal_com/auth/token_manager_service.rb
module CalCom
  module Auth
    class TokenManagerService
      EXPIRY_BUFFER_SECONDS = 120  # refresh 2 min before expiry

      def initialize(account:, refresher: CalCom::Auth::RefreshTokensService.new)
        @account   = account
        @refresher = refresher
      end

      def call
        return failure_result(:no_account)   unless @account
        return failure_result(:no_tokens)    unless @account.access_token.present?
        return success_result(refreshed: false) unless needs_refresh?

        refresh_tokens
      end

      private

      def needs_refresh?
        return true unless @account.access_token_expires_at
        @account.access_token_expires_at < (Time.current + EXPIRY_BUFFER_SECONDS)
      end

      def refresh_tokens
        response = @refresher.call(account: @account)
        return failure_result(:refresh_failed) unless response&.success?

        parsed = safe_parse(response)
        @account.apply_token_payload!(parsed["data"])
        success_result(refreshed: true)
      rescue StandardError => e
        Rails.logger.error("[CalCom] Token refresh error: #{e.message}")
        failure_result(:refresh_exception)
      end

      def success_result(refreshed:)
        { success?: true, refreshed?: refreshed, error: nil }
      end

      def failure_result(reason)
        { success?: false, refreshed?: false, reason:, error: reason.to_s }
      end
    end
  end
end
```

**Usage in an API service:**
```ruby
def call(user)
  token_result = CalCom::Auth::TokenManagerService.new(account: user.cal_com_account).call
  return Failure([:token_refresh_failed, token_result[:reason]]) unless token_result[:success?]

  response = @client.get("/bookings", headers: bearer_header(user))
  # ...
end

def bearer_header(user)
  { "Authorization" => "Bearer #{user.cal_com_account.access_token}" }
end
```

## Transaction Coordination with External Cleanup

When you write to both an external API and your DB, do the external call first. If the DB transaction fails, compensate by deleting the external resource.

```ruby
module CalCom
  class CreateManagedUserService < ApplicationService
    include Dry::Monads[:result, :do]

    def call(user)
      # Step 1: External write first (can be compensated)
      api_response = yield create_calcom_user(user)
      external_id  = api_response.dig("data", "id")

      # Step 2: DB transaction (if it fails, compensate the external write)
      ActiveRecord::Base.transaction do
        account = yield persist_account(user, external_id, api_response)
        yield create_schedule_entries(account)
        yield create_event_type(account)
        Success(account)
      rescue StandardError => e
        Rails.logger.error("[CalCom] DB failed after API write, cleaning up #{external_id}: #{e.message}")
        CalCom::ManagedUsers::DeleteService.new(client: @client).call(external_id)
        raise ActiveRecord::Rollback
      end
    end

    private

    def create_calcom_user(user)
      response = @client.post("/managed-users", body: user_payload(user))
      return Failure([:api_error, extract_error_message(response)]) unless api_success?(response)
      Success(safe_parse(response))
    end
  end
end
```

**Rule:** Never commit the DB first and then call the external API — you cannot roll back a committed write.

See `service-composition-patterns` skill for the full orchestrator/transaction pattern.

## Result Return Conventions

When integrating external APIs, choose the right return convention for the context:

| Convention | When to use | Example |
|------------|-------------|---------|
| `Success` / `Failure` (dry-monads) | Service inside a monad chain (`yield`) | `yield charge_card(order)` |
| Hash `{ success?: Boolean, error: }` | Utility/manager called outside monad context | `TokenManagerService#call` |
| Symbol (`:ok`, `:failed`) | Dispatcher that routes webhook events | `Webhooks::Dispatcher#dispatch` |

**Do not mix conventions within the same service chain.** If the orchestrator uses `yield`, all leaf services must return monads.

## HTTP Status Mapping to Domain Errors

Map external API HTTP status codes to your domain errors at the service boundary:

```ruby
def handle_api_response(response)
  case response.code
  when 200, 201 then Success(safe_parse(response)["data"])
  when 401      then Failure([:unauthorized,   "API credentials invalid or expired"])
  when 404      then Failure([:not_found,      "Resource not found in external service"])
  when 422      then Failure([:validation,     extract_error_message(response)])
  when 429      then Failure([:rate_limited,   "Too many requests — retry after #{response.headers['Retry-After']}s"])
  when 500..599 then Failure([:external_service, "#{@service_name} is temporarily unavailable"])
  else               Failure([:unknown_error,  "Unexpected status #{response.code}"])
  end
end
```

## Staggered Job Scheduling (Thundering Herd Prevention)

When syncing many records to an external API, stagger the jobs to avoid rate limits:

```ruby
# app/services/cal_com/rake_task/sync_worker_scheduler.rb
module CalCom
  module RakeTask
    class SyncWorkerScheduler
      INITIAL_DELAY   = 1   # minutes
      DELAY_INCREMENT = 2   # minutes per user

      def schedule_sync_jobs(users)
        results = users.each_with_index.with_object({ scheduled_count: 0, errors: [] }) do |(user, index), acc|
          ok, err = try_schedule(user, index)
          ok ? acc[:scheduled_count] += 1 : acc[:errors] << err
        end
        results.merge(success: results[:errors].empty?)
      end

      private

      def try_schedule(user, index)
        delay = (index * DELAY_INCREMENT) + INITIAL_DELAY
        CalCom::SyncManagedUserWorker.perform_in(delay.minutes, user.id)
        [true, nil]
      rescue StandardError => e
        [false, "Failed to schedule user #{user.id}: #{e.message}"]
      end
    end
  end
end
```

## Anti-Patterns

1. **HTTP calls directly in controllers or models** — always go through a gateway service
2. **No timeout on HTTParty** — every external call can hang indefinitely without one
3. **Raising from the gateway** — callers use monads; rescue at the gateway and return an error hash
4. **Mixing monad and hash returns in the same chain** — orchestrators using `yield` need all collaborators to return monads
5. **DB write before external API call** — you can't roll back a committed write if the API call then fails
6. **No token expiry check** — calling the API with an expired token causes silent 401s; always check before calling
7. **Hardcoded error message paths** — `response["error"]["message"]` raises `NoMethodError` on unexpected shapes; use the dig fallback chain

## Testing

```ruby
# Gateway — stub HTTParty at the HTTP level
RSpec.describe CalCom::ApiClient do
  describe "#post" do
    context "when API returns success" do
      before do
        stub_request(:post, /api.cal.com/).to_return(
          status: 200,
          body:   { status: "success", data: { id: "ext_123" } }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "returns parsed response" do
        response = described_class.new.post("/managed-users", body: { email: "a@b.com" })
        expect(response.parsed_response["data"]["id"]).to eq("ext_123")
      end
    end

    context "when HTTP times out" do
      before { stub_request(:post, /api.cal.com/).to_timeout }

      it "returns error hash without raising" do
        response = described_class.new.post("/managed-users", body: {})
        expect(response).to be_a(Hash)
        expect(response["success?"]).to be false
      end
    end
  end
end

# Service — inject client double
RSpec.describe CalCom::CreateManagedUserService do
  let(:client) { instance_double(CalCom::ApiClient) }

  subject(:service) { described_class.new(client:) }

  context "when API succeeds and DB transaction succeeds" do
    before do
      allow(client).to receive(:post).and_return(
        double(code: 201, parsed_response: { "status" => "success", "data" => { "id" => "ext_1" } })
      )
    end

    it "returns Success with the account" do
      result = service.call(user)
      expect(result).to be_success
      expect(result.value!).to be_a(CalCom::Account)
    end
  end

  context "when DB transaction fails" do
    before do
      allow(client).to receive(:post).and_return(api_success_response)
      allow(client).to receive(:delete)  # cleanup should be called
      allow_any_instance_of(CalCom::Account).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)
    end

    it "calls delete to clean up the external resource" do
      service.call(user)
      expect(client).to have_received(:delete).with("/managed-users/ext_1")
    end
  end
end
```

## Related Skills

| Need | Use |
|------|-----|
| Service composition, Failure propagation, transaction patterns | `service-composition-patterns` skill |
| Guaranteed event delivery after external API call | `outbox-pattern` skill |
| Webhook receiving (signature verification, idempotency) | `webhooks-receiving` skill |
| Operations that must run exactly once (payments, retries) | `idempotency-keys` skill |
| Background jobs calling external APIs | `solid-queue-setup` skill |
| Custom exception hierarchy, Sentry, HTTP error responses | `error-handling-patterns` skill |
