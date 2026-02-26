---
name: packwerk
description: Implements modular architecture with Packwerk for Rails applications. Use when creating packages, enforcing privacy boundaries, managing dependencies, preventing circular references, or when user mentions Packwerk, packages, modularization, or architectural boundaries.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Packwerk - Modular Architecture for Rails 8

## Overview

Packwerk is a gem by Shopify that helps enforce modular boundaries in Rails applications:
- Create explicit packages with clear boundaries
- Prevent privacy violations (accessing private constants)
- Prevent dependency violations (undeclared package dependencies)
- Detect and eliminate circular dependencies
- Gradually modularize existing monoliths
- Document architectural decisions

## Quick Start

```bash
# Add to Gemfile
bundle add packwerk

# Initialize Packwerk configuration
bundle exec packwerk init

# Check for violations
bundle exec packwerk check

# Update package_todo.yml files
bundle exec packwerk update
```

## Project Structure

```
app/
├── package.yml                  # Root package (optional)
├── models/
│   └── package.yml
├── controllers/
│   └── package.yml
└── packages/                    # Recommended: organize by domain
    ├── billing/
    │   ├── package.yml
    │   ├── app/
    │   │   ├── models/
    │   │   │   └── billing/
    │   │   │       ├── invoice.rb
    │   │   │       └── payment.rb
    │   │   ├── services/
    │   │   │   └── billing/
    │   │   │       └── invoice_generator.rb
    │   │   └── controllers/
    │   │       └── billing/
    │   │           └── invoices_controller.rb
    │   └── spec/
    │       └── billing/
    ├── orders/
    │   ├── package.yml
    │   ├── app/
    │   │   ├── models/
    │   │   │   └── orders/
    │   │   │       ├── order.rb
    │   │   │       └── order_item.rb
    │   │   └── services/
    │   │       └── orders/
    │   │           └── order_processor.rb
    │   └── spec/
    └── users/
        ├── package.yml
        ├── app/
        │   └── models/
        │       └── users/
        │           └── user.rb
        └── spec/

packwerk.yml                     # Packwerk configuration
package_todo.yml                 # Violation backlog (root)
app/packages/billing/package_todo.yml  # Package-specific backlog
```

## Configuration

### packwerk.yml

```yaml
# packwerk.yml
---
# List of patterns for folders that contain packages
package_paths:
  - app/packages/*

# List of patterns to exclude from parsing
exclude:
  - "{bin,node_modules,script,tmp,vendor}/**/*"
  - "**/*.rake"

# Custom inflections for Zeitwerk compatibility
inflections:
  acronym:
    - "API"
    - "JSON"
    - "XML"
    - "HTML"

# Package categories for organization
package_categories:
  - domain      # Core domain logic
  - platform    # Technical infrastructure
  - utilities   # Shared utilities

# Parallel processing for faster checks
parallel: true
```

## Package Configuration

### Basic Package

```yaml
# app/packages/billing/package.yml
---
# Package metadata
metadata:
  category: domain
  owner: billing-team
  slack_channel: "#team-billing"

# Enforce privacy (prevent access to private constants)
enforce_privacy: true

# Enforce dependencies (require explicit declarations)
enforce_dependencies: true

# List of packages this package depends on
dependencies:
  - "app/packages/users"
  - "app/packages/orders"

# Public folder (constants that can be accessed by other packages)
# Everything else is considered private
# Must include namespace folder for consistency with models/, services/, etc.
public_path: "app/packages/billing/app/public/billing/"

# Ignored dependencies (temporary during migration)
# ignored_dependencies:
#   - "app/packages/legacy_module"
```

### Public vs Private Constants

```ruby
# app/packages/billing/app/models/billing/invoice.rb
# ❌ PRIVATE - Cannot be accessed from other packages (unless in public_path)
module Billing
  class Invoice < ApplicationRecord
    # Private implementation
  end
end

# app/packages/billing/app/public/billing/invoice_creator.rb
# ✅ PUBLIC - Explicitly exposed API via constant alias

require_relative "../../../services/billing/invoice_creator_service"

module Billing
  # Public API for creating invoices
  #
  # @example Create invoice for an order
  #   Billing::InvoiceCreator.call(order: order, user: user)
  #
  InvoiceCreator = ::Billing::InvoiceCreatorService
end

# app/packages/billing/app/public/billing/invoice_finder.rb
# ✅ PUBLIC - Query interface

require_relative "../../../services/billing/invoice_finder_service"

module Billing
  # Public API for finding invoices
  #
  # @example Find invoice by order
  #   Billing::InvoiceFinder.for_order(order)
  #
  InvoiceFinder = ::Billing::InvoiceFinder Service
end
```

## Privacy Enforcement

### Privacy Violations

```ruby
# ❌ BAD - Privacy violation
# app/packages/orders/app/services/orders/order_processor.rb
module Orders
  class OrderProcessor
    def process(order)
      # Direct access to private constant from billing package
      Billing::Invoice.create!(order: order)  # ❌ Privacy violation!
    end
  end
end
```

```ruby
# ✅ GOOD - Use public API
# app/packages/orders/app/services/orders/order_processor.rb
module Orders
  class OrderProcessor
    def process(order)
      # Use public interface
      Billing.create_invoice(order: order, user: order.user)  # ✅ Correct!
    end
  end
end
```

### Exposing Public APIs

```ruby
# app/packages/billing/app/public/billing/invoice_creator.rb
# ✅ Public API - Service exposed via constant alias

require_relative "../../../services/billing/invoice_creator_service"

module Billing
  # Public API for creating invoices
  #
  # Creates invoices with proper validation and business rules.
  #
  # @example Create invoice for an order
  #   Billing::InvoiceCreator.call(
  #     order: order,
  #     user: user
  #   )
  #
  # @return [Invoice] The created invoice
  InvoiceCreator = ::Billing::InvoiceCreatorService
end

# app/packages/billing/app/public/billing/payment_processor.rb
# ✅ Public API - Payment processing service

require_relative "../../../services/billing/payment_processor_service"

module Billing
  # Public API for processing payments
  #
  # Handles payment processing with external gateway integration.
  #
  # @example Process payment for invoice
  #   Billing::PaymentProcessor.call(invoice_id: invoice.id)
  #
  # @return [Payment] The processed payment
  PaymentProcessor = ::Billing::PaymentProcessorService
end

# app/packages/billing/app/public/billing/invoice_finder.rb
# ✅ Public API - Query interface

require_relative "../../../queries/billing/invoice_finder_query"

module Billing
  # Public API for finding invoices
  #
  # Provides query methods for retrieving invoice data.
  #
  # @example Find invoice by ID
  #   Billing::InvoiceFinder.by_id(invoice_id)
  #
  # @example Find invoices for user
  #   Billing::InvoiceFinder.for_user(user)
  #
  InvoiceFinder = ::Billing::InvoiceFinderQuery
end

# app/packages/billing/app/public/billing/types.rb
# ✅ Public API - Types and constants

module Billing
  module Types
    # Invoice status constants
    module InvoiceStatus
      DRAFT = "draft"
      PENDING = "pending"
      PAID = "paid"
      CANCELLED = "cancelled"

      ALL = [DRAFT, PENDING, PAID, CANCELLED].freeze
    end
  end
end
```

## Side Effects Philosophy

**⚠️ IMPORTANT - Package Services Must Be Pure:**

Services within packages should be **PURE** - they handle business logic and return results, but **NOT side effects**:
- ✅ Package services: Business logic, validation, data transformation, return results
- ❌ Package services: NO mailers, NO broadcasts, NO ApplicationEvent.dispatch
- ✅ Controllers: Handle side effects AFTER successful service execution

For multiple side effects (3+), use **Event Dispatcher pattern** in controller (see `@event_dispatcher_agent`).

```ruby
# ❌ DON'T: Side effects in package service
module Billing
  module Services
    class InvoiceCreator
      def call
        invoice = Invoice.create!(...)
        ApplicationEvent.dispatch("billing.invoice_created", invoice: invoice)  # ❌ Side effect!
        invoice
      end
    end
  end
end

# ✅ DO: Pure service, controller handles side effects
module Billing
  module Services
    class InvoiceCreator
      def call
        Invoice.create!(
          order_id: @order.id,
          user_id: @user.id,
          amount_cents: @order.total_cents
        )  # ✅ Pure - just creates and returns
      end
    end
  end
end

# Controller orchestrates side effects
class InvoicesController < ApplicationController
  def create
    invoice = Billing.create_invoice(order: @order, user: current_user)

    if invoice.persisted?
      # ✅ Controller handles side effects explicitly
      ApplicationEvent.dispatch("billing.invoice_created", invoice: invoice)
      redirect_to invoice
    end
  end
end
```

**Key Rules:**
- Package services return data, not trigger side effects
- Controllers orchestrate side effects after service success
- No callbacks with side effects (after_create, after_commit, etc.)
- This keeps packages testable, predictable, and loosely coupled

## Dependency Management

### Declaring Dependencies

```yaml
# app/packages/orders/package.yml
---
enforce_dependencies: true

# Explicit dependencies
dependencies:
  - "app/packages/users"      # Can use Users public API
  - "app/packages/billing"    # Can use Billing public API
  - "app/packages/inventory"  # Can use Inventory public API
```

### Dependency Violations

```ruby
# ❌ BAD - Undeclared dependency
# app/packages/orders/app/models/orders/order.rb
module Orders
  class Order < ApplicationRecord
    # This would cause dependency violation if called
    # Dependency not declared in package.yml
  end
end

# Trying to use Notifications package without declaring it
Notifications.send_email(...)  # ❌ Dependency violation!
```

```ruby
# ✅ GOOD - Declare dependency and use public API from controller
# Option 1: Declare dependency in package.yml
dependencies:
  - "app/packages/notifications"

# Then use from controller (NOT callback)
class OrdersController < ApplicationController
  def create
    @order = Orders::OrderCreator.call(params)

    if @order.persisted?
      Notifications::EmailSender.call(order: @order)  # ✅ Explicit in controller
      redirect_to @order
    end
  end
end

# Option 2: Use Event Dispatcher in controller (no dependency needed)
class OrdersController < ApplicationController
  def create
    @order = Orders::OrderCreator.call(params)

    if @order.persisted?
      # ✅ Controller dispatches event
      ApplicationEvent.dispatch("order.created", order: @order)
      redirect_to @order
    end
  end
end

# In notifications package - subscribes to event
# app/packages/notifications/app/subscribers/order_subscriber.rb
module Notifications
  class OrderSubscriber
    def self.on_order_created(order:)
      send_email(order)
    end
  end
end
```

## Circular Dependencies

### Detecting Circular Dependencies

```bash
# Check for circular dependencies
bundle exec packwerk check

# Example output:
# Circular dependency detected:
#   app/packages/orders → app/packages/billing → app/packages/orders
```

### Breaking Circular Dependencies

```ruby
# ❌ BAD - Circular dependency
# orders depends on billing
# billing depends on orders
# This creates a cycle!

# orders/app/models/orders/order.rb
module Orders
  class Order < ApplicationRecord
    def create_invoice
      Billing::Invoice.create(order: self)  # orders → billing
    end
  end
end

# billing/app/models/billing/invoice.rb
module Billing
  class Invoice < ApplicationRecord
    def recalculate
      Orders::Order.find(order_id).calculate_total  # billing → orders (cycle!)
    end
  end
end
```

```ruby
# ✅ GOOD - Break cycle with events dispatched from controller
# Solution 1: Use Event Dispatcher from controller (preferred)

# orders/app/models/orders/order.rb
module Orders
  class Order < ApplicationRecord
    # No callbacks - keep model pure
  end
end

# orders/app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  def create
    @order = Orders.create_order(params)

    if @order.persisted?
      # ✅ Controller dispatches event (no direct dependency on billing)
      ApplicationEvent.dispatch("order.created", order: @order)
      redirect_to @order
    end
  end
end

# billing/app/subscribers/order_subscriber.rb
module Billing
  class OrderSubscriber
    def self.on_order_created(order:)
      Invoice.create!(order_id: order.id, amount: order.total)
    end
  end
end

# Solution 2: Extract shared package
# Create app/packages/contracts with shared interfaces
# Both orders and billing depend on contracts (no cycle)

# contracts/app/public/contracts/invoice_data.rb
module Contracts
  class InvoiceData
    attr_reader :order_id, :amount, :items

    def initialize(order_id:, amount:, items:)
      @order_id = order_id
      @amount = amount
      @items = items
    end
  end
end

# orders/package.yml
dependencies:
  - "app/packages/contracts"

# billing/package.yml
dependencies:
  - "app/packages/contracts"
```

## TDD Workflow with Packwerk

```
Packwerk Development Cycle:
- [ ] Step 1: Design package boundaries
- [ ] Step 2: Create package.yml
- [ ] Step 3: Define public API in public_path
- [ ] Step 4: Write tests for public API
- [ ] Step 5: Implement package logic (RED → GREEN)
- [ ] Step 6: Run packwerk check
- [ ] Step 7: Fix violations or update package_todo.yml
- [ ] Step 8: Refactor with confidence
```

## Working with package_todo.yml

### Understanding Violations

```yaml
# app/packages/orders/package_todo.yml
---
# This file contains a list of violations that need to be fixed
# Run `bundle exec packwerk update` to regenerate this file

"app/packages/billing":
  "::Billing::Invoice":
    violations:
      - privacy
    files:
      - "app/packages/orders/app/services/orders/invoice_creator.rb"

  "::Billing::Payment":
    violations:
      - dependency
    files:
      - "app/packages/orders/app/models/orders/order.rb"
```

### Fixing Violations

```ruby
# BEFORE - Privacy violation recorded in package_todo.yml
# app/packages/orders/app/services/orders/invoice_creator.rb
module Orders
  class InvoiceCreator
    def call(order)
      Billing::Invoice.create!(order: order)  # ❌ Privacy violation
    end
  end
end

# AFTER - Use public API
module Orders
  class InvoiceCreator
    def call(order)
      Billing.create_invoice(order: order, user: order.user)  # ✅ Fixed!
    end
  end
end

# Then regenerate package_todo.yml
# bundle exec packwerk update
# Violation will be removed from package_todo.yml
```

## Migration Strategies

### Gradual Modularization

```ruby
# Step 1: Start with enforce_privacy: false, enforce_dependencies: false
# app/packages/billing/package.yml
---
enforce_privacy: false
enforce_dependencies: false

# Step 2: Create package structure
# Move files into package directories

# Step 3: Define public API
# Create app/packages/billing/app/public/billing/api.rb

# Step 4: Enable privacy enforcement
enforce_privacy: true  # Start catching privacy violations

# Step 5: Run packwerk check and fix violations
bundle exec packwerk check
bundle exec packwerk update  # Record remaining violations

# Step 6: Gradually fix violations in package_todo.yml

# Step 7: Enable dependency enforcement
enforce_dependencies: true

# Step 8: Declare dependencies explicitly in package.yml

# Step 9: Fix dependency violations
```

### Package Extraction

```ruby
# Extract a package from existing code
# Example: Extracting "billing" from monolithic app/models

# BEFORE - Monolithic structure
app/
├── models/
│   ├── invoice.rb
│   ├── payment.rb
│   └── subscription.rb
└── services/
    └── billing_service.rb

# AFTER - Package structure
app/
└── packages/
    └── billing/
        ├── package.yml
        ├── app/
        │   ├── models/
        │   │   └── billing/
        │   │       ├── invoice.rb
        │   │       ├── payment.rb
        │   │       └── subscription.rb
        │   ├── services/
        │   │   └── billing/
        │   │       └── billing_service.rb
        │   └── public/
        │       └── billing/
        │           └── api.rb
        └── spec/
            └── billing/

# Move files and update namespaces
# OLD: class Invoice < ApplicationRecord
# NEW: class Billing::Invoice < ApplicationRecord

# Run packwerk check
bundle exec packwerk check

# Fix violations by updating references
# OLD: Invoice.find(id)
# NEW: Billing.find_invoice(id)
```

## Integration with Rails

### Autoloading with Zeitwerk

```ruby
# config/application.rb
module MyApp
  class Application < Rails::Application
    # Add package paths to autoload
    config.paths.add "app/packages", glob: "*/app/{*,*/concerns}", eager_load: true

    # Custom inflections
    config.inflections do |inflect|
      inflect.acronym "API"
      inflect.acronym "JSON"
    end
  end
end
```

### Routes Organization

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Package-specific routes can be defined in package
  # and included here, or defined inline with namespace

  namespace :billing do
    resources :invoices, only: [:index, :show]
    resources :payments, only: [:create]
  end

  namespace :orders do
    resources :orders do
      member do
        post :confirm
        post :cancel
      end
    end
  end
end
```

### Testing Package Boundaries

```ruby
# spec/packwerk_spec.rb
require "rails_helper"

RSpec.describe "Packwerk" do
  it "has no privacy violations" do
    result = `bundle exec packwerk check --packages=app/packages/billing`
    expect(result).not_to include("privacy violation")
  end

  it "has no dependency violations" do
    result = `bundle exec packwerk check --packages=app/packages/billing`
    expect(result).not_to include("dependency violation")
  end

  it "has no circular dependencies" do
    result = `bundle exec packwerk check`
    expect(result).not_to include("Circular dependency")
  end
end

# Package-specific tests
# spec/packages/billing_spec.rb
require "rails_helper"

RSpec.describe "Billing Package" do
  describe "Public API" do
    it "exposes create_invoice" do
      expect(Billing).to respond_to(:create_invoice)
    end

    it "exposes charge_invoice" do
      expect(Billing).to respond_to(:charge_invoice)
    end

    it "exposes find_invoice" do
      expect(Billing).to respond_to(:find_invoice)
    end
  end

  describe "Privacy" do
    it "does not expose Invoice model directly" do
      expect { Billing::Invoice }.to raise_error(NameError)
    end
  end
end
```

## Common Patterns

### Service Objects as Public API

```ruby
# app/packages/billing/app/public/billing/api.rb
module Billing
  class << self
    def create_invoice(order:, user:)
      Services::InvoiceCreator.call(order: order, user: user)
    end

    def charge_invoice(invoice_id)
      Services::PaymentProcessor.call(invoice_id: invoice_id)
    end
  end
end

# app/packages/billing/app/services/billing/invoice_creator.rb
module Billing
  module Services
    class InvoiceCreator
      def self.call(order:, user:)
        new(order: order, user: user).call
      end

      def initialize(order:, user:)
        @order = order
        @user = user
      end

      def call
        Invoice.create!(
          order_id: @order.id,
          user_id: @user.id,
          amount_cents: @order.total_cents
        )
        # ✅ Service is pure - returns invoice without side effects
        # Controller will handle event dispatching
      end
    end
  end
end
```

### Repository Pattern for Data Access

```ruby
# app/packages/billing/app/public/billing/invoice_finder.rb
# ✅ Public API - Query/finder service

require_relative "../../../repositories/billing/invoice_repository"

module Billing
  # Public API for finding invoices
  #
  # Provides query methods for invoice retrieval.
  #
  # @example Find by ID
  #   Billing::InvoiceFinder.find(invoice_id)
  #
  # @example Find for user
  #   Billing::InvoiceFinder.for_user(user)
  #
  InvoiceFinder = ::Billing::InvoiceRepository
end

# app/packages/billing/app/repositories/billing/invoice_repository.rb
# ❌ PRIVATE - Not accessible from other packages
module Billing
  class InvoiceRepository
    def self.find(id)
      Invoice.find(id)
    end

    def self.for_user(user)
      Invoice.where(user: user).order(created_at: :desc)
    end

    def self.pending
      Invoice.where(status: "pending")
    end
  end
end
```

### Query Objects as Public API

```ruby
# app/packages/billing/app/public/billing/overdue_invoices_query.rb
# ✅ Public API - Query object exposed via constant alias

require_relative "../../../queries/billing/overdue_invoices_query"

module Billing
  # Public API for finding overdue invoices
  #
  # Returns all pending invoices past their due date.
  #
  # @example Find overdue invoices
  #   Billing::OverdueInvoicesQuery.call
  #
  # @return [ActiveRecord::Relation<Invoice>] Overdue invoices
  #
  OverdueInvoicesQuery = ::Billing::OverdueInvoicesQueryObject
end

# app/packages/billing/app/public/billing/invoices_by_status_query.rb
# ✅ Public API - Parameterized query

require_relative "../../../queries/billing/invoices_by_status_query"

module Billing
  # Public API for finding invoices by status
  #
  # @example Find paid invoices
  #   Billing::InvoicesByStatusQuery.call(status: "paid")
  #
  InvoicesByStatusQuery = ::Billing::InvoicesByStatusQueryObject
end

# app/packages/billing/app/queries/billing/overdue_invoices_query.rb
# ❌ PRIVATE - Not accessible from other packages
module Billing
  class OverdueInvoicesQueryObject
    def self.call
      new.call
    end

    def call
      Invoice
        .where(status: "pending")
        .where("due_date < ?", Date.current)
        .order(:due_date)
    end
  end
end
```

### Value Objects for Package Boundaries

```ruby
# app/packages/billing/app/public/billing/invoice_presenter.rb
# ✅ Public API - Value object/presenter for cross-package communication

require_relative "../../../presenters/billing/invoice_presenter"

module Billing
  # Public API for invoice presentation
  #
  # Provides a safe, read-only interface to invoice data
  # for use by other packages.
  #
  # @example Get invoice data
  #   presenter = Billing::InvoicePresenter.new(invoice)
  #   presenter.total  # => "$150.00"
  #   presenter.overdue?  # => true
  #
  InvoicePresenter = ::Billing::InvoicePresenterObject
end

# app/packages/billing/app/presenters/billing/invoice_presenter.rb
# ❌ PRIVATE - Implementation details
module Billing
  class InvoicePresenterObject
    attr_reader :id, :status, :due_date

    def initialize(invoice)
      @invoice = invoice
      @id = invoice.id
      @status = invoice.status
      @due_date = invoice.due_date
    end

    def total
      "$#{@invoice.amount_cents / 100.0}"
    end

    def overdue?
      due_date < Date.current && status != "paid"
    end

    def to_h
      {
        id: id,
        total: total,
        status: status,
        due_date: due_date
      }
    end
  end
end

# Usage from other packages
invoice = Billing::InvoiceFinder.find(123)
presenter = Billing::InvoicePresenter.new(invoice)
puts presenter.total  # Returns formatted value
```

## CI/CD Integration

### GitHub Actions

```yaml
# .github/workflows/packwerk.yml
name: Packwerk

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  packwerk:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.3
          bundler-cache: true

      - name: Check Packwerk violations
        run: bundle exec packwerk check

      - name: Check for new violations
        run: |
          # Fail if package_todo.yml files have grown
          git diff --exit-code '**/package_todo.yml'

      - name: Validate package.yml files
        run: bundle exec packwerk validate
```

### Pre-commit Hook

```bash
# .git/hooks/pre-commit
#!/bin/bash

echo "Running Packwerk checks..."

bundle exec packwerk check

if [ $? -ne 0 ]; then
  echo "❌ Packwerk violations detected!"
  echo "Run 'bundle exec packwerk check' to see details"
  echo "Fix violations or run 'bundle exec packwerk update' to record them"
  exit 1
fi

echo "✅ No Packwerk violations"
```

## Debugging Violations

### Understanding Error Messages

```bash
# Privacy violation
app/packages/orders/app/models/order.rb:15:0
Privacy violation: ::Billing::Invoice is private to app/packages/billing
  but referenced from app/packages/orders

# Dependency violation
app/packages/orders/app/services/order_processor.rb:23:0
Dependency violation: ::Notifications::EmailService belongs to app/packages/notifications
  but app/packages/orders does not declare a dependency on it

# Circular dependency
Circular dependency detected:
  app/packages/orders → app/packages/billing → app/packages/orders
```

### Finding Violation Location

```bash
# Check specific package
bundle exec packwerk check --packages=app/packages/billing

# Check specific file
bundle exec packwerk check app/packages/billing/app/models/billing/invoice.rb

# Offenses only (no progress output)
bundle exec packwerk check --offenses-formatter
```

## Best Practices

### Package Design Principles

```yaml
# ✅ GOOD - Small, focused packages
app/packages/
├── billing/          # Single responsibility
├── orders/           # Single responsibility
├── inventory/        # Single responsibility
└── notifications/    # Single responsibility

# ❌ BAD - Large, unfocused packages
app/packages/
├── core/             # Too broad
└── everything_else/  # Not modular
```

### Public API Design

```ruby
# ✅ GOOD - Stable, minimal public API
module Billing
  class << self
    # Service methods
    def create_invoice(order:, user:)
      # ...
    end

    def charge_invoice(invoice_id)
      # ...
    end

    # Query methods
    def find_invoice(id)
      # ...
    end
  end
end

# ❌ BAD - Exposing too much
module Billing
  class << self
    def create_invoice(...) end
    def update_invoice(...) end
    def delete_invoice(...) end
    def recalculate_invoice(...) end
    def send_invoice_email(...) end
    def process_refund(...) end
    def generate_pdf(...) end
    # ... 20 more methods
  end
end
```

### Dependency Direction

```
✅ GOOD - Dependencies flow inward
┌─────────────┐
│   Web UI    │
└──────┬──────┘
       │ depends on
┌──────▼───────┐
│   Domain     │
└──────┬───────┘
       │ depends on
┌──────▼───────┐
│   Platform   │
└──────────────┘

❌ BAD - Circular dependencies
┌─────────────┐
│   Orders    │◄──┐
└──────┬──────┘   │
       │          │
       │ depends  │ depends
       │ on       │ on
┌──────▼──────┐   │
│   Billing   │───┘
└─────────────┘
```

## Checklist

- [ ] `packwerk.yml` configured with package_paths
- [ ] Each package has `package.yml` with metadata
- [ ] `enforce_privacy: true` for new packages
- [ ] `enforce_dependencies: true` for new packages
- [ ] Public API defined in `public_path`
- [ ] Dependencies explicitly declared
- [ ] No circular dependencies
- [ ] CI/CD checks Packwerk violations
- [ ] `package_todo.yml` files are shrinking, not growing
- [ ] Tests verify package boundaries
- [ ] Public API is documented
- [ ] Namespaces follow Zeitwerk conventions
