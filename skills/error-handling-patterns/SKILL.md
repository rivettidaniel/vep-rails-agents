---
name: error-handling-patterns
description: Rails error handling - custom exception hierarchy, rescue_from in controllers, consistent API error responses, Sentry integration, and the bridge between dry-monads Failure() and HTTP status codes.
allowed-tools: Read, Write, Edit, Bash
---

# Error Handling Patterns

## Overview

Rails error handling has three layers that work together:

```
Service Object       → Failure("not found")          dry-monads Result
       ↓
Controller           → rescue_from / result.failure?  translate to HTTP
       ↓
ApplicationController → rescue_from AppError          catch-all for exceptions
       ↓
Error Reporter       → Sentry.capture_exception       observability
```

The goal: **explicit, consistent, observable errors** — no silent swallowing, no raw 500s in production, no leaking internal details to clients.

## When to Use

| Scenario | Pattern |
|----------|---------|
| Service returns unexpected failure | `rescue_from` in controller |
| Domain rule violated (not found, unauthorized) | Custom exception class |
| External API / third-party failure | Rescue in service, return `Failure()` |
| Unhandled exception in production | Sentry + generic error response |
| API endpoint — consistent error format | Error serializer / standard JSON shape |

## Workflow Checklist

```
Error Handling Implementation:
- [ ] Step 1: Create custom exception hierarchy
- [ ] Step 2: Add rescue_from to ApplicationController
- [ ] Step 3: Create error responder (JSON or HTML)
- [ ] Step 4: Configure Sentry (or Honeybadger)
- [ ] Step 5: Map dry-monads Failure codes to HTTP statuses
- [ ] Step 6: Write specs for each error path
```

## Step 1: Custom Exception Hierarchy

```ruby
# app/errors/app_error.rb
class AppError < StandardError
  attr_reader :code, :status

  def initialize(message = nil, code: nil, status: :unprocessable_entity)
    super(message)
    @code   = code
    @status = status
  end
end

# Domain errors — raise these from services or controllers
class NotFoundError      < AppError
  def initialize(resource = "Resource")
    super("#{resource} not found", code: :not_found, status: :not_found)
  end
end

class UnauthorizedError  < AppError
  def initialize(msg = "Not authorized")
    super(msg, code: :unauthorized, status: :forbidden)
  end
end

class ValidationError    < AppError
  attr_reader :errors

  def initialize(errors)
    super("Validation failed", code: :validation_error, status: :unprocessable_entity)
    @errors = errors
  end
end

class ConflictError      < AppError
  def initialize(msg = "Conflict")
    super(msg, code: :conflict, status: :conflict)
  end
end

class ExternalServiceError < AppError
  def initialize(service, msg)
    super("#{service} unavailable: #{msg}", code: :external_service_error, status: :bad_gateway)
  end
end
```

## Step 2: rescue_from in ApplicationController

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include ErrorResponder

  rescue_from AppError,                    with: :render_app_error
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from Pundit::NotAuthorizedError,   with: :render_forbidden
  rescue_from ActionController::ParameterMissing, with: :render_bad_request

  private

  def render_app_error(error)
    report_error(error) if error.status == :internal_server_error
    respond_with_error(error.status, error.code, error.message, error.try(:errors))
  end

  def render_not_found(error)
    respond_with_error(:not_found, :not_found, "Resource not found")
  end

  def render_forbidden(error)
    respond_with_error(:forbidden, :forbidden, "Not authorized to perform this action")
  end

  def render_bad_request(error)
    respond_with_error(:bad_request, :bad_request, error.message)
  end
end
```

## Step 3: Error Responder (HTML + JSON)

```ruby
# app/controllers/concerns/error_responder.rb
module ErrorResponder
  extend ActiveSupport::Concern

  private

  def respond_with_error(status, code, message, errors = nil)
    respond_to do |format|
      format.json do
        payload = {
          error: {
            code:    code,
            message: message
          }
        }
        payload[:error][:details] = errors if errors.present?
        render json: payload, status: status
      end

      format.html do
        flash[:alert] = message
        redirect_back(fallback_location: root_path)
      end
    end
  end

  def report_error(error)
    Sentry.capture_exception(error, extra: { user_id: current_user&.id }) if defined?(Sentry)
  end
end
```

**Standard JSON error shape:**
```json
{
  "error": {
    "code": "not_found",
    "message": "Order not found",
    "details": ["field: can't be blank"]
  }
}
```

## Step 4: Sentry Configuration

```ruby
# Gemfile
gem "sentry-ruby"
gem "sentry-rails"

# config/initializers/sentry.rb
Sentry.init do |config|
  config.dsn = Rails.application.credentials.dig(:sentry, :dsn)
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]
  config.traces_sample_rate = Rails.env.production? ? 0.1 : 0.0

  # Don't report expected errors (domain errors, client mistakes)
  config.excluded_exceptions += %w[
    AppError
    ActiveRecord::RecordNotFound
    Pundit::NotAuthorizedError
    ActionController::ParameterMissing
    ActionController::RoutingError
  ]
end
```

## Step 5: dry-monads Failure → HTTP Status

Map `Failure` codes from service objects to HTTP responses in controllers:

```ruby
# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  def create
    result = Orders::CreateService.call(user: current_user, params: order_params)

    if result.success?
      render json: result.value!, status: :created
    else
      # Map Failure codes to HTTP statuses
      handle_service_failure(result)
    end
  end

  private

  def handle_service_failure(result)
    # Option A: String message → 422 with message
    respond_with_error(:unprocessable_entity, :service_error, result.failure)
  end
end
```

**Richer mapping with typed failures:**

```ruby
# Service returns typed failure
module Orders
  class CreateService < ApplicationService
    def call
      return Failure([:not_found, "User not found"]) unless user
      return Failure([:validation, order.errors.full_messages]) unless order.valid?
      return Failure([:payment, "Card declined"]) unless charge_succeeds?

      Success(order)
    end
  end
end

# Controller maps type → HTTP status
def handle_service_failure(result)
  type, message = result.failure

  status, code = case type
                 when :not_found   then [:not_found, :not_found]
                 when :validation  then [:unprocessable_entity, :validation_error]
                 when :payment     then [:payment_required, :payment_failed]
                 when :unauthorized then [:forbidden, :forbidden]
                 else                   [:unprocessable_entity, :service_error]
                 end

  errors = message.is_a?(Array) ? message : nil
  msg    = message.is_a?(Array) ? "Validation failed" : message

  respond_with_error(status, code, msg, errors)
end
```

## Step 6: External Service Error Wrapping

Wrap third-party exceptions in your domain errors so they never leak through:

```ruby
# app/services/payments/charge_service.rb
module Payments
  class ChargeService < ApplicationService
    def call
      response = stripe_client.charge(amount: amount, source: token)
      Success(response.id)
    rescue Stripe::CardError => e
      Failure([:payment, e.message])
    rescue Stripe::RateLimitError, Stripe::APIConnectionError => e
      Rails.logger.error("Stripe unavailable: #{e.message}")
      Sentry.capture_exception(e)
      Failure([:external_service, "Payment service temporarily unavailable"])
    rescue Stripe::StripeError => e
      Rails.logger.error("Stripe error: #{e.message}")
      Sentry.capture_exception(e)
      Failure([:external_service, "Payment failed — please try again"])
    end
  end
end
```

## Testing Error Paths

```ruby
RSpec.describe "OrdersController", type: :request do
  describe "POST /orders" do
    context "when service returns not_found failure" do
      before do
        allow(Orders::CreateService).to receive(:call)
          .and_return(Failure([:not_found, "User not found"]))
      end

      it "returns 404" do
        post orders_path, params: { order: valid_params }, headers: auth_headers
        expect(response).to have_http_status(:not_found)
      end

      it "returns standard error JSON" do
        post orders_path, params: { order: valid_params }, headers: auth_headers
        expect(response.parsed_body.dig("error", "code")).to eq("not_found")
      end
    end

    context "when ActiveRecord::RecordNotFound is raised" do
      before { allow(Order).to receive(:find).and_raise(ActiveRecord::RecordNotFound) }

      it "returns 404" do
        get order_path(0), headers: auth_headers
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
```

## Custom Error Pages (HTML)

```ruby
# config/application.rb
config.exceptions_app = routes

# config/routes.rb
match "/404", to: "errors#not_found",   via: :all
match "/422", to: "errors#unprocessable", via: :all
match "/500", to: "errors#internal",    via: :all

# app/controllers/errors_controller.rb
class ErrorsController < ApplicationController
  def not_found
    render status: :not_found
  end

  def unprocessable
    render status: :unprocessable_entity
  end

  def internal
    render status: :internal_server_error
  end
end
```

## Anti-Patterns to Avoid

1. **Rescuing `StandardError` broadly in services** — only rescue specific, expected exceptions
2. **Letting raw ActiveRecord errors bubble to the view** — always rescue at the controller boundary
3. **Leaking stack traces to API clients** — never render `e.backtrace` in JSON responses
4. **Swallowing errors silently** — `rescue nil` or empty `rescue` blocks hide bugs
5. **Different error shapes per endpoint** — standardize the JSON error envelope across all APIs
6. **Reporting expected errors to Sentry** — configure `excluded_exceptions` to avoid noise
7. **Using string matching on error messages** — use typed failures (`[:not_found, msg]`) for branching, not `result.failure.include?("not found")`
