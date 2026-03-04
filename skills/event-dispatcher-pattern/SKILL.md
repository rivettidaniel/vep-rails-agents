# Event Dispatcher Pattern in Rails

## Overview

The Event Dispatcher pattern (also called Event Bus or Application Events) decouples side effects from business logic by dispatching named events from controllers. Handlers registered elsewhere respond to those events independently.

**Key Insight**: Side effects should be explicit and visible in controllers, but decoupled from them. The controller calls `dispatch()` — it does NOT call each side effect directly.

## Core Components

```
Controller → ApplicationEvent.dispatch(:event_name, record)
                      ↓
             Handler 1 (email)
             Handler 2 (notification)
             Handler 3 (analytics)
             Handler 4 (broadcast)
```

1. **ApplicationEvent** — Central dispatcher; stores handlers per event name
2. **Event Handlers** — Procs registered with `.on`; each handles ONE side effect
3. **Controller** — Dispatches events AFTER successful business operations
4. **Initializer** — Loads all event handler files on boot

## When to Use Event Dispatcher

✅ **Use Event Dispatcher when:**

- **3+ side effects** after a save/update/delete (emails, notifications, analytics, cache, broadcasts)
- **Adding/removing side effects** without touching the controller
- **Cross-cutting concerns** — analytics, logging, cache invalidation
- **Independent side effects** — each can succeed or fail without affecting the others

❌ **Don't use Event Dispatcher for:**

- 1-2 simple side effects (just call them directly in the controller)
- Business logic (use Service Objects — logic must run in order, failure must halt)
- Sequential operations that depend on each other (handlers run independently)
- Dispatching from models or background jobs

## Rule: Handlers Are Pure Side Effects

**Handlers must NEVER contain business logic.**

Business logic (model updates, calculations, state transitions) happens **before** dispatch, in the controller or service. Handlers only trigger notifications, emails, broadcasts, cache invalidation, and analytics.

```ruby
# ❌ Business logic in handler
ApplicationEvent.on(:order_flagged) do |order|
  order.update!(flagged_at: Time.current)  # Model update = business logic
  order.user.increment_reputation!(-10)    # Calculation = business logic
end

# ✅ Business logic in controller, handler is pure side effect
# Controller:
@order.update!(flagged_at: Time.current)
ApplicationEvent.dispatch(:order_flagged, @order)

# Handler:
ApplicationEvent.on(:order_flagged) do |order|
  ModerationMailer.flagged(order).deliver_later  # Pure side effect ✅
end
```

## Rule: Dispatch Only from Controllers

Events are dispatched explicitly from controllers (or services), never from models.

```ruby
# ❌ Dispatch from model (hidden, automatic — same problems as callbacks)
class Order < ApplicationRecord
  after_create_commit -> { ApplicationEvent.dispatch(:order_created, self) }
end

# ✅ Dispatch from controller (explicit, visible)
class OrdersController < ApplicationController
  def create
    if @order.save
      ApplicationEvent.dispatch(:order_created, @order)
      redirect_to @order
    end
  end
end
```

## Implementation

### Step 1: ApplicationEvent Base Class

```ruby
# app/events/application_event.rb
class ApplicationEvent
  @handlers = Hash.new { |hash, key| hash[key] = [] }
  @mutex = Mutex.new

  class << self
    def on(event_name, &block)
      raise ArgumentError, "Event name must be a symbol" unless event_name.is_a?(Symbol)
      raise ArgumentError, "Handler block required" unless block

      @mutex.synchronize { @handlers[event_name] << block }
    end

    def dispatch(event_name, *args)
      handlers = @mutex.synchronize { @handlers[event_name].dup }

      handlers.each do |handler|
        handler.call(*args)
      rescue StandardError => e
        Rails.logger.error("Event handler error [#{event_name}]: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
      end
    end

    def handlers_for(event_name)
      @mutex.synchronize { @handlers[event_name].dup }
    end

    def clear_all
      @mutex.synchronize { @handlers.clear }
    end

    def clear(event_name)
      @mutex.synchronize { @handlers.delete(event_name) }
    end
  end
end
```

### Step 2: Event Handler Files

```ruby
# app/events/user_events.rb
module UserEvents
  ApplicationEvent.on(:user_registered) do |user|
    WelcomeMailer.welcome(user).deliver_later
  end

  ApplicationEvent.on(:user_registered) do |user|
    Analytics.track("user_registered", user_id: user.id)
  end

  ApplicationEvent.on(:user_registered) do |user|
    SlackNotifier.notify_team("New user: #{user.email}")
  end

  ApplicationEvent.on(:user_registered) do |user|
    CrmService.create_contact(user)
  end
end
```

### Step 3: Load on Boot

```ruby
# config/initializers/events.rb
Dir[Rails.root.join("app/events/**/*_events.rb")].each { |f| require f }
```

### Step 4: Dispatch from Controller

```ruby
class UsersController < ApplicationController
  def create
    @user = User.new(user_params)

    if @user.save
      # One explicit line replaces 4+ inline side effects
      ApplicationEvent.dispatch(:user_registered, @user)
      redirect_to @user, notice: "Welcome!"
    else
      render :new, status: :unprocessable_entity
    end
  end
end
```

## File Structure

```
app/
├── events/
│   ├── application_event.rb      # Dispatcher base class
│   ├── user_events.rb            # User-related handlers
│   ├── order_events.rb           # Order-related handlers
│   └── entity_events.rb          # Entity-related handlers
config/
└── initializers/
    └── events.rb                 # Loads all event files on boot

spec/
└── events/
    ├── user_events_spec.rb
    └── order_events_spec.rb
```

## Async Handlers (Slow Operations)

Slow handlers should enqueue jobs, not run inline:

```ruby
# ❌ Slow inline handler blocks request
ApplicationEvent.on(:report_generated) do |report|
  PdfService.render(report)  # Takes 3 seconds
end

# ✅ Enqueue a job instead
ApplicationEvent.on(:report_generated) do |report|
  RenderReportJob.perform_later(report.id)
end
```

## Testing

### Test Handlers in Isolation

```ruby
# spec/events/user_events_spec.rb
require "rails_helper"

RSpec.describe "UserEvents" do
  before { ApplicationEvent.clear(:user_registered) }

  describe ":user_registered" do
    let(:user) { create(:user) }

    it "sends welcome email" do
      ApplicationEvent.on(:user_registered) { |u| WelcomeMailer.welcome(u).deliver_later }

      expect {
        ApplicationEvent.dispatch(:user_registered, user)
      }.to have_enqueued_mail(WelcomeMailer, :welcome)
    end

    it "continues when one handler fails" do
      called = false

      ApplicationEvent.on(:user_registered) { raise "boom" }
      ApplicationEvent.on(:user_registered) { called = true }

      expect { ApplicationEvent.dispatch(:user_registered, user) }.not_to raise_error
      expect(called).to be true
    end
  end
end
```

### Test Controllers Dispatch the Right Event

```ruby
# spec/requests/users_spec.rb
describe "POST /users" do
  it "dispatches user_registered event on success" do
    expect(ApplicationEvent).to receive(:dispatch).with(:user_registered, an_instance_of(User))
    post users_path, params: { user: valid_params }
  end

  it "does not dispatch event on failure" do
    expect(ApplicationEvent).not_to receive(:dispatch)
    post users_path, params: { user: invalid_params }
  end
end
```

## When to Use Each Approach

| Side Effects | Approach |
|---|---|
| 1–2 actions | Direct in controller (simpler, no overhead) |
| 3+ actions | Event Dispatcher (decoupled, easy to extend) |
| Business logic | Service Object (ordered steps, failure halts) |
| Sequential steps | Service Object (guarantees order) |

## Comparison with Similar Patterns

| | Event Dispatcher | Observer (Callbacks) | Chain of Responsibility |
|---|---|---|---|
| **Trigger** | Explicit `dispatch()` | Automatic on save | Request passed along chain |
| **Who runs** | All handlers | All observers | First handler that claims it |
| **Visibility** | Controller (explicit) | Model (hidden) | Chain builder |
| **Order guarantee** | No | No | Yes (chain order) |
| **Use case** | Decoupled side effects | Auto-magic (avoid this) | Conditional routing |
