---
name: api-serialization
description: JSON serialization for Rails APIs using Blueprinter (preferred) or ActiveModel::Serializers. Use when building API endpoints that need consistent JSON output, field selection, nested associations, and versioning.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# API Serialization in Rails

## Overview

| Option | Use When |
|--------|----------|
| **Blueprinter** | Default — fast, explicit, zero magic, composable views |
| **ActiveModel::Serializers** | Legacy codebases already using it |
| **Jbuilder** | Simple one-off views, no gem needed |
| **as_json / to_json** | Throwaway scripts, never in production APIs |

**Default choice:** Blueprinter. It's explicit, fast, and has no ActiveRecord coupling.

---

## Setup — Blueprinter

```ruby
# Gemfile
gem "blueprinter"
```

## Basic Serializer

```ruby
# app/serializers/post_serializer.rb
class PostSerializer < Blueprinter::Base
  identifier :id

  fields :title, :status, :created_at

  field :published_at do |post|
    post.published_at&.iso8601
  end

  field :excerpt do |post|
    post.body.truncate(160)
  end
end
```

```ruby
# Controller
render json: PostSerializer.render(@post)
render json: PostSerializer.render(@posts)  # works with arrays too
```

## Views — Field Groups

```ruby
class PostSerializer < Blueprinter::Base
  identifier :id

  # :default view — always rendered
  fields :title, :status, :created_at

  # :summary view — lightweight list response
  view :summary do
    fields :title, :status
  end

  # :detail view — full response with all fields
  view :detail do
    include_view :default

    fields :body, :published_at, :updated_at

    field :word_count do |post|
      post.body.split.size
    end
  end
end
```

```ruby
# Controller
def index
  @posts = Post.published.order(created_at: :desc)
               .paginate(page: params[:page], per_page: 25)
  render json: PostSerializer.render(@posts, view: :summary)
end

def show
  render json: PostSerializer.render(@post, view: :detail)
end
```

## Associations

```ruby
class PostSerializer < Blueprinter::Base
  identifier :id
  fields :title, :status

  # Inline association (uses UserSerializer automatically)
  association :author, blueprint: UserSerializer, view: :summary

  # Collection association
  association :tags, blueprint: TagSerializer

  # Conditional association
  association :comments, blueprint: CommentSerializer do |post, options|
    post.comments.published if options[:include_comments]
  end
end

class UserSerializer < Blueprinter::Base
  identifier :id

  view :summary do
    fields :name, :avatar_url
  end

  view :detail do
    include_view :summary
    fields :email, :created_at
  end
end
```

```ruby
# Render with nested associations
render json: PostSerializer.render(@post, view: :detail, include_comments: true)
```

## Passing Options / Context

```ruby
class PostSerializer < Blueprinter::Base
  identifier :id
  fields :title

  field :can_edit do |post, options|
    options[:current_user]&.admin? || post.author_id == options[:current_user]&.id
  end
end

# Controller
render json: PostSerializer.render(@post, current_user: current_user)
```

## Pagination Envelope

```ruby
# app/controllers/concerns/json_response.rb
module JsonResponse
  extend ActiveSupport::Concern

  def render_paginated(serializer, records, **options)
    render json: {
      data:       serializer.render_as_hash(records, **options),
      pagination: {
        page:        records.current_page,
        per_page:    records.per_page,
        total:       records.total_entries,
        total_pages: records.total_pages
      }
    }
  end
end

# Controller
class Api::V1::PostsController < Api::BaseController
  include JsonResponse

  def index
    @posts = Post.published.order(created_at: :desc)
                 .paginate(page: params[:page], per_page: 25)
    render_paginated(PostSerializer, @posts, view: :summary)
  end
end
```

## Error Responses

Consistent error format across all endpoints:

```ruby
# app/controllers/api/base_controller.rb
class Api::BaseController < ActionController::API
  rescue_from ActiveRecord::RecordNotFound do |e|
    render json: { error: e.message }, status: :not_found
  end

  rescue_from ActionController::ParameterMissing do |e|
    render json: { error: e.message }, status: :bad_request
  end

  def render_errors(record)
    render json: {
      error:  "Validation failed",
      errors: record.errors.as_json
    }, status: :unprocessable_entity
  end

  def render_service_failure(message)
    render json: { error: message }, status: :unprocessable_entity
  end
end
```

```ruby
# Standard controller pattern with service objects
class Api::V1::PostsController < Api::BaseController
  def create
    result = Posts::CreateService.call(user: current_user, params: post_params)

    if result.success?
      render json: PostSerializer.render(result.value!, view: :detail),
             status: :created
    else
      render_service_failure(result.failure)
    end
  end

  def update
    result = Posts::UpdateService.call(post: @post, params: post_params)

    if result.success?
      render json: PostSerializer.render(result.value!, view: :detail)
    else
      render_service_failure(result.failure)
    end
  end
end
```

## Versioning + Serializers

Keep serializers versioned when your API has breaking changes:

```
app/serializers/
├── v1/
│   ├── post_serializer.rb     # Api::V1::PostSerializer
│   └── user_serializer.rb
└── v2/
    ├── post_serializer.rb     # Api::V2::PostSerializer (new field names)
    └── user_serializer.rb
```

```ruby
# app/serializers/v1/post_serializer.rb
module V1
  class PostSerializer < Blueprinter::Base
    identifier :id
    fields :title, :body, :created_at
  end
end

# app/serializers/v2/post_serializer.rb
module V2
  class PostSerializer < Blueprinter::Base
    identifier :id
    fields :title, :content, :created_at  # "body" renamed to "content"

    field :author_name do |post|
      post.author.full_name
    end
  end
end
```

## Testing

```ruby
RSpec.describe PostSerializer do
  let(:author) { create(:user, name: "Alice") }
  let(:post)   { create(:post, title: "Hello", status: "published", author: author) }

  subject(:json) { JSON.parse(described_class.render(post, view: :detail)) }

  it "includes expected fields" do
    expect(json).to include(
      "id"     => post.id,
      "title"  => "Hello",
      "status" => "published"
    )
  end

  it "includes author association" do
    expect(json["author"]).to include("name" => "Alice")
  end

  it "excludes sensitive fields" do
    expect(json).not_to have_key("body_raw")
  end

  describe "summary view" do
    subject(:json) { JSON.parse(described_class.render(post, view: :summary)) }

    it "omits heavy fields" do
      expect(json).not_to have_key("body")
    end
  end
end
```

## Checklist

- [ ] `blueprinter` in Gemfile
- [ ] One serializer per resource in `app/serializers/`
- [ ] `:summary` view for list endpoints, `:detail` for show
- [ ] Associations explicitly declared (never implicit)
- [ ] Sensitive fields (password_digest, tokens) never included
- [ ] Options used for current_user-dependent fields (permissions, ownership)
- [ ] Consistent error format in `Api::BaseController`
- [ ] Pagination envelope on index endpoints
- [ ] Spec covers fields present, fields absent, nested associations
