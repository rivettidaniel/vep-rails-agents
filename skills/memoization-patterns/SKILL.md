---
name: memoization-patterns
description: In-process memoization patterns for Rails — instance variable ||=, nil/false-safe memoization, multi-argument caching, request-scoped CurrentAttributes, and the memo_wise gem. Use when avoiding repeated expensive computations within a single object or request lifecycle.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Memoization Patterns for Rails

## Overview

Memoization caches the result of a method call in memory for the lifetime of the object (or request). It is **not** the same as `Rails.cache` (which survives across requests and processes):

| Technique | Scope | Use When |
|-----------|-------|----------|
| `@ivar ||=` | Object instance | Avoid repeating a computation in one request |
| `defined?` guard | Object instance | Return value can be `nil` or `false` |
| Hash memoization | Object instance | Method accepts arguments |
| `CurrentAttributes` | Single request | Share computed value across controllers/views |
| `Rails.cache.fetch` | Cross-request / cross-process | Expensive DB/API call, reuse across requests |

**Rule of thumb:** use memoization when:
1. The method is called more than once in the same object lifecycle.
2. The computation is non-trivial (DB query, calculation, API call).
3. The result is deterministic for the lifetime of the object.

## 1. Basic `||=` Memoization

```ruby
class PostPresenter
  def initialize(post)
    @post = post
  end

  # Without memoization: hits the DB every call
  def comment_count
    @post.comments.count
  end

  # With memoization: DB hit only on first call
  def comment_count
    @comment_count ||= @post.comments.count
  end

  def word_count
    @word_count ||= @post.body.split.size
  end
end
```

## 2. Nil/False-Safe Memoization

`||=` fails silently when the value is `nil` or `false` — it re-executes every time:

```ruby
# ❌ BUG: re-queries every call when published? is false
def published?
  @published ||= @post.published_at.present?
end

# ✅ CORRECT: use defined? guard
def published?
  return @published if defined?(@published)
  @published = @post.published_at.present?
end

# ✅ CORRECT (alternative): explicit nil check
def admin_user
  return @admin_user if instance_variable_defined?(:@admin_user)
  @admin_user = User.find_by(role: :admin)  # may return nil
end
```

**When you need nil/false-safe memoization:**
- Boolean methods (can return `false`)
- `find_by` queries (can return `nil`)
- Any method where the "empty" value is meaningful

## 3. Multi-Argument Memoization

When a method takes arguments, use a Hash keyed by arguments:

```ruby
class PricingService
  # ❌ WRONG: ignores arguments, returns wrong cached value
  def price_for(product, quantity)
    @price ||= calculate_price(product, quantity)
  end

  # ✅ CORRECT: cache per unique argument combination
  def price_for(product, quantity)
    @prices ||= {}
    @prices[[product.id, quantity]] ||= calculate_price(product, quantity)
  end

  private

  def calculate_price(product, quantity)
    product.base_price * quantity * discount_factor(quantity)
  end
end
```

### With keyword arguments:

```ruby
def fetch_events(status:, limit: 10)
  @events_cache ||= {}
  @events_cache[[status, limit]] ||= Event.where(status: status).limit(limit).to_a
end
```

## 4. Memoization in Service Objects

Memoize intermediate results to avoid redundant queries within a single `call`:

```ruby
# app/services/invoices/generate_service.rb
module Invoices
  class GenerateService < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      return Failure("No line items") if line_items.empty?
      return Failure("Invalid total") unless total_cents.positive?

      invoice = Invoice.create!(
        order:       @order,
        user:        user,
        line_items:  line_items,
        total_cents: total_cents
      )
      Success(invoice)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors.full_messages.join(", "))
    end

    private

    # Each called multiple times in `call` — memoized to avoid N+1
    def line_items
      @line_items ||= @order.line_items.includes(:product).to_a
    end

    def user
      @user ||= @order.user
    end

    def total_cents
      @total_cents ||= line_items.sum { |li| li.quantity * li.product.price_cents }
    end
  end
end
```

## 5. Memoization in Query Objects

```ruby
# app/queries/dashboard_stats_query.rb
class DashboardStatsQuery
  def initialize(account:)
    @account = account
  end

  def summary
    {
      events_count:   events_count,
      revenue_cents:  revenue_cents,
      pending_orders: pending_orders_count
    }
  end

  private

  # Memoized — called by multiple summary methods
  def published_events
    @published_events ||= @account.events.published.to_a
  end

  def events_count
    published_events.size
  end

  def revenue_cents
    @revenue_cents ||= @account.orders.completed.sum(:total_cents)
  end

  def pending_orders_count
    @pending_orders_count ||= @account.orders.pending.count
  end
end
```

## 6. Request-Scoped Memoization with `CurrentAttributes`

`CurrentAttributes` lives for the duration of a single request and is reset automatically. Use it to share expensive lookups across controllers, views, and mailers **without passing objects down the call chain**.

```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :account, :plan

  # Computed once per request — not just stored
  def plan
    super || (self.plan = account&.active_plan)
  end
end

# Set in ApplicationController (before_action)
class ApplicationController < ActionController::Base
  before_action :set_current_attributes

  private

  def set_current_attributes
    Current.user    = current_user
    Current.account = current_user&.account
    # Current.plan is computed lazily on first access
  end
end

# Use anywhere without passing it around
class PostsController < ApplicationController
  def create
    # Current.plan already available — no query
    return redirect_to upgrade_path unless Current.plan&.allows?(:post_creation)

    @post = Current.account.posts.build(post_params)
    # ...
  end
end

# In views
# <%= Current.plan.name %>
```

### What belongs in Current vs instance variables:

| Use `Current` | Use `@ivar` |
|---------------|-------------|
| Data shared across layers (controller → view → mailer) | Data local to one object |
| Current user, account, tenant | Computed intermediaries in a service |
| Feature flags / plan limits | Aggregated query results |

## 7. Memoization in Presenters

Presenters format data for views — they are constructed once per render and may call the same formatting logic many times:

```ruby
# app/presenters/event_presenter.rb
class EventPresenter < ApplicationPresenter
  def initialize(event, current_user:)
    @event = event
    @current_user = current_user
  end

  def display_date
    @display_date ||= I18n.l(@event.starts_at, format: :long)
  end

  def vendor_names
    @vendor_names ||= vendors.map(&:name).join(", ")
  end

  def ticket_price_range
    @ticket_price_range ||= build_price_range
  end

  def can_edit?
    return @can_edit if defined?(@can_edit)
    @can_edit = @current_user.admin? || @event.organizer == @current_user
  end

  private

  def vendors
    @vendors ||= @event.vendors.active.order(:name).to_a
  end

  def build_price_range
    prices = @event.ticket_tiers.map(&:price_cents)
    return "Free" if prices.all?(&:zero?)
    "#{format_cents(prices.min)} – #{format_cents(prices.max)}"
  end

  def format_cents(cents)
    Money.from_cents(cents).format
  end
end
```

## 8. `memo_wise` Gem (Advanced)

For classes with many memoized methods, [memo_wise](https://github.com/panorama-ed/memo_wise) provides a cleaner DSL and handles nil/false/multi-argument automatically:

```ruby
# Gemfile
gem "memo_wise"

# Usage
class ReportGenerator
  prepend MemoWise

  def initialize(account:, period:)
    @account = account
    @period  = period
  end

  memo_wise def total_revenue
    @account.orders.completed.where(created_at: @period).sum(:total_cents)
  end

  memo_wise def top_products(limit: 5)
    @account.products.best_selling.limit(limit).to_a
  end

  memo_wise def conversion_rate
    return 0.0 if visits.zero?
    (conversions.to_f / visits * 100).round(2)
  end

  private

  memo_wise def visits
    Analytics.count_visits(account: @account, period: @period)
  end

  memo_wise def conversions
    Analytics.count_conversions(account: @account, period: @period)
  end
end
```

**memo_wise advantages over manual `||=`:**
- Handles `nil` and `false` automatically (no `defined?` needed)
- Handles method arguments automatically (no `@cache ||= {}` needed)
- `reset_memo_wise` / `preset_memo_wise` for testing
- Works with inheritance

## 9. Thread Safety

Instance variable memoization is **thread-safe in Rails** because each request gets its own controller instance. However, **class-level memoization is not thread-safe**:

```ruby
# ❌ DANGEROUS: class-level memoization with mutation
class FeatureFlags
  def self.enabled?(flag)
    @flags ||= load_flags  # Race condition — two threads may call load_flags simultaneously
    @flags[flag]
  end
end

# ✅ SAFE: use Mutex for class-level caching
class FeatureFlags
  MUTEX = Mutex.new

  def self.enabled?(flag)
    MUTEX.synchronize { @flags ||= load_flags }[flag]
  end
end

# ✅ SAFER: use Rails.cache (already thread-safe)
class FeatureFlags
  def self.enabled?(flag)
    Rails.cache.fetch("feature_flags", expires_in: 5.minutes) { load_flags }[flag]
  end
end
```

**Rule:** Only memoize in instance methods or use `Rails.cache` for class/module-level caching.

## 10. When NOT to Memoize

```ruby
# ❌ DON'T memoize methods that depend on mutable state
def current_status
  @current_status ||= @order.reload.status  # stale after first call
end

# ❌ DON'T memoize in long-lived objects (workers, singletons)
class BackgroundWorker
  def process_orders
    # @orders memoized but the worker lives across many jobs — stale data!
    orders = @orders ||= Order.pending.to_a
    # ...
  end
end

# ❌ DON'T memoize when the method is only called once
def single_use_result
  @result ||= complex_calculation  # pointless overhead
end

# ❌ DON'T memoize cheap computations
def formatted_name
  @formatted_name ||= "#{first_name} #{last_name}"  # string concat is already fast
end
```

## 11. Testing Memoized Methods

### Test the result, not the memoization:

```ruby
RSpec.describe EventPresenter do
  let(:event) { create(:event) }
  let(:presenter) { described_class.new(event, current_user: create(:user)) }

  describe "#vendor_names" do
    it "returns comma-separated vendor names" do
      create(:vendor, event: event, name: "Alpha Catering")
      create(:vendor, event: event, name: "Beta Sound")

      expect(presenter.vendor_names).to eq("Alpha Catering, Beta Sound")
    end
  end
end
```

### Test that memoization actually caches (when it matters):

```ruby
RSpec.describe Invoices::GenerateService do
  let(:order) { create(:order, :with_line_items) }
  let(:service) { described_class.new(order: order) }

  it "queries line_items only once even when called multiple times in call" do
    # Call the private method to verify memoization
    2.times { service.send(:line_items) }

    # Verify only 1 query was made by counting queries
    query_count = 0
    counter = ->(*, **) { query_count += 1 }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      service.send(:line_items)
    end

    expect(query_count).to eq(0)  # Already memoized — no new query
  end
end
```

### Reset memoization between examples:

```ruby
RSpec.describe EventPresenter do
  # RSpec creates a fresh `presenter` instance per example via `let`
  # No manual reset needed for instance variable memoization

  # For memo_wise:
  after { presenter.reset_memo_wise }
end
```

### Test nil-safe memoization:

```ruby
RSpec.describe PostPresenter do
  describe "#published?" do
    it "returns false without re-querying" do
      post = create(:post, published_at: nil)
      presenter = described_class.new(post)

      expect(presenter.published?).to be false

      # Simulate a second call — should NOT re-query
      expect(presenter).not_to receive(:published_at)
      expect(presenter.published?).to be false
    end
  end
end
```

## Quick Reference

```ruby
# Basic memoization
@result ||= expensive_call

# Nil/false safe
return @result if defined?(@result)
@result = call_that_may_return_nil_or_false

# With arguments
@cache ||= {}
@cache[arg] ||= expensive_call(arg)

# Multiple keyword args
@cache ||= {}
@cache[[arg1, arg2]] ||= expensive_call(arg1, arg2)

# Request-scoped (cross-layer)
Current.attribute_name ||= compute_once

# Class-level (thread-safe)
Rails.cache.fetch("key", expires_in: 5.minutes) { load_data }
```

## Checklist

- [ ] Method called more than once? (otherwise skip memoization)
- [ ] Return value can be `nil` or `false`? → use `defined?` guard
- [ ] Method accepts arguments? → use Hash as cache key
- [ ] Result shared across controller/view/mailer? → use `CurrentAttributes`
- [ ] Needed across requests? → use `Rails.cache` instead
- [ ] Long-lived object (worker, singleton)? → avoid instance variable memoization
- [ ] Class-level cache? → wrap in Mutex or use `Rails.cache`
- [ ] Many memoized methods in one class? → consider `memo_wise` gem
