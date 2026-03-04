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

Packages live in `app/packs/` with a `_module` suffix. The Ruby namespace matches in PascalCase (e.g. `billing_module` → `BillingModule`). Services are nested under a sub-namespace (e.g. `BillingModule::Invoice::CreatorService`).

```
app/packs/
├── billing_module/
│   ├── package.yml
│   ├── app/
│   │   ├── models/
│   │   │   └── billing_module/
│   │   │       └── invoice/
│   │   │           └── invoice.rb        # BillingModule::Invoice::Invoice
│   │   ├── services/
│   │   │   └── billing_module/
│   │   │       └── invoice/
│   │   │           └── creator_service.rb  # BillingModule::Invoice::CreatorService
│   │   ├── repositories/
│   │   │   └── billing_module/
│   │   │       └── invoice/
│   │   │           └── invoice_repository.rb
│   │   ├── workers/
│   │   │   └── billing_module/
│   │   │       └── invoice/
│   │   │           └── send_invoice_worker.rb
│   │   └── public/
│   │       └── billing_module/
│   │           └── invoice/
│   │               └── creator.rb        # Public alias → CreatorService
│   └── spec/
│       └── billing_module/
├── orders_module/
│   ├── package.yml
│   ├── app/
│   │   ├── models/
│   │   │   └── orders_module/
│   │   │       └── order/
│   │   │           └── order.rb          # OrdersModule::Order::Order
│   │   └── services/
│   │       └── orders_module/
│   │           └── order/
│   │               └── processor_service.rb
│   └── spec/
└── users_module/
    ├── package.yml
    ├── app/
    │   └── models/
    │       └── users_module/
    │           └── user/
    │               └── user.rb           # UsersModule::User::User
    └── spec/

packwerk.yml                     # Packwerk configuration
package_todo.yml                 # Violation backlog (root)
app/packs/billing_module/package_todo.yml  # Package-specific backlog
```

## Configuration

### packwerk.yml

```yaml
# packwerk.yml
---
# List of patterns for folders that contain packages
package_paths:
  - app/packs/*

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
# app/packs/billing_module/package.yml
---
enforce_dependencies: true   # Require explicit declarations
# enforce_privacy: true      # Uncomment when ready to enforce (start permissive)

# List of packages this package depends on
dependencies:
  - '.'                             # Self (always include)
  - app/packs/users_module          # Can use UsersModule public API
  - app/packs/orders_module         # Can use OrdersModule public API

# Test paths for packwerk to recognize spec/ as part of this package
metadata:
  test_paths:
    - spec/
```

### Public vs Private Constants

```ruby
# app/packs/billing_module/app/models/billing_module/invoice/invoice.rb
# ❌ PRIVATE - Cannot be accessed from other packages (unless in public_path)
module BillingModule
  module Invoice
    class Invoice < ApplicationRecord
      # Private implementation
    end
  end
end

# app/packs/billing_module/app/public/billing_module/invoice/creator.rb
# ✅ PUBLIC - Pattern A: Simple alias (most common — Zeitwerk autoloads implementation)
module BillingModule
  module Invoice
    # Public API for creating invoices
    #
    # @example
    #   BillingModule::Invoice::Creator.call(order: order, user: user)
    #
    Creator = ::BillingModule::Invoice::CreatorService
  end
end

# app/packs/billing_module/app/public/billing_module/invoice/repository.rb
# ✅ PUBLIC - Pattern B: With require_relative (when autoload order matters)
require_relative "../../../repositories/billing_module/invoice/invoice_repository"

module BillingModule
  module Invoice
    # Public API for finding invoices
    #
    # @example
    #   BillingModule::Invoice::Repository.for_user(user)
    #
    Repository = ::BillingModule::Invoice::InvoiceRepository
  end
end
```

## Privacy Enforcement

### Privacy Violations

```ruby
# ❌ BAD - Privacy violation
# app/packs/orders_module/app/services/orders_module/order/processor_service.rb
module OrdersModule
  module Order
    class ProcessorService
      def process(order)
        # Direct access to private constant from billing_module package
        BillingModule::Invoice::Invoice.create!(order: order)  # ❌ Privacy violation!
      end
    end
  end
end
```

```ruby
# ✅ GOOD - Use public API
# app/packs/orders_module/app/services/orders_module/order/processor_service.rb
module OrdersModule
  module Order
    class ProcessorService
      def process(order)
        # Use public constant alias
        BillingModule::Invoice::Creator.call(order: order, user: order.user)  # ✅
      end
    end
  end
end
```

### Exposing Public APIs — Three Patterns

```ruby
# Pattern A: Simple alias (most common — Zeitwerk autoloads the implementation)
# app/packs/billing_module/app/public/billing_module/invoice/creator.rb
module BillingModule
  module Invoice
    # @example
    #   BillingModule::Invoice::Creator.call(order: order, user: user)
    Creator = ::BillingModule::Invoice::CreatorService
  end
end

# Pattern B: Alias with require_relative (when autoload order matters)
# app/packs/billing_module/app/public/billing_module/payment/processor.rb
require_relative "../../../services/billing_module/payment/processor_service"

module BillingModule
  module Payment
    # @example
    #   BillingModule::Payment::Processor.call(invoice_id: invoice.id)
    Processor = ::BillingModule::Payment::ProcessorService
  end
end

# Pattern C: Full module implementation (facade/adapter — use when API needs own logic)
# app/packs/billing_module/app/public/billing_module/payment/gateway.rb
module BillingModule
  module Payment
    module Gateway
      class << self
        # @example
        #   BillingModule::Payment::Gateway.instance(role: :admin)
        def instance(role: :standard)
          BillingModule::Payment::GatewayService.instance(role: role)
        end

        delegate :enabled?, to: :"BillingModule::Payment::GatewayService"
      end
    end
  end
end

# app/packs/billing_module/app/public/billing_module/invoice/types.rb
# ✅ Public API - Types and constants (no alias needed for plain constants)
module BillingModule
  module Invoice
    module Types
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
# app/packs/orders_module/package.yml
---
enforce_dependencies: true

# Explicit dependencies
dependencies:
  - '.'                              # Self (always include)
  - app/packs/users_module           # Can use UsersModule public API
  - app/packs/billing_module         # Can use BillingModule public API
  - app/packs/inventory_module       # Can use InventoryModule public API

metadata:
  test_paths:
    - spec/
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
enforce_privacy: true  # Uncomment to start catching privacy violations

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

# AFTER - Package structure (note: app/packs/, _module suffix)
app/packs/
└── billing_module/
    ├── package.yml
    ├── app/
    │   ├── models/
    │   │   └── billing_module/
    │   │       └── invoice/
    │   │           └── invoice.rb        # BillingModule::Invoice::Invoice
    │   ├── services/
    │   │   └── billing_module/
    │   │       └── invoice/
    │   │           └── creator_service.rb # BillingModule::Invoice::CreatorService
    │   └── public/
    │       └── billing_module/
    │           └── invoice/
    │               └── creator.rb        # Public alias
    └── spec/
        └── billing_module/

# Move files and update namespaces
# OLD: class Invoice < ApplicationRecord
# NEW: module BillingModule; module Invoice; class Invoice < ApplicationRecord

# Run packwerk check
bundle exec packwerk check

# Fix violations by updating references
# OLD: Invoice.find(id)
# NEW: BillingModule::Invoice::Repository.find(id)
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
    result = `bundle exec packwerk check --packages=app/packs/billing_module`
    expect(result).not_to include("privacy violation")
  end

  it "has no dependency violations" do
    result = `bundle exec packwerk check --packages=app/packs/billing_module`
    expect(result).not_to include("dependency violation")
  end

  it "has no circular dependencies" do
    result = `bundle exec packwerk check`
    expect(result).not_to include("Circular dependency")
  end
end

# Package-specific tests
# spec/packages/billing_module_spec.rb
require "rails_helper"

RSpec.describe "BillingModule Package" do
  describe "Public API" do
    it "exposes Invoice::Creator" do
      expect(BillingModule::Invoice::Creator).to be_a(Class)
      expect(BillingModule::Invoice::Creator).to respond_to(:call)
    end

    it "exposes Invoice::Repository" do
      expect(BillingModule::Invoice::Repository).to be_a(Class)
      expect(BillingModule::Invoice::Repository).to respond_to(:find)
    end

    it "exposes Payment::Processor" do
      expect(BillingModule::Payment::Processor).to be_a(Class)
      expect(BillingModule::Payment::Processor).to respond_to(:call)
    end
  end

  describe "Privacy" do
    # Packwerk enforces privacy statically, not at runtime.
    # Constants are still accessible in Ruby's object space during tests.
    # Use packwerk check to verify privacy, not NameError expectations.
    it "reports no privacy violations" do
      result = `bundle exec packwerk check --packages=app/packs/billing_module`
      expect(result).not_to include("privacy violation")
    end
  end
end
```

## Common Patterns

### Service as Public API (Constant Alias — most common)

```ruby
# app/packs/billing_module/app/public/billing_module/invoice/creator.rb
# ✅ Public API — Pattern A: simple alias, Zeitwerk autoloads the implementation
module BillingModule
  module Invoice
    # @example
    #   BillingModule::Invoice::Creator.call(order: order, user: user)
    Creator = ::BillingModule::Invoice::CreatorService
  end
end

# app/packs/billing_module/app/services/billing_module/invoice/creator_service.rb
# ❌ PRIVATE - Not accessible from other packages directly
module BillingModule
  module Invoice
    class CreatorService
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
        # Controller handles event dispatching
      end

      private

      attr_reader :order, :user
    end
  end
end
```

### Repository Pattern for Data Access

```ruby
# app/packs/billing_module/app/public/billing_module/invoice/repository.rb
# ✅ Public API - repository exposed via constant alias
module BillingModule
  module Invoice
    # @example
    #   BillingModule::Invoice::Repository.find(invoice_id)
    #
    # @example
    #   BillingModule::Invoice::Repository.for_user(user)
    #
    Repository = ::BillingModule::Invoice::InvoiceRepository
  end
end

# app/packs/billing_module/app/repositories/billing_module/invoice/invoice_repository.rb
# ❌ PRIVATE - Not accessible from other packages
module BillingModule
  module Invoice
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
end
```

### Facade as Public API (Full Module Implementation)

Use when the public API needs its own logic — e.g. adapting method signatures or delegating to multiple internals.

```ruby
# app/packs/billing_module/app/public/billing_module/payment/gateway.rb
# ✅ Public API - Pattern C: full module implementation (not just an alias)
module BillingModule
  module Payment
    module Gateway
      class << self
        # @example
        #   BillingModule::Payment::Gateway.instance(role: :admin)
        def instance(role: :standard)
          BillingModule::Payment::GatewayService.instance(role: role)
        end

        delegate :enabled?, to: :"BillingModule::Payment::GatewayService"
      end
    end
  end
end
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
# ✅ GOOD - Small, focused packages (note: app/packs/, _module suffix)
app/packs/
├── billing_module/          # Single responsibility → BillingModule
├── orders_module/           # Single responsibility → OrdersModule
├── inventory_module/        # Single responsibility → InventoryModule
└── notifications_module/    # Single responsibility → NotificationsModule

# ❌ BAD - Large, unfocused packages
app/packs/
├── core_module/             # Too broad
└── everything_else_module/  # Not modular
```

### Public API Design

```ruby
# ✅ GOOD - Minimal public API via constant aliases
# Each alias exposes one service/repo/query — easy to reason about
module BillingModule
  module Invoice
    Creator   = ::BillingModule::Invoice::CreatorService    # one service
    Canceller = ::BillingModule::Invoice::CancellerService  # one service
    Repository = ::BillingModule::Invoice::InvoiceRepository # one repo
  end
  module Payment
    Processor = ::BillingModule::Payment::ProcessorService  # one service
  end
end

# ❌ BAD - Exposing too much via one god-object
module BillingModule
  class << self
    def create_invoice(...) end
    def update_invoice(...) end
    def delete_invoice(...) end
    def recalculate_invoice(...) end
    def send_invoice_email(...) end    # ❌ Side effect in public API
    def process_refund(...) end
    def generate_pdf(...) end
    # ... 20 more methods - hard to test and discover
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
