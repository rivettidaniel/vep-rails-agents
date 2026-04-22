---
name: bulk-operations
description: Bulk insert, upsert, and update operations in Rails - insert_all, upsert_all, update_all, find_in_batches, and activerecord-import. Use when processing large datasets, imports, or batch writes that would be too slow with individual ActiveRecord saves.
allowed-tools: Read, Write, Edit, Bash
---

# Bulk Operations

## Overview

Individual ActiveRecord saves are expensive: each `record.save` triggers validations, callbacks, and a separate SQL INSERT/UPDATE. For large datasets this becomes a bottleneck:

```
1,000 records × record.save = 1,000 SQL statements + 1,000 callback cycles
1,000 records × insert_all  = 1 SQL statement, no callbacks
```

**When to bulk-operate:**
- Importing CSV / JSON data (hundreds or thousands of records)
- Backfilling a new column
- Batch status updates
- Processing job queues
- Seeding or syncing from external APIs

**Trade-off:** Bulk operations skip validations and callbacks — use them only where that's acceptable (imports, backfills, maintenance jobs).

## Operations Reference

| Operation | SQL | Validations | Callbacks | Use When |
|-----------|-----|-------------|-----------|----------|
| `record.save` | INSERT/UPDATE | ✅ | ✅ | Single record, full safety |
| `insert_all` | INSERT | ❌ | ❌ | Bulk insert, no conflict handling |
| `upsert_all` | INSERT ON CONFLICT | ❌ | ❌ | Bulk insert or update by unique key |
| `update_all` | UPDATE | ❌ | ❌ | Bulk update same value |
| `find_in_batches` | SELECT in batches | N/A | N/A | Reading large datasets |
| `in_batches` | SELECT in batches | N/A | N/A | Batch operations on relations |

## insert_all — Bulk Insert

```ruby
# ✅ One SQL INSERT for N records — no validations, no callbacks
records = users.map do |user|
  {
    user_id:    user.id,
    balance:    0,
    created_at: Time.current,
    updated_at: Time.current
  }
end

LedgerAccount.insert_all(records)

# With returning (PostgreSQL) — get the inserted IDs back
result = LedgerAccount.insert_all(records, returning: [:id, :user_id])
result.rows  # [[1, 42], [2, 43], ...]
```

**Skip duplicates silently (INSERT IGNORE behavior):**

```ruby
# unique_by tells Rails which unique constraint to check
LedgerAccount.insert_all(records, unique_by: :user_id)
# → duplicate user_ids are silently skipped, no error
```

## upsert_all — Insert or Update

```ruby
# INSERT ... ON CONFLICT DO UPDATE
# If record exists (by unique key) → update it; otherwise → insert it
LedgerAccount.upsert_all(
  records,
  unique_by: :user_id,
  update_only: [:balance, :updated_at]  # Only update these columns on conflict
)

# Without update_only — updates ALL columns on conflict
LedgerAccount.upsert_all(records, unique_by: :user_id)
```

**Practical example — sync from external API:**

```ruby
# app/services/products/sync_from_api_service.rb
module Products
  class SyncFromApiService < ApplicationService
    def call
      raw_products = ExternalCatalogApi.fetch_all

      records = raw_products.map do |p|
        {
          external_id: p["id"],
          name:        p["name"],
          price_cents: (p["price"].to_s.to_d * 100).to_i,  # ✅ to_s first — avoids float imprecision
          active:      p["available"],
          synced_at:   Time.current,
          created_at:  Time.current,
          updated_at:  Time.current
        }
      end

      Product.upsert_all(records, unique_by: :external_id)
      Success(records.size)
    rescue StandardError => e
      Failure("Sync failed: #{e.message}")
    end
  end
end
```

## update_all — Bulk Update Same Value

```ruby
# ✅ Single UPDATE statement — no callbacks, no validations
Order.where(status: nil).update_all(status: "pending")

# With expressions
Order.where("created_at < ?", 1.year.ago).update_all(
  archived: true,
  archived_at: Time.current
)

# ❌ WRONG — triggers N individual UPDATEs
orders.each { |o| o.update!(status: "pending") }

# ✅ CORRECT — one SQL statement
Order.where(id: order_ids).update_all(status: "pending")
```

**With SQL expressions:**

```ruby
# Increment a counter without loading records
LedgerAccount.where(user_id: user_id)
             .update_all("balance = balance + #{amount.to_i}")
             # ⚠️ Use interpolation carefully — only with validated integers

# Safer with Arel
LedgerAccount.where(user_id: user_id)
             .update_all(
               LedgerAccount.sanitize_sql(["balance = balance + ?", amount])
             )
```

## find_in_batches / find_each — Memory-Safe Reads

```ruby
# find_each — simplest, processes one record at a time
User.find_each(batch_size: 1_000) do |user|
  SomeExpensiveService.call(user: user)
end

# find_in_batches — gives you the whole batch as an array
User.find_in_batches(batch_size: 1_000) do |users|
  # Process the whole batch at once — useful for bulk inserts within the batch
  records = users.map { |u| build_record(u) }
  TargetModel.insert_all(records)
end

# With conditions
Order.where(status: :pending)
     .find_in_batches(batch_size: 500) do |batch|
  batch_ids = batch.map(&:id)
  Order.where(id: batch_ids).update_all(status: :processing)
end
```

## in_batches — Batch Operations on Relations

```ruby
# Returns a BatchEnumerator — gives you the relation for each batch
User.in_batches(of: 1_000) do |batch_relation|
  batch_relation.update_all(migrated: true)
end

# With start/finish for resumable backfills
User.in_batches(of: 1_000, start: last_processed_id) do |batch|
  batch.update_all(new_column: "value")
end
```

## Full Import Pipeline Example

```ruby
# app/services/ledger/import_events_service.rb
module Ledger
  class ImportEventsService < ApplicationService
    BATCH_SIZE = 500

    def initialize(file_path:, user:)
      @file_path = file_path
      @user      = user
    end

    def call
      rows = parse_csv(file_path)
      return Failure("File is empty") if rows.empty?

      valid, invalid = validate_rows(rows)
      return Failure("#{invalid.size} invalid rows found") if invalid.any?

      inserted = bulk_insert(valid)
      Success({ inserted: inserted, skipped: rows.size - inserted })
    rescue CSV::MalformedCSVError => e
      Failure("Invalid CSV format: #{e.message}")
    rescue StandardError => e
      Failure("Import failed: #{e.message}")
    end

    private

    attr_reader :file_path, :user

    def parse_csv(path)
      CSV.foreach(path, headers: true).map(&:to_h)
    end

    def validate_rows(rows)
      rows.partition do |row|
        row["amount"].present? &&
          row["type"].in?(%w[deposit withdrawal]) &&
          row["reference_id"].present?
      end
    end

    def bulk_insert(rows)
      rows.each_slice(BATCH_SIZE).sum do |batch|
        records = batch.map do |row|
          {
            user_id:      user.id,
            type:         row["type"],
            amount_cents: (row["amount"].to_d * 100).to_i,
            reference_id: row["reference_id"],
            status:       "pending",
            created_at:   Time.current,
            updated_at:   Time.current
          }
        end

        result = LedgerEvent.insert_all(records, unique_by: :reference_id)
        result.length
      end
    end
  end
end
```

## Callbacks and Validations — When You Need Them

If you need validations or callbacks with bulk data, validate in Ruby before inserting:

```ruby
def bulk_insert_with_validation(records)
  valid_records = records.select do |attrs|
    record = Order.new(attrs)
    record.valid?
  end

  Order.insert_all(valid_records) if valid_records.any?
  valid_records.size
end
```

Or use a two-pass approach — insert raw, validate after:

```ruby
# Insert all, flag invalid ones
Order.insert_all(records)

# Then validate and mark invalid
Order.where(validated: false).find_each do |order|
  order.valid? ? order.update_column(:validated, true) : order.discard!
end
```

## Performance Benchmarks

```
1,000 records:
  order.save × 1,000     →  ~2,500ms  (individual INSERTs + callbacks)
  insert_all(1,000)       →  ~15ms    (single INSERT)

10,000 records:
  order.save × 10,000    →  ~25,000ms
  insert_all in batches   →  ~150ms
```

## Testing Bulk Operations

```ruby
RSpec.describe Ledger::ImportEventsService do
  let(:user) { create(:user) }
  let(:csv_file) { Rails.root.join("spec/fixtures/ledger_events.csv") }

  it "inserts all valid rows" do
    expect {
      described_class.call(file_path: csv_file, user: user)
    }.to change(LedgerEvent, :count).by(5)
  end

  it "skips duplicate reference_ids" do
    create(:ledger_event, reference_id: "ref_001", user: user)

    result = described_class.call(file_path: csv_file, user: user)

    expect(result).to be_success
    expect(result.value![:skipped]).to eq(1)
  end

  it "returns Failure for empty file" do
    empty_file = Tempfile.new(["empty", ".csv"])
    result = described_class.call(file_path: empty_file.path, user: user)
    expect(result).to be_failure
    expect(result.failure).to include("empty")
  end
end
```

## Anti-Patterns to Avoid

1. **`Model.all.each` without batching** — loads all records into memory; use `find_each`
2. **`insert_all` without timestamps** — always include `created_at` and `updated_at`; `insert_all` does NOT add them automatically
3. **`update_all` with string interpolation of user input** — SQL injection risk; use `sanitize_sql` or parameterized values
4. **Batches that are too large** — `insert_all` with 100,000 records in one call can exhaust memory or hit PostgreSQL limits; use 500-2,000 per batch
5. **Assuming callbacks run on `insert_all`** — they don't; if you need `after_create` behavior, trigger it manually after insert
6. **`upsert_all` without `unique_by`** — without a unique constraint to conflict on, behavior is undefined
7. **Skipping validation silently** — document clearly when validations are skipped, and add a post-import validation pass if data quality matters

## Related Skills

| Need | Use |
|------|-----|
| Bulk-enqueuing N background jobs from a scheduler job | `job-fan-out-pattern` skill |
| Separate data migrations from schema migrations | `data-migrations` skill |
| Memory-safe reads + bulk writes in background jobs | `solid-queue-setup` skill |
