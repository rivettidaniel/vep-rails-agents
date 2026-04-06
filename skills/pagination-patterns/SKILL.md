---
name: pagination-patterns
description: Pagination in Rails using will_paginate. Use when adding page navigation to index actions or API endpoints.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Pagination with will_paginate

## Setup

```ruby
# Gemfile
gem "will_paginate"
```

## Usage

```ruby
# Controller
def index
  @page  = params[:page] || 1
  @posts = Post.published.order(created_at: :desc)
               .paginate(page: @page, per_page: 25)
end
```

Works on any ActiveRecord relation — scopes, joins, includes, anything:

```ruby
@messages = User.role_support.last
               .unread_messages
               .order(:conversation_id)
               .paginate(page: @page, per_page: 25)
```

## View

```erb
<%= render @posts %>
<%= will_paginate @posts %>
```

## API Response

```ruby
def index
  @posts = Post.published.order(created_at: :desc)
               .paginate(page: params[:page], per_page: 25)

  render json: {
    posts:       PostSerializer.render(@posts),
    page:        @posts.current_page,
    total_pages: @posts.total_pages,
    total:       @posts.total_entries
  }
end
```

## Testing

```ruby
RSpec.describe PostsController, type: :request do
  before { create_list(:post, 30, :published) }

  it "paginates results" do
    get posts_path
    expect(assigns(:posts).size).to eq(25)
  end

  it "returns page 2" do
    get posts_path, params: { page: 2 }
    expect(assigns(:posts).size).to eq(5)
  end
end
```

## Checklist

- [ ] `gem "will_paginate"` in Gemfile
- [ ] `.paginate(page: params[:page], per_page: N)` on the relation
- [ ] `will_paginate @collection` in the view
- [ ] `includes()` on the relation to prevent N+1
