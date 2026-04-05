---
name: soft-delete-patterns
description: Soft delete with the Discard gem - discarded_at column, kept/discarded scopes, cascade, and Pundit integration. Use when records must be deactivated without permanent deletion (audit trail, referential integrity, recovery).
allowed-tools: Read, Write, Edit, Bash
---

# Soft Delete Patterns

## Overview

Soft delete marks records as deleted without removing them from the database. This preserves:
- **Audit trail** — who deleted what and when
- **Referential integrity** — foreign keys stay valid
- **Recovery** — deleted records can be restored
- **Reporting** — historical data remains queryable

**Use `Discard` gem** (not Paranoia). Paranoia overrides `ActiveRecord::Base.destroy` globally — Discard is explicit and predictable.

```
Hard delete:  DELETE FROM orders WHERE id = 1   ← gone forever
Soft delete:  UPDATE orders SET discarded_at = NOW() WHERE id = 1  ← still there, hidden
```

## When to Use

| Scenario | Soft Delete? |
|----------|--------------|
| Users (GDPR may require hard delete) | Careful — check legal requirements |
| Orders, invoices, transactions | Yes — audit trail required |
| Posts, comments, content | Yes — moderation and recovery |
| Products, catalog items | Yes — orders reference them |
| Join records (taggings, memberships) | Usually — depends on domain |
| Sessions, tokens, logs | No — hard delete or TTL expiry |

## Workflow Checklist

```
Soft Delete Implementation:
- [ ] Step 1: Add discard gem
- [ ] Step 2: Migration — add discarded_at column
- [ ] Step 3: Include Discard::Model in model
- [ ] Step 4: Update default scope (only kept records)
- [ ] Step 5: Update Pundit policy (discarded records off-limits)
- [ ] Step 6: Controller — discard instead of destroy
- [ ] Step 7: Handle cascade (discard associations)
- [ ] Step 8: Write specs — discard, restore, cascade, scope
```

## Step 1: Gem

```ruby
# Gemfile
gem "discard", "~> 1.4"
```

## Step 2: Migration

```ruby
class AddDiscardedAtToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :discarded_at, :datetime
    add_index  :orders, :discarded_at
  end
end
```

## Step 3: Model

```ruby
# app/models/order.rb
class Order < ApplicationRecord
  include Discard::Model

  # default_scope { kept } is set automatically by Discard
  # Override if you need a different default:
  # self.discard_column = :deleted_at  (if column name differs)

  belongs_to :user
  has_many   :order_items, dependent: :destroy

  validates :amount_cents, presence: true, numericality: { greater_than: 0 }
end
```

**Discard adds these automatically:**

```ruby
# Scopes
Order.kept       # WHERE discarded_at IS NULL  (default)
Order.discarded  # WHERE discarded_at IS NOT NULL
Order.with_discarded  # No filter — all records

# Instance methods
order.discard        # Sets discarded_at = Time.current
order.undiscard      # Sets discarded_at = nil
order.discard!       # Same but raises on failure
order.undiscard!
order.discarded?     # true if discarded_at is set
order.kept?          # true if discarded_at is nil
```

## Step 4: Default Scope Behavior

Discard sets `default_scope { kept }`. This means:

```ruby
Order.all          # → only kept orders (WHERE discarded_at IS NULL)
Order.find(id)     # → raises RecordNotFound if discarded
Order.discarded    # → only discarded orders
Order.with_discarded  # → all records regardless of state
```

**Important — associations follow the default scope:**

```ruby
user.orders          # → only kept orders
user.orders.discarded  # → only discarded orders belonging to user
Order.with_discarded.find(id)  # → find including discarded
```

## Step 5: Pundit Policy

```ruby
# app/policies/order_policy.rb
class OrderPolicy < ApplicationPolicy
  def show?
    user&.admin? || (record.kept? && record.user == user)
  end

  def destroy?
    user&.admin? || (record.kept? && record.user == user)
  end

  def restore?
    user&.admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      # Admins can see discarded records; users only see kept
      user&.admin? ? scope.with_discarded : scope.kept
    end
  end
end
```

## Step 6: Controller

```ruby
# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  def destroy
    @order = Order.find(params[:id])
    authorize @order

    result = Orders::DiscardService.call(order: @order, discarded_by: current_user)

    if result.success?
      redirect_to orders_path, notice: "Order removed"
    else
      redirect_to @order, alert: result.failure
    end
  end

  def restore
    @order = Order.with_discarded.find(params[:id])
    authorize @order, :restore?

    result = Orders::RestoreService.call(order: @order)

    if result.success?
      redirect_to @order, notice: "Order restored"
    else
      redirect_to orders_path, alert: result.failure
    end
  end
end
```

```ruby
# app/services/orders/discard_service.rb
module Orders
  class DiscardService < ApplicationService
    def initialize(order:, discarded_by:)
      @order        = order
      @discarded_by = discarded_by
    end

    def call
      return Failure("Order is already discarded") if order.discarded?

      ActiveRecord::Base.transaction do
        order.discard!
        # Cascade to associations (see Step 7)
        order.order_items.each(&:discard!)

        # Audit log (optional)
        AuditLog.create!(
          action:      :discarded,
          record_type: "Order",
          record_id:   order.id,
          user:        discarded_by
        )
      end

      Success(order)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.message)
    end

    private

    attr_reader :order, :discarded_by
  end
end
```

## Step 7: Cascade Soft Deletes

Discard does NOT cascade automatically. Handle explicitly in the service:

```ruby
# ❌ WRONG — dependent: :destroy hard-deletes associated records
has_many :order_items, dependent: :destroy

# ✅ CORRECT — cascade in service, or use a callback only for discard
class Order < ApplicationRecord
  include Discard::Model

  has_many :order_items

  # Option A: Cascade in service (preferred — explicit)
  # See DiscardService above

  # Option B: Callback (acceptable for discard-only side effect)
  after_discard   { order_items.each(&:discard) }
  after_undiscard { order_items.each(&:undiscard) }
end
```

## Step 8: Admin Interface for Discarded Records

```ruby
# app/controllers/admin/orders_controller.rb
class Admin::OrdersController < AdminController
  def index
    # Show all including discarded, filter by param
    @orders = if params[:show_discarded]
                Order.with_discarded.order(discarded_at: :desc)
              else
                Order.kept.order(created_at: :desc)
              end
  end
end
```

## Testing

```ruby
RSpec.describe Order, type: :model do
  describe "soft delete" do
    let(:order) { create(:order) }

    it "is kept by default" do
      expect(order).to be_kept
      expect(Order.kept).to include(order)
    end

    it "is excluded from default scope after discard" do
      order.discard
      expect(Order.all).not_to include(order)
      expect(Order.discarded).to include(order)
      expect(Order.with_discarded).to include(order)
    end

    it "can be restored" do
      order.discard
      order.undiscard
      expect(order).to be_kept
      expect(Order.all).to include(order)
    end
  end
end

RSpec.describe Orders::DiscardService do
  let(:order)   { create(:order) }
  let(:user)    { create(:user) }

  it "discards the order and its items" do
    items = create_list(:order_item, 3, order: order)

    result = described_class.call(order: order, discarded_by: user)

    expect(result).to be_success
    expect(order.reload).to be_discarded
    items.each { |item| expect(item.reload).to be_discarded }
  end

  it "returns Failure if already discarded" do
    order.discard
    result = described_class.call(order: order, discarded_by: user)
    expect(result).to be_failure
    expect(result.failure).to include("already discarded")
  end
end
```

## GDPR Considerations

For personal data, soft delete alone may not satisfy "right to erasure":

```ruby
# app/services/users/gdpr_erase_service.rb
module Users
  class GdprEraseService < ApplicationService
    def initialize(user:)
      @user = user
    end

    def call
      ActiveRecord::Base.transaction do
        # Anonymize PII — keep the record shape for referential integrity
        user.update!(
          email:      "deleted_#{user.id}@anonymized.invalid",
          name:       "Deleted User",
          phone:      nil,
          discarded_at: Time.current
        )
        # Hard delete sensitive associated data
        user.payment_methods.delete_all
        user.sessions.delete_all
      end

      Success(user)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.message)
    end

    private

    attr_reader :user
  end
end
```

## Anti-Patterns to Avoid

1. **Using Paranoia** — overrides `destroy` globally, causes unexpected behavior with `dependent: :destroy`
2. **`default_scope` without `with_discarded`** — forgetting to use `with_discarded` when querying admin interfaces causes "record not found" on discarded records
3. **Automatic cascade via `dependent: :destroy`** — hard-deletes children; use explicit cascade in service
4. **Soft-deleting without audit trail** — add `discarded_by_id` column or an audit log for compliance
5. **Pundit policies ignoring `discarded?`** — a discarded record's policy must check `record.kept?`
6. **Using `order.destroy` instead of `order.discard`** — defeats the purpose; always call `discard!` through a service
7. **GDPR erasure via soft delete only** — soft delete retains PII; anonymize or hard-delete sensitive fields separately
