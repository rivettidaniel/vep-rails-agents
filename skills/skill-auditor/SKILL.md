---
name: skill-auditor
description: Audits and improves Rails skill files in a project. Use when reviewing a SKILL.md file for correctness, completeness, and best practices. Triggers on: "audit skill", "review skill", "check skill", "improve skill", "verify skill", or when asked to verify that skill code examples are correct.
allowed-tools: Read, Write, Edit, Glob, Grep
---

# Skill Auditor

## Overview

This skill systematically reviews `skills/*/SKILL.md` files for:
1. **Structural completeness** — correct frontmatter and required sections
2. **Code correctness** — bugs, wrong APIs, anti-patterns in examples
3. **Rails best practices** — adherence to project conventions
4. **Documentation quality** — clarity, Related Skills, decision guides

## Workflow Checklist

```
Skill Audit Progress:
- [ ] Step 1: Read target SKILL.md completely
- [ ] Step 2: Run structural checklist
- [ ] Step 3: Run code correctness checklist
- [ ] Step 4: Run Rails conventions checklist
- [ ] Step 5: Run documentation quality checklist
- [ ] Step 6: Generate findings report with severity
- [ ] Step 7: Apply fixes
- [ ] Step 8: Verify fixes don't break intent
```

## Step 1: Load the Skill

Read the target skill file completely before auditing:

```bash
# Find all skills to audit
ls skills/*/SKILL.md

# Or audit a specific skill
cat skills/[skill-name]/SKILL.md
```

If no skill is specified, ask: **"Which skill should I audit? Run `ls skills/` to list available skills."**

---

## Step 2: Structural Checklist

Verify the SKILL.md has required structure:

```
Structural Checks:
- [ ] YAML frontmatter present (--- block at top)
- [ ] `name` field in frontmatter matches directory name
- [ ] `description` field present and describes WHEN to use (not just what)
- [ ] `allowed-tools` field lists needed tools
- [ ] Markdown body starts with H1 title
- [ ] Has "Overview" or equivalent intro section
- [ ] Has "When to Use" guidance (table, list, or prose)
- [ ] Has at least one code example
- [ ] Under 500 lines (if longer, link to references/)
```

**Report format per issue:**
```
🔴 CRITICAL | Frontmatter missing `allowed-tools` field
🟡 WARNING  | No "When to Use" section — readers won't know when to apply this
🔵 INFO     | Consider adding a Related Skills section
```

---

## Step 3: Code Correctness Checklist

Scan all code blocks in the skill for these known bugs:

### 3.1 dry-monads API

```
- [ ] Uses Success() not success()  (correct: Success("value"), not success("value"))
- [ ] Uses Failure() not failure()  (correct: Failure("error"), not failure("error"))
- [ ] Uses result.value! not result.value or result.data
- [ ] Uses result.failure not result.error or result.errors
- [ ] Does NOT use errors.merge!(result.error) → use errors.add(:base, result.failure)
```

**Examples:**
```ruby
# ❌ Wrong dry-monads API
def call
  success(user)              # ❌ — lowercase, not a monad
  failure("invalid email")   # ❌ — lowercase, not a monad
end
result.value                 # ❌ — NoMethodError
result.data                  # ❌ — NoMethodError
result.error                 # ❌ — NoMethodError
errors.merge!(result.error)  # ❌ — wrong method + wrong accessor

# ✅ Correct dry-monads API
def call
  Success(user)              # ✅
  Failure("invalid email")   # ✅
end
result.value!                # ✅
result.failure               # ✅
errors.add(:base, result.failure)  # ✅
```

### 3.2 Callback Side Effects (CRITICAL)

```
- [ ] No after_create_commit with email/notification/job
- [ ] No after_save with email/notification/job
- [ ] No after_commit with email/notification/job
- [ ] No after_destroy with email/notification/job
- [ ] ONLY allowed: before_validation (normalization), before_save (defaults)
```

**Examples:**
```ruby
# ❌ Side effects in callbacks
class Post < ApplicationRecord
  after_create_commit :send_notification   # ❌
  after_save :update_search_index          # ❌
  after_commit :broadcast_changes          # ❌
end

# ✅ Side effects in controller
def create
  if @post.save
    PostMailer.notify(@post).deliver_later   # ✅
    SearchIndexJob.perform_later(@post)      # ✅
  end
end
```

### 3.3 Spec Paths

```
- [ ] Uses spec/requests/ not spec/controllers/
- [ ] Uses RSpec.describe [ClassName], type: :request for HTTP specs
```

**Examples:**
```ruby
# ❌ Old path
spec/controllers/posts_controller_spec.rb

# ✅ Correct path
spec/requests/posts_spec.rb
```

### 3.4 Turbo/Rails 7+ HTML Attributes

```
- [ ] Uses data: { turbo_method: :delete } not method: :delete
- [ ] Uses data: { turbo_confirm: "..." } not data: { confirm: "..." }
- [ ] Does NOT use local: true in form_with (disables Turbo)
```

**Examples:**
```erb
<%# ❌ Rails 6 syntax %>
<%= link_to "Delete", post_path(@post), method: :delete, data: { confirm: "Sure?" } %>
<%= form_with model: @post, local: true do |f| %>

<%# ✅ Rails 7 / Turbo syntax %>
<%= link_to "Delete", post_path(@post), data: { turbo_method: :delete, turbo_confirm: "Sure?" } %>
<%= form_with model: @post do |f| %>
```

### 3.5 Nil-Safety on Current User

```
- [ ] Uses user&.admin? not user.admin? when user can be nil (guest/visitor)
- [ ] Uses user&.role? not user.role?
```

**Examples:**
```ruby
# ❌ NoMethodError for nil visitor
def admin?
  user.admin?
end

# ✅ Safe nil check
def admin?
  user&.admin?
end
```

### 3.6 String Methods

```
- [ ] truncate already appends "..." — don't add manually
- [ ] 5.business_days does not exist in Rails (use 5.days or require a gem)
```

**Examples:**
```ruby
# ❌ Double ellipsis
post.title.truncate(50) + "..."  # → "Very long title that gets cut..." + "..."

# ✅ truncate already adds omission
post.title.truncate(50)          # → "Very long title that gets cut..."

# ❌ business_days not in Rails core
7.business_days.from_now         # ❌ NoMethodError

# ✅ Use plain days or business_time gem
7.days.from_now                  # ✅
```

### 3.7 Mailer Test Helpers

```
- [ ] Uses have_enqueued_mail(Mailer, :method) not have_enqueued_job(ActionMailer::MailDeliveryJob)
- [ ] Uses change { ActionMailer::Base.deliveries.count }.by(1) for deliver_now
```

**Examples:**
```ruby
# ❌ Brittle mailer test
expect { call }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
  .with("UserMailer", "welcome_email", ...)

# ✅ Semantic mailer test
expect { call }.to have_enqueued_mail(UserMailer, :welcome_email)
```

### 3.8 Turbo Stream Mixing

```
- [ ] Does NOT render turbo_stream tags inside regular HTML partials
- [ ] turbo_stream.append/prepend/replace only inside format.turbo_stream blocks
```

**Examples:**
```ruby
# ❌ turbo_stream in partial served as HTML (stream tags silently ignored)
# _pagination.html.erb:
<%= turbo_stream.append "posts", partial: "post", locals: { post: @post } %>

# ✅ format-conditional stream response
def create
  respond_to do |format|
    format.turbo_stream { render turbo_stream: turbo_stream.append("posts", ...) }
    format.html { redirect_to posts_path }
  end
end
```

### 3.9 Migration Safety

```
- [ ] rename_column uses multi-step (add + backfill + drop), NOT inline rename
- [ ] Concurrent index creation uses disable_ddl_transaction! + algorithm: :concurrently
```

**Examples:**
```ruby
# ❌ Dangerous inline rename (breaks zero-downtime deploys)
rename_column :users, :name, :full_name

# ✅ Zero-downtime: add new + backfill + drop old in separate migrations
add_column :users, :full_name, :string
User.update_all("full_name = name")
remove_column :users, :name

# ❌ Missing concurrency for index on large table
add_index :orders, :user_id

# ✅ Concurrent non-blocking index
disable_ddl_transaction!
add_index :orders, :user_id, algorithm: :concurrently
```

### 3.10 ViewComponent XSS Risk

```
- [ ] Does NOT use .map { "#{k}='#{v}'" }.join.html_safe (XSS + broken for nested hashes)
- [ ] Uses tag.attributes(html_attrs).deep_merge(...) pattern instead
```

**Examples:**
```ruby
# ❌ XSS risk + broken for nested hashes
def html_attributes
  @attrs.map { |k, v| "#{k}='#{v}'" }.join(" ").html_safe
end

# ✅ Rails-safe attribute merging
def html_attributes
  { class: "card" }.deep_merge(@html_attributes)
end
```

---

## Step 4: Rails Conventions Checklist

```
- [ ] Namespaced classes use module prefix (module Posts; class CreateService)
- [ ] Service objects include Dry::Monads[:result] not custom Result structs
- [ ] Query objects use method chaining with .then { |rel| filter(rel, param) }
- [ ] Policies use ApplicationPolicy base class
- [ ] ViewComponents inherit from ViewComponent::Base
- [ ] Jobs inherit from ApplicationJob
- [ ] Mailers inherit from ApplicationMailer
- [ ] Specs use FactoryBot (create/build) not fixtures
- [ ] Specs use let/let! not instance variables in before blocks
```

---

## Step 5: Documentation Quality Checklist

```
- [ ] Has "Related Skills" section listing complementary skills
- [ ] Has "When to Use X vs Y" decision guide (table or prose)
- [ ] Examples have both ❌ wrong and ✅ correct patterns
- [ ] Code examples are complete enough to be copy-paste useful
- [ ] No broken cross-references or dead links to templates/references
```

**Related Skills section template:**
```markdown
## Related Skills

| Skill | Use When |
|-------|----------|
| `rails-service-object` | Business logic, multiple models |
| `tdd-cycle` | Writing tests first |
| `rails-architecture` | Overall structure decisions |

**This skill vs Service Object:**
- Use this skill for [specific case]
- Use `rails-service-object` when [other case]
```

---

## Step 6: Generate Findings Report

After running all checklists, output:

```
Skill Audit Report: [skill-name]
================================

Score: X/10

🔴 CRITICAL (must fix — causes bugs or broken behavior)
  - [issue description + line reference + fix]

🟡 WARNING (should fix — bad practices, misleading examples)
  - [issue description + line reference + fix]

🔵 INFO (nice to have — completeness, clarity)
  - [issue description + suggestion]

Summary:
  Critical issues: N
  Warnings: N
  Info: N
  Estimated fix time: [minutes]
```

**Score guide:**
- 9-10: Minor improvements only
- 7-8: 1-3 issues, still usable
- 5-6: Several issues, may mislead users
- < 5: Major issues, needs significant rework

---

## Step 7: Apply Fixes

For each CRITICAL or WARNING issue, propose the exact fix:

```markdown
## Fix 1: [issue title]
**File:** skills/[name]/SKILL.md:L42
**Change:**
- Before: `result.value`
- After:  `result.value!`
**Reason:** dry-monads uses value! (raises if Failure), not value (returns nil)
```

Ask before applying if there are 3+ fixes. Apply one at a time for CRITICAL issues.

---

## Step 8: Verify Fixes

After editing, re-read the changed sections and confirm:
- The fix is syntactically correct Ruby
- The fix doesn't contradict other examples in the same skill
- The fix aligns with the project's established patterns

---

## Common Bugs Quick Reference

Use this as a fast scan during audits:

| Bug Pattern | Correct Pattern | Severity |
|-------------|-----------------|----------|
| `success(x)` | `Success(x)` | 🔴 |
| `failure(x)` | `Failure(x)` | 🔴 |
| `result.value` | `result.value!` | 🔴 |
| `result.error` | `result.failure` | 🔴 |
| `result.data` | `result.value!` | 🔴 |
| `errors.merge!(result.error)` | `errors.add(:base, result.failure)` | 🔴 |
| `after_create_commit :send_email` | explicit in controller | 🔴 |
| `spec/controllers/` | `spec/requests/` | 🟡 |
| `method: :delete` | `data: { turbo_method: :delete }` | 🟡 |
| `data: { confirm: }` | `data: { turbo_confirm: }` | 🟡 |
| `local: true` in form_with | remove it | 🟡 |
| `user.admin?` (nil possible) | `user&.admin?` | 🟡 |
| `.truncate(50) + "..."` | `.truncate(50)` | 🟡 |
| `5.business_days` | `5.days` or explicit gem | 🟡 |
| `rename_column` inline | multi-step migration | 🟡 |
| `have_enqueued_job(ActionMailer...)` | `have_enqueued_mail(Mailer, :method)` | 🟡 |
| `turbo_stream.*` in HTML partial | inside `format.turbo_stream` block | 🟡 |
| `.map {...}.html_safe` in component | `deep_merge` + `tag.attributes` | 🟡 |
| Missing Related Skills | add section | 🔵 |
| Missing ❌/✅ examples | add both patterns | 🔵 |
| No decision guide | add when-to-use table | 🔵 |

---

## Related Skills

| Skill | Use When |
|-------|----------|
| `tdd-cycle` | Verifying code in skills follows TDD patterns |
| `rails-architecture` | Validating structural decisions in skills |
| `rails-service-object` | Auditing service-related skill examples |

**This skill vs manual review:**
- Use `skill-auditor` for systematic, repeatable audits with a consistent checklist
- Use manual review when evaluating overall skill purpose or project fit
