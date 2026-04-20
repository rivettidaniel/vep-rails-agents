---
name: service-composition-patterns
description: How to compose multiple service objects — Leaf vs Orchestrator distinction, self.build() DI factory, Failure propagation with do-notation yield, side effect placement rules, and transaction coordination with external cleanup.
allowed-tools: Read, Write, Edit, Bash
---

# Service Composition Patterns

## Overview

As features grow, services compose each other. Without a clear model, side effects leak into leaf services, failures disappear silently, and tests become hard to isolate.

The core distinction:

```
Leaf Service    — one responsibility, no side effects, always returns Success/Failure
Orchestrator    — coordinates leaf services, owns flow, manages side effects and transactions
```

## Leaf vs Orchestrator

**Leaf Service** — does exactly one thing:
- Validates input
- Queries the database
- Calls an external API and normalizes the response
- Transforms data
- ❌ No emails, no job enqueuing, no multi-model writes

**Orchestrator Service** — coordinates leaf services:
- Calls 2+ leaf services in sequence via `yield`
- Controls transaction boundaries
- Decides where side effects go (or delegates up to the controller)
- Returns an aggregated result

## Pattern 1: Dependency Injection with `self.build()`

Inject all dependencies via a factory method — never hardcode collaborators inside `call`. This makes every service independently testable.

```ruby
# app/services/auth/jwt_authenticator.rb
module Auth
  class JwtAuthenticator < ApplicationService
    include Dry::Monads[:result, :do]

    def self.build
      new(
        decoder:         Auth::JwtDecoder.new,
        user_finder:     Auth::UserFinder.new,
        locale_resolver: Auth::LocaleResolver.new
      )
    end

    def initialize(decoder:, user_finder:, locale_resolver:)
      @decoder         = decoder
      @user_finder     = user_finder
      @locale_resolver = locale_resolver
    end

    def call(token:, locale: nil)
      decoded  = yield @decoder.call(token)
      user     = yield @user_finder.call(decoded)
      eff_locale = yield @locale_resolver.call(user:, locale:)
      Success({ user:, locale: eff_locale })
    end
  end
end
```

**In tests — inject doubles, never stub internal calls:**
```ruby
RSpec.describe Auth::JwtAuthenticator do
  subject(:service) do
    described_class.new(
      decoder:         instance_double(Auth::JwtDecoder,     call: Success(decoded_payload)),
      user_finder:     instance_double(Auth::UserFinder,     call: Success(user)),
      locale_resolver: instance_double(Auth::LocaleResolver, call: Success("es"))
    )
  end

  it "returns Success when all steps succeed" do
    expect(service.call(token: "valid")).to be_success
  end

  it "short-circuits when decoder fails" do
    allow(service.instance_variable_get(:@decoder))
      .to receive(:call).and_return(Failure([:invalid_token, "expired"]))
    expect(service.call(token: "bad")).to be_failure
  end
end
```

## Pattern 2: Failure Propagation with do-notation

`yield` on a `Failure` short-circuits the entire method and returns that `Failure` to the caller — no `if/else`, no nested conditions.

```ruby
module Payments
  class CheckoutService < ApplicationService
    include Dry::Monads[:result, :do]

    def call(user:, cart:, payment_token:)
      order   = yield Orders::CreateService.call(user:, cart:)
      charge  = yield Payments::ChargeService.call(order:, token: payment_token)
      receipt = yield Receipts::GenerateService.call(order:, charge:)
      Success({ order:, charge:, receipt: })
    end
  end
end
```

If `ChargeService` returns `Failure([:payment, "Card declined"])`, `CheckoutService#call` immediately returns that same `Failure` — `GenerateService` is never called.

**Typed failures carry context up the chain:**
```ruby
module Auth
  class UserFinder < ApplicationService
    def call(decoded_token)
      user = User.find_by(email: decoded_token[:email])
      return Failure([:user_not_found, decoded_token]) unless user
      Success(user)
    end
  end
end
# The orchestrator propagates Failure([:user_not_found, ...]) transparently via yield
```

## Pattern 3: Side Effect Placement

Side effects (emails, jobs, external writes, analytics) belong to the **caller**, not to leaf services.

```
Caller level        Where the side effect lives
─────────────────────────────────────────────────
1-2 effects         Controller — explicit after result.success?
3+ effects          @event_dispatcher_agent — dispatch event
Transactional       Orchestrator — inside transaction block only
```

```ruby
# ❌ WRONG — side effect inside leaf service
module Auth
  class SignInEventTracker
    def call(user:, registration:)
      user.sign_in_events.create!(...)      # DB write in a leaf
      AnalyticsService.track(:sign_in, user) # External call in a leaf
    end
  end
end

# ✅ CORRECT — controller handles side effects
result = Auth::JwtAuthenticator.build.call(token:, locale:)

if result.success?
  user, locale = result.value!.values_at(:user, :locale)
  SignInEventJob.perform_later(user.id)   # Side effect in the controller
  render json: { token: issue_jwt(user) }
end
```

## Pattern 4: Transaction Coordination with External Cleanup

When a write touches both a DB and an external API, do the external call first. If the DB transaction fails, clean up the external resource.

```ruby
module CalCom
  class CreateManagedUserService < ApplicationService
    include Dry::Monads[:result, :do]

    def call(user)
      # 1. External call first — can be compensated if DB fails
      external_id = yield create_external_user(user)

      # 2. DB transaction second
      ActiveRecord::Base.transaction do
        account = yield persist_account(user, external_id)
        yield create_schedule(account)
        yield create_event_type(account)
        Success(account)
      rescue StandardError
        delete_external_user(external_id)   # compensate on DB failure
        raise ActiveRecord::Rollback
      end
    end
  end
end
```

**Rule:** Never commit the DB first and then call the external API — you cannot roll back a committed write.

## Pattern 5: ErrorsHandler — Mapping Failures to HTTP

An `ErrorsHandler` is a valid leaf service for translating `Failure` atoms into HTTP response structures. Its **only** job is translation.

```ruby
module Auth
  class ErrorsHandler
    FAILURE_MAP = {
      user_not_found:              { status: :not_found,            code: :user_not_found },
      invalid_token:               { status: :unauthorized,          code: :invalid_token },
      language_selection_required: { status: :unprocessable_entity, code: :language_required }
    }.freeze

    def self.call(failure)
      type     = failure.is_a?(Array) ? failure.first : failure
      mapping  = FAILURE_MAP.fetch(type, { status: :unprocessable_entity, code: :service_error })
      { status: mapping[:status], payload: { success: false, error: mapping[:code] } }
    end
  end
end

# Controller
result = Auth::JwtAuthenticator.build.call(token:, locale:)
if result.success?
  render json: { user: result.value! }, status: :ok
else
  resp = Auth::ErrorsHandler.call(result.failure)
  render json: resp[:payload], status: resp[:status]
end
```

**ErrorsHandler must NEVER:** persist to DB, send emails, enqueue jobs, or call external services.

See `error-handling-patterns` skill for the full error hierarchy, Sentry integration, and typed failure mapping.

## Anti-Patterns

1. **Side effects in leaf services** — events, emails, analytics inside a `call` that should be pure
2. **Hardcoded collaborators** — `Auth::JwtDecoder.new` inside `call` instead of injected via `self.build()`
3. **Swallowing failures** — wrapping `yield` in `rescue` and returning `Success` when it fails
4. **ErrorsHandler with side effects** — sending emails or creating records inside the failure mapper
5. **In-place mutation** — service modifies the passed object (`user.assign_attributes(...)`) and also returns it, making data flow opaque
6. **Missing rescue on transaction** — `ActiveRecord::RecordInvalid` bubbling out of the `transaction` block uncaught
7. **Missing do-notation include** — using `yield` without `include Dry::Monads[:result, :do]` causes silent bugs

## Related Skills

| Need | Use |
|------|-----|
| Full `ApplicationService` base class + dry-monads reference | `rails-service-object` skill |
| Custom exception hierarchy, Sentry, HTTP error responses | `error-handling-patterns` skill |
| Service calls external API (gateway layer, token refresh) | `external-api-integration` skill |
| Service modifies shared rows concurrently | `database-locking` skill |
| 3+ side effects from one action | `event-dispatcher-pattern` skill |
