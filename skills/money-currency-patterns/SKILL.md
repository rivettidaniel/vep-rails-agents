---
name: money-currency-patterns
description: Money and currency handling in Rails - integer cents storage, money-rails gem, BigDecimal arithmetic, formatting, and multi-currency. Use whenever amounts, prices, balances, or currencies are involved.
allowed-tools: Read, Write, Edit, Bash
---

# Money & Currency Patterns

## Overview

Floating point numbers are **never safe for money**. `0.1 + 0.2` is `0.30000000000000004` in Ruby. The canonical solution: store amounts as **integers in the smallest currency unit** (cents for USD, pence for GBP, yen for JPY) and use the `money-rails` gem for arithmetic, formatting, and currency handling.

```
❌ Store:  amount: 19.99  (float — loses precision)
✅ Store:  amount_cents: 1999  (integer — exact)
```

## When to Use

| Scenario | Apply This Pattern |
|----------|--------------------|
| Any monetary amount in a model | Yes — always cents |
| Displaying prices to users | Yes — `humanized_money` |
| Arithmetic between amounts | Yes — `Money` objects |
| External API returns float amount | Yes — convert to cents immediately |
| Storing currency code | Yes — alongside the cents column |

## Workflow Checklist

```
Money Pattern Implementation:
- [ ] Step 1: Add money-rails gem
- [ ] Step 2: Create initializer
- [ ] Step 3: Migration — integer *_cents column + currency column
- [ ] Step 4: Monetize model attributes
- [ ] Step 5: Update service objects to work with Money objects
- [ ] Step 6: Update views to use humanized_money helpers
- [ ] Step 7: Write specs — arithmetic, formatting, edge cases
```

## Step 1: Gemfile

```ruby
gem "money-rails", "~> 1.15"
```

## Step 2: Initializer

```ruby
# config/initializers/money.rb
MoneyRails.configure do |config|
  config.default_currency = :usd

  # Raise on ambiguous currency operations
  config.raise_error_on_money_parsing = true

  # Store in cents (subunit) — never change this after data exists
  config.amount_column = { postfix: "_cents", type: :integer }

  # Optional: locale-aware formatting
  config.locale_backend = :i18n
end
```

## Step 3: Migration

```ruby
class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      # ✅ Integer cents + currency code — the correct pattern
      t.integer  :amount_cents,    null: false, default: 0
      t.string   :amount_currency, null: false, default: "USD"

      # For multi-currency totals
      t.integer  :tax_cents,       null: false, default: 0
      t.string   :tax_currency,    null: false, default: "USD"

      t.timestamps
    end
  end
end
```

## Step 4: Monetize Model

```ruby
# app/models/order.rb
class Order < ApplicationRecord
  monetize :amount_cents
  monetize :tax_cents

  # Optional: restrict to specific currencies
  monetize :amount_cents, with_currency: :usd

  # Computed money attribute (not stored)
  def total
    amount + tax
  end

  validates :amount_cents, numericality: { greater_than: 0 }
end
```

## Step 5: Working with Money in Services

```ruby
# app/services/orders/create_service.rb
module Orders
  class CreateService < ApplicationService
    def initialize(user:, params:)
      @user   = user
      @params = params
    end

    def call
      # ✅ Parse once — reuse for both amount and tax calculation
      amount = parse_amount(params[:amount], params[:currency] || "USD")
      order  = Order.new(user: user, amount: amount, tax: calculate_tax(amount))

      if order.save
        Success(order)
      else
        Failure(order.errors.full_messages.join(", "))
      end
    rescue ArgumentError => e
      Failure(e.message)
    end

    private

    attr_reader :user, :params

    def parse_amount(raw, currency)
      case raw
      when Money    then raw
      when Integer  then Money.new(raw, currency)                  # Already cents
      when String   then Money.from_amount(raw.to_d, currency)     # "19.99" → 1999 cents
      when Float    then Money.from_amount(raw.to_s.to_d, currency) # ✅ to_s first — avoids float imprecision
      else raise ArgumentError, "Cannot parse amount: #{raw.inspect}"
      end
    end

    def calculate_tax(amount)
      # ✅ Money arithmetic is exact — no float errors
      amount * 0.1
    end
  end
end
```

## Step 6: Views

```erb
<%# app/views/orders/show.html.erb %>

<%# ✅ Formatted with currency symbol and locale %>
<p><%= humanized_money @order.amount %></p>
<%# → "$19.99" %>

<%# With explicit options %>
<p><%= humanized_money_with_symbol @order.amount %></p>
<%# → "$19.99" %>

<%# Just the number, no symbol %>
<p><%= humanized_money @order.amount, no_cents_if_whole: true %></p>
<%# → "$20" for whole numbers, "$19.99" otherwise %>

<%# In a form — store as cents, display as dollars %>
<%= f.money_field :amount, as: :money %>
```

## Step 7: Converting External API Floats

External APIs often return amounts as floats. Convert to `BigDecimal` immediately to avoid float accumulation:

```ruby
# ❌ WRONG — float arithmetic accumulates errors
amount_in_cents = (api_response["amount"] * 100).round  # May be 1998 instead of 1999

# ✅ CORRECT — convert float to string → BigDecimal → cents
raw     = api_response["amount"]          # e.g. 19.99 (Float from JSON)
decimal = raw.to_s.to_d                   # "19.99".to_d → BigDecimal("19.99")
cents   = (decimal * 100).to_i            # 1999 (exact)
money   = Money.new(cents, "USD")
```

## Money Arithmetic

```ruby
# Money objects support standard arithmetic — always returns Money
price    = Money.new(1999, "USD")   # $19.99
tax_rate = 0.1

tax      = price * tax_rate         # Money($2.00) — rounds correctly
total    = price + tax              # Money($21.99)
discount = price - Money.new(500)   # Money($14.99)

# Comparison
price > Money.new(1000, "USD")      # true
price == Money.new(1999, "USD")     # true

# ❌ CANNOT add different currencies without exchange rate
# Money.new(1000, "USD") + Money.new(1000, "EUR") → raises Money::Bank::UnknownRate
```

## Multi-Currency

```ruby
# Storing multiple currencies on the same record
class Invoice < ApplicationRecord
  monetize :subtotal_cents
  monetize :tax_cents
  monetize :total_cents

  # Each monetized attribute stores its own currency column
  # subtotal_cents + subtotal_currency
  # tax_cents + tax_currency
  # total_cents + total_currency
end

# Exchange rates (via external service)
Money.default_bank = Money::Bank::VariableExchange.new
Money.default_bank.set_rate("EUR", "USD", 1.08)
Money.default_bank.set_rate("USD", "EUR", 0.93)

eur_amount = Money.new(1000, "EUR")
usd_amount = eur_amount.exchange_to("USD")  # Money($10.80)
```

## Testing

```ruby
RSpec.describe Order do
  describe "money attributes" do
    it "stores amount as cents" do
      order = build(:order, amount: Money.new(1999, "USD"))
      expect(order.amount_cents).to eq(1999)
      expect(order.amount_currency).to eq("USD")
    end

    it "computes correct total" do
      order = build(:order, amount: Money.new(1000, "USD"), tax: Money.new(100, "USD"))
      expect(order.total).to eq(Money.new(1100, "USD"))
    end
  end
end

RSpec.describe Orders::CreateService do
  it "accepts string amount and converts to cents" do
    result = described_class.call(user: create(:user), params: { amount: "19.99", currency: "USD" })
    expect(result).to be_success
    expect(result.value!.amount_cents).to eq(1999)
  end

  it "accepts float from external API without precision loss" do
    result = described_class.call(user: create(:user), params: { amount: 19.99, currency: "USD" })
    expect(result).to be_success
    expect(result.value!.amount_cents).to eq(1999)
  end
end
```

## FactoryBot

```ruby
# spec/factories/orders.rb
FactoryBot.define do
  factory :order do
    user
    amount_cents    { 1999 }
    amount_currency { "USD" }
    tax_cents       { 200 }
    tax_currency    { "USD" }
  end
end
```

## Anti-Patterns to Avoid

1. **Float columns for money** — `t.float :price` or `t.decimal :price` — use `t.integer :price_cents`
2. **`amount * 0.1` without Money object** — use `Money.new(cents) * 0.1`, not raw integer math
3. **Rounding in the wrong place** — round only at display time, never during intermediate calculations
4. **Storing currency symbol** — store ISO code (`"USD"`, `"EUR"`), not symbol (`"$"`, `"€"`)
5. **Float from JSON without BigDecimal conversion** — always `raw.to_s.to_d` before multiplying
6. **Comparing Money with integers** — `order.amount > 0` fails; use `order.amount > Money.new(0, "USD")` or `order.amount_cents > 0`
