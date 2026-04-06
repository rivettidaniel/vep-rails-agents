---
name: feature-flags
description: Feature flags in Rails using the Flipper gem — boolean flags, percentage rollouts, per-user/group enablement, and UI. Use when doing canary releases, A/B testing, or gating features behind a flag.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Feature Flags with Flipper

## Overview

Feature flags decouple deployment from release. Ship code dark, enable for a subset, then roll out progressively.

| Use Case | Flipper Feature |
|----------|----------------|
| Enable for all users | `Flipper.enable(:feature)` |
| Enable for one user | `Flipper.enable_actor(:feature, user)` |
| Enable for a group | `Flipper.enable_group(:feature, :admins)` |
| Percentage of users | `Flipper.enable_percentage_of_actors(:feature, 10)` |
| Percentage of time | `Flipper.enable_percentage_of_time(:feature, 5)` |
| Disable entirely | `Flipper.disable(:feature)` |

## Setup

```ruby
# Gemfile
gem "flipper"
gem "flipper-active_record"  # DB-backed storage (recommended)
gem "flipper-ui"             # Admin UI (optional)

# Or for simple apps:
# gem "flipper-active_record" pulls in flipper automatically
```

```bash
bin/rails generate flipper:active_record
bin/rails db:migrate
```

```ruby
# config/initializers/flipper.rb
require "flipper"
require "flipper/adapters/active_record"

Flipper.configure do |config|
  config.adapter { Flipper::Adapters::ActiveRecord.new }
end

# Register groups
Flipper.register(:admins) { |actor| actor.respond_to?(:admin?) && actor.admin? }
Flipper.register(:beta_users) { |actor| actor.respond_to?(:beta?) && actor.beta? }
```

### Admin UI (optional)

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount Flipper::UI.app(Flipper) => "/flipper",
        constraints: AdminConstraint.new  # protect with auth
end

# app/constraints/admin_constraint.rb
class AdminConstraint
  def matches?(request)
    return false unless request.session[:user_id]
    User.find_by(id: request.session[:user_id])&.admin?
  end
end
```

## Checking Flags

### In controllers

```ruby
class BetaFeatureController < ApplicationController
  before_action :require_feature_flag

  def show
    # ...
  end

  private

  def require_feature_flag
    unless Flipper.enabled?(:new_dashboard, current_user)
      redirect_to root_path, alert: "Feature not available"
    end
  end
end
```

### In views

```erb
<% if Flipper.enabled?(:new_checkout, current_user) %>
  <%= render "checkout/new_flow" %>
<% else %>
  <%= render "checkout/legacy_flow" %>
<% end %>
```

### In service objects

Flag checks inside a service are fine — but side effects (mailers, jobs) stay in the controller:

```ruby
# ✅ Service only decides — no side effects
class Orders::CreateService < ApplicationService
  def call
    order = Order.create!(order_attributes)
    Success(order)
  end
end

# ✅ Controller handles the flag + side effects after result
class OrdersController < ApplicationController
  def create
    result = Orders::CreateService.call(user: current_user, params: order_params)

    if result.success?
      if Flipper.enabled?(:instant_confirmation, current_user)
        ConfirmationMailer.instant(result.value!).deliver_later
      else
        ConfirmationMailer.standard(result.value!).deliver_later
      end
      redirect_to result.value!
    else
      render_service_failure(result.failure)
    end
  end
end
```

### Shorthand helper (optional concern)

```ruby
# app/controllers/concerns/feature_flaggable.rb
module FeatureFlaggable
  extend ActiveSupport::Concern

  def feature_enabled?(flag)
    Flipper.enabled?(flag, current_user)
  end
  helper_method :feature_enabled?
end

# In view: <% if feature_enabled?(:new_dashboard) %>
```

## Managing Flags

### In console / seed / deployment

```ruby
# Enable globally
Flipper.enable(:dark_mode)

# Enable for a specific user
user = User.find(42)
Flipper.enable_actor(:dark_mode, user)

# Enable for admins group
Flipper.enable_group(:dark_mode, :admins)

# Canary: 5% of users
Flipper.enable_percentage_of_actors(:dark_mode, 5)

# Ramp up to 50%
Flipper.enable_percentage_of_actors(:dark_mode, 50)

# Full rollout
Flipper.enable(:dark_mode)

# Disable
Flipper.disable(:dark_mode)

# Check state
Flipper[:dark_mode].state        # :on / :off / :conditional
Flipper[:dark_mode].enabled?(user)
```

### Preloading flags to avoid N+1 in views

```ruby
# app/controllers/application_controller.rb
before_action :preload_feature_flags

private

def preload_feature_flags
  Flipper.preload([:new_dashboard, :new_checkout, :dark_mode])
end
```

## Actor Requirements

Flipper requires actors to respond to `flipper_id`:

```ruby
# app/models/user.rb
class User < ApplicationRecord
  # Flipper uses this as the unique actor identifier
  def flipper_id
    "User:#{id}"
  end
end
```

## Seeding Flags in Development

```ruby
# db/seeds.rb
# Ensure flags exist but don't override their state if already set
[
  :new_dashboard,
  :new_checkout,
  :dark_mode,
  :instant_confirmation
].each do |flag|
  Flipper.add(flag) unless Flipper.exist?(flag)
end

# Enable everything in development
if Rails.env.development?
  Flipper.enable(:new_dashboard)
  Flipper.enable(:new_checkout)
end
```

## Testing

```ruby
# spec/rails_helper.rb
RSpec.configure do |config|
  config.before(:each) do
    # Reset all flags between tests
    Flipper.instance_variable_set(:@adapter, nil)
    Flipper.configure { |c| c.adapter { Flipper::Adapters::Memory.new } }
  end
end
```

Flag behavior lives in the **controller**, not the service — test it with a request spec:

```ruby
RSpec.describe "Orders", type: :request do
  let(:user) { create(:user) }
  let(:valid_params) { { order: attributes_for(:order) } }

  before { sign_in user }

  context "when instant_confirmation flag is enabled" do
    before { Flipper.enable(:instant_confirmation) }

    it "sends instant confirmation email" do
      expect {
        post orders_path, params: valid_params
      }.to have_enqueued_mail(ConfirmationMailer, :instant)
    end
  end

  context "when instant_confirmation flag is disabled" do
    before { Flipper.disable(:instant_confirmation) }

    it "sends standard confirmation email" do
      expect {
        post orders_path, params: valid_params
      }.to have_enqueued_mail(ConfirmationMailer, :standard)
    end
  end
end
```

The service itself has no flag dependency — its spec tests only order creation:

```ruby
RSpec.describe Orders::CreateService do
  let(:user) { create(:user) }

  it "creates and returns the order" do
    result = described_class.call(user: user, params: attributes_for(:order))
    expect(result).to be_success
    expect(result.value!).to be_a(Order)
  end
end
```

## Checklist

- [ ] `flipper-active_record` in Gemfile + migration run
- [ ] Groups registered in initializer (`Flipper.register`)
- [ ] `flipper_id` defined on User model
- [ ] Admin UI mounted with auth constraint (never public)
- [ ] Flags preloaded in ApplicationController to prevent N+1
- [ ] Flags seeded in `db/seeds.rb` for development
- [ ] Tests use `Flipper::Adapters::Memory` (not ActiveRecord)
- [ ] Flags disabled / cleaned up after full rollout (no dead flags)
