---
name: data-migrations
description: Data migrations separate from schema migrations - data_migrate gem, safe backfills with find_in_batches, zero-downtime strategies, and when NOT to use schema migrations for data transformations.
allowed-tools: Read, Write, Edit, Bash
---

# Data Migrations

## Overview

**Schema migrations** change database structure. **Data migrations** transform existing data. Mixing them is dangerous in production:

- Schema migrations run with a deploy — they must be fast and reversible
- Data migrations can take minutes or hours on large tables — blocking deploys and reads
- If a data migration fails halfway, your app may be in an inconsistent state

**Rule:** Never backfill data in a schema migration file.

```
db/migrate/20240101_add_status_to_orders.rb  ← schema only
db/data/20240101_backfill_order_statuses.rb  ← data only (data_migrate gem)
```

## When to Use

| Scenario | Use Data Migration? |
|----------|---------------------|
| Backfilling a new column for existing rows | Yes |
| Transforming data format (snake_case → camelCase) | Yes |
| Deduplicating records | Yes |
| Populating a denormalized column | Yes |
| Setting a default value for existing rows | Yes — not in schema migration |
| Creating records for new feature (seeds) | Sometimes — use seeds for dev, data migration for prod |
| Dropping a column | No — schema migration |

## Workflow Checklist

```
Data Migration Implementation:
- [ ] Step 1: Install data_migrate gem
- [ ] Step 2: Create schema migration (structure only — no data)
- [ ] Step 3: Create data migration (data only — no DDL)
- [ ] Step 4: Write data migration in batches (find_in_batches)
- [ ] Step 5: Add rollback strategy (up/down or reversible check)
- [ ] Step 6: Test locally against a copy of prod data volume
- [ ] Step 7: Deploy schema + data migration separately if zero-downtime
```

## Step 1: Gem

```ruby
# Gemfile
gem "data_migrate", "~> 9.4"
```

```bash
bundle install
bundle exec rails data_migrate:install:migrations   # creates db/data/ directory
```

**Available commands:**

```bash
bundle exec rails db:migrate:with_data      # runs schema + data migrations together
bundle exec rails db:data:migrate           # runs only data migrations
bundle exec rails db:data:rollback          # rolls back last data migration
bundle exec rails db:migrate:status:with_data  # shows status of both
```

## Step 2: Schema Migration — Structure Only

```ruby
# db/migrate/20240101120000_add_full_name_to_users.rb
class AddFullNameToUsers < ActiveRecord::Migration[8.1]
  def change
    # ✅ Structure only — no UPDATE, no backfill
    add_column :users, :full_name, :string

    # Allow null initially so existing rows don't fail
    # The data migration will fill it in
  end
end
```

## Step 3: Data Migration — Data Only

```ruby
# db/data/20240101120001_backfill_user_full_names.rb
class BackfillUserFullNames < ActiveRecord::Migration[8.1]
  # ✅ No DDL here — only data transformations

  def up
    User.find_in_batches(batch_size: 1_000) do |batch|
      batch.each do |user|
        full_name = [user.first_name, user.last_name].compact.join(" ").presence
        # Use update_column to skip validations and callbacks (faster, safer for backfills)
        user.update_column(:full_name, full_name) if full_name
      end
    end
  end

  def down
    # Revert: clear the column
    User.update_all(full_name: nil)
  end
end
```

## Step 4: Batch Processing Patterns

### find_in_batches — Memory Safe

```ruby
# ✅ Processes 1000 records at a time — never loads all into memory
def up
  User.find_in_batches(batch_size: 1_000) do |batch|
    batch.each { |user| user.update_column(:full_name, compute_full_name(user)) }
  end
end
```

### update_all — Fast Bulk Update (No Callbacks)

```ruby
# ✅ Single SQL UPDATE — fastest for simple transformations
def up
  # Set status based on existing column value
  Order.where(paid_at: nil).update_all(status: "pending")
  Order.where.not(paid_at: nil).update_all(status: "paid")
end
```

### in_batches — For Complex Updates with SQL

```ruby
# ✅ in_batches gives you a relation, allowing batched SQL UPDATEs
def up
  Order.where(status: nil).in_batches(of: 5_000) do |batch|
    batch.update_all(
      "status = CASE WHEN paid_at IS NOT NULL THEN 'paid' ELSE 'pending' END"
    )
  end
end
```

### insert_all / upsert_all — For Creating Records in Bulk

```ruby
# ✅ Batched bulk insert — avoids loading all records into memory
def up
  User.find_in_batches(batch_size: 1_000) do |batch|
    records = batch.map do |user|
      {
        user_id:    user.id,
        balance:    0,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    LedgerAccount.insert_all(records, unique_by: :user_id)
  end
end
```

## Step 5: Zero-Downtime Strategy

For large tables (>1M rows), running a data migration at deploy time blocks the deploy and may lock the table.

**Deploy in 3 steps:**

```
Step 1 — Schema migration:
  Add column (nullable, no default)
  Deploy app code that writes to NEW column but reads from OLD

Step 2 — Data migration (off-hours or background job):
  Backfill the new column in batches
  Monitor progress — can be stopped and resumed

Step 3 — Cleanup migration:
  Add NOT NULL constraint
  Remove old column if applicable
  Deploy app code that reads from NEW column only
```

**Background job backfill alternative (for very large tables):**

```ruby
# When the data migration would take >5 minutes, use a job instead
class BackfillLedgerAccountsJob < ApplicationJob
  queue_as :maintenance

  def perform(last_processed_id = 0)
    batch = User.where("id > ?", last_processed_id).order(:id).limit(500)
    return if batch.empty?

    batch.each do |user|
      LedgerAccount.find_or_create_by!(user_id: user.id) do |account|
        account.balance = 0
      end
    end

    # Enqueue next batch
    BackfillLedgerAccountsJob.perform_later(batch.last.id)
  end
end

# Kick off in a data migration
class BackfillLedgerAccounts < ActiveRecord::Migration[8.1]
  def up
    BackfillLedgerAccountsJob.perform_later
  end

  def down
    LedgerAccount.delete_all
  end
end
```

## Step 6: Testing Data Migrations

```ruby
# spec/data/backfill_user_full_names_spec.rb
require "rails_helper"
require Rails.root.join("db/data/20240101120001_backfill_user_full_names")

RSpec.describe BackfillUserFullNames do
  describe "#up" do
    let!(:user_with_names) { create(:user, first_name: "Jane", last_name: "Doe", full_name: nil) }
    let!(:user_no_last)    { create(:user, first_name: "Prince", last_name: nil, full_name: nil) }

    before { described_class.new.up }

    it "combines first and last name" do
      expect(user_with_names.reload.full_name).to eq("Jane Doe")
    end

    it "uses only first name when last name is nil" do
      expect(user_no_last.reload.full_name).to eq("Prince")
    end
  end

  describe "#down" do
    before do
      described_class.new.up
      described_class.new.down
    end

    it "clears full_name" do
      expect(User.where.not(full_name: nil).count).to eq(0)
    end
  end
end
```

## Monitoring Backfill Progress

```ruby
# Add logging to long-running data migrations
def up
  total    = User.count
  processed = 0

  User.find_in_batches(batch_size: 1_000) do |batch|
    batch.each { |user| user.update_column(:full_name, compute_full_name(user)) }
    processed += batch.size
    Rails.logger.info("Backfill progress: #{processed}/#{total} (#{(processed.to_f / total * 100).round(1)}%)")
  end
end
```

## Anti-Patterns to Avoid

1. **Data transformations in schema migration files** — slow, hard to skip if they fail
2. **`User.all.each` without batching** — loads all records into memory; use `find_in_batches`
3. **`user.save` in backfills** — triggers validations and callbacks; use `update_column` or `update_all`
4. **No rollback strategy** — always implement `down` or document why rollback is not possible
5. **Running multi-million-row backfills synchronously at deploy** — use a background job or schedule off-peak
6. **Adding NOT NULL constraint in the same migration that backfills** — add column nullable, backfill, then add constraint in a separate migration
7. **No progress logging** — backfills that take >5 minutes need progress output for monitoring
