---
name: search-patterns
description: Full-text and filtered search in Rails using pg_search (PostgreSQL native), ransack (filter forms), and searchkick (Elasticsearch). Use when adding search bars, filter UIs, or autocomplete to Rails apps.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Search Patterns for Rails

## Overview

| Tool | Use When |
|------|----------|
| **pg_search** | Full-text search on PostgreSQL — no extra infrastructure |
| **ransack** | Admin filter forms, multi-field filtering, sortable tables |
| **searchkick** | Elasticsearch/OpenSearch — fuzzy, typo-tolerant, faceted |
| **ILIKE / tsvector raw** | Simple one-field search, no gem needed |

**Default choice:** `pg_search` for most apps (no extra infra, good enough for millions of rows).

---

## 1. pg_search — PostgreSQL Full-Text Search

### Setup

```ruby
# Gemfile
gem "pg_search"
```

### Multisearch (single model)

```ruby
# app/models/post.rb
class Post < ApplicationRecord
  include PgSearch::Model

  pg_search_scope :search_by_content,
    against: {
      title:   "A",   # Weight A = highest
      excerpt: "B",
      body:    "C"
    },
    using: {
      tsearch: {
        dictionary:     "english",  # stemming: "running" matches "run"
        tsvector_column: "search_vector"  # optional pre-computed column
      },
      trigram: { threshold: 0.3 }  # handles partial matches
    }
end

# Usage
Post.search_by_content("rails performance")
```

### Multi-model global search

```ruby
# app/models/post.rb
class Post < ApplicationRecord
  include PgSearch::Model
  multisearchable against: [:title, :body]
end

# app/models/user.rb
class User < ApplicationRecord
  include PgSearch::Model
  multisearchable against: [:name, :email]
end

# Search across all models
PgSearch.multisearch("john")
# => [PgSearch::Document, ...] — call .searchable to get the original record
results = PgSearch.multisearch("john").includes(:searchable).map(&:searchable)
```

### Performance: pre-computed tsvector column

For large tables, pre-compute the search vector with a DB trigger instead of computing on every query:

```ruby
# Migration
class AddSearchVectorToPosts < ActiveRecord::Migration[8.1]
  def up
    add_column :posts, :search_vector, :tsvector

    execute <<~SQL
      CREATE INDEX posts_search_vector_idx ON posts USING gin(search_vector);

      CREATE OR REPLACE FUNCTION posts_search_vector_update() RETURNS trigger AS $$
      BEGIN
        NEW.search_vector :=
          setweight(to_tsvector('english', coalesce(NEW.title, '')), 'A') ||
          setweight(to_tsvector('english', coalesce(NEW.body, '')), 'C');
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER posts_search_vector_trigger
      BEFORE INSERT OR UPDATE ON posts
      FOR EACH ROW EXECUTE FUNCTION posts_search_vector_update();
    SQL

    # Backfill existing rows
    execute "UPDATE posts SET search_vector = NULL"
  end

  def down
    remove_column :posts, :search_vector
  end
end
```

### In a Query Object

```ruby
# app/queries/posts/search_query.rb
module Posts
  class SearchQuery
    def call(params = {})
      Post.all
          .then { |r| full_text_search(r, params[:q]) }
          .then { |r| filter_by_status(r, params[:status]) }
          .then { |r| filter_by_author(r, params[:author_id]) }
          .order(params[:sort] == "oldest" ? :created_at : { created_at: :desc })
    end

    private

    def full_text_search(relation, query)
      return relation if query.blank?
      relation.search_by_content(query)
    end

    def filter_by_status(relation, status)
      return relation if status.blank?
      relation.where(status: status)
    end

    def filter_by_author(relation, author_id)
      return relation if author_id.blank?
      relation.where(author_id: author_id)
    end
  end
end
```

---

## 2. Simple ILIKE (no gem, single field)

For a basic search bar with one field, no gem is needed:

```ruby
# In a Query Object
def full_text_search(relation, query)
  return relation if query.blank?
  relation.where("title ILIKE ?", "%#{sanitize_sql_like(query)}%")
end

# Model concern for reuse
scope :search, ->(q) {
  where("title ILIKE :q OR description ILIKE :q", q: "%#{sanitize_sql_like(q)}%") if q.present?
}
```

---

## 3. ransack — Filter Forms

Ransack generates search forms without custom query logic. Best for admin panels and sortable tables.

### Setup

```ruby
# Gemfile
gem "ransack"
```

### Controller

```ruby
class Admin::PostsController < Admin::BaseController
  def index
    @q = Post.ransack(ransack_params)
    @posts = @q.result(distinct: true)
                .includes(:author)
                .order(:created_at)
  end

  private

  # IMPORTANT: allowlist ransack params to prevent mass assignment
  def ransack_params
    params.fetch(:q, {}).permit(
      :title_cont,          # title contains
      :status_eq,           # status equals
      :author_name_cont,    # author.name contains (joins automatically)
      :created_at_gteq,     # created_at >= date
      :created_at_lteq,     # created_at <= date
      :s                    # sort
    )
  end
end
```

### View (search form)

```erb
<%# app/views/admin/posts/index.html.erb %>
<%= search_form_for @q, url: admin_posts_path do |f| %>
  <div class="flex gap-4">
    <%= f.label :title_cont, "Title" %>
    <%= f.search_field :title_cont, class: "input" %>

    <%= f.label :status_eq, "Status" %>
    <%= f.select :status_eq, Post.statuses.keys, include_blank: "All", class: "select" %>

    <%= f.label :created_at_gteq, "From" %>
    <%= f.date_field :created_at_gteq, class: "input" %>

    <%= f.submit "Search", class: "btn btn-primary" %>
  </div>
<% end %>

<%# Sortable column header %>
<th><%= sort_link(@q, :title, "Title") %></th>
<th><%= sort_link(@q, :created_at, "Date") %></th>
```

### ransack predicate reference

```
_eq         exact match
_cont       contains (ILIKE %val%)
_start      starts with
_end        ends with
_gt / _lt   greater/less than
_gteq/_lteq >=, <=
_in         IN array
_null       IS NULL
_not_eq     !=
_matches    LIKE (manual wildcard)
```

---

## 4. searchkick — Elasticsearch / OpenSearch

Use only when you need fuzzy matching, typo tolerance, or faceted filters at scale.

```ruby
# Gemfile
gem "searchkick"

# Model
class Product < ApplicationRecord
  searchkick word_start: [:name],
             text_middle: [:description],
             filterable: [:category, :brand, :active]

  def search_data
    {
      name:        name,
      description: description,
      category:    category.name,
      brand:       brand,
      active:      active,
      price_cents: price_cents
    }
  end
end

# Reindex
Product.reindex

# Search
Product.search(
  "wireless headphones",
  fields:  [:name, :description],
  where:   { active: true, category: "Electronics" },
  order:   { price_cents: :asc },
  page:    params[:page],
  per_page: 25
)
```

---

## Testing pg_search

```ruby
RSpec.describe Posts::SearchQuery do
  let!(:rails_post)  { create(:post, title: "Rails Performance Tips", status: "published") }
  let!(:ruby_post)   { create(:post, title: "Ruby Metaprogramming", status: "published") }
  let!(:draft_post)  { create(:post, title: "Rails Draft", status: "draft") }

  subject(:query) { described_class.new }

  it "finds posts matching the search term" do
    results = query.call(q: "rails")
    expect(results).to include(rails_post)
    expect(results).not_to include(ruby_post)
  end

  it "filters by status" do
    results = query.call(status: "published")
    expect(results).not_to include(draft_post)
  end

  it "returns all posts when query is blank" do
    results = query.call(q: "")
    expect(results).to include(rails_post, ruby_post)
  end
end
```

## Checklist

- [ ] Choose tool: pg_search (default) / ILIKE (simple) / ransack (admin forms) / searchkick (fuzzy at scale)
- [ ] Wrap in a Query Object — keep search logic out of controllers and models
- [ ] Add GIN index on `tsvector` column for pg_search on large tables
- [ ] Allowlist ransack params explicitly (never `params[:q]` directly)
- [ ] Sanitize ILIKE queries with `sanitize_sql_like`
- [ ] Test: hit, miss, blank query, combined filters
- [ ] Combine with `pagination-patterns` skill for paginated search results
