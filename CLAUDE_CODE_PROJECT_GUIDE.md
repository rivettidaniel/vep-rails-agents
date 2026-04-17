# Claude Code Guide for Rails AI Suite

> **Project-specific guide for using this Rails AI agent collection with Claude Code.**
>
> For general Rails setup templates, see [CLAUDE_CODE_SETUP_TEMPLATE.md](CLAUDE_CODE_SETUP_TEMPLATE.md).

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Available Agents (33 total)](#available-agents-33-total)
3. [Available Skills (30 total)](#available-skills-30-total)
4. [VEP Planning Commands](#vep-planning-commands)
5. [Workflow Examples](#workflow-examples)
6. [Best Practices](#best-practices)

---

## Quick Start

### How to Use Agents

Reference agents in your prompts with `@agent_name`:

```
@model_agent create a User model with email, password_digest, and role
```

### How to Use Skills

Skills provide context automatically when agents need them. You can also reference them directly:

```
Show me examples from the rails-service-object skill
```

### Multi-Agent Workflows

Combine multiple agents for complex tasks:

```
@feature_planner_agent analyze this feature
Then use recommended agents to implement
@senior_qa_reviewer review the implementation
```

---

## Available Agents (34 total)

### 1. Specialist Agents (31)

#### Testing & TDD (3 agents)

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| `@tdd_red_agent` | Write failing tests FIRST | Start of every feature (RED phase) |
| `@rspec_agent` | RSpec expert for all test types | Writing/fixing tests, test coverage |
| `@tdd_refactoring_agent` | Refactor while keeping tests green | After tests pass (REFACTOR phase) |

**Example:**
```
@tdd_red_agent write failing tests for Post model with title, body, published_at
@model_agent implement the Post model
@tdd_refactoring_agent improve the Post model structure
```

---

#### Implementation (11 agents)

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| `@model_agent` | Thin ActiveRecord models | Creating/modifying models |
| `@controller_agent` | Thin RESTful controllers | Creating/modifying controllers |
| `@service_agent` | Business logic service objects | Complex operations (2+ models) |
| `@query_agent` | Complex query objects | Complex database queries |
| `@form_agent` | Multi-model form objects | Forms spanning multiple models |
| `@presenter_agent` | View logic presenters | View formatting logic |
| `@policy_agent` | Pundit authorization | Authorization rules |
| `@view_component_agent` | ViewComponent + Hotwire | Reusable UI components |
| `@job_agent` | Background jobs (Solid Queue) | Async work |
| `@mailer_agent` | Mailers with previews | Email sending |
| `@migration_agent` | Safe migrations | Database schema changes |
| `@gem_agent` | Gemfile and dependencies | Managing gems and versions |
| `@implementation_agent` | General implementation | General coding tasks |

**Example:**
```
@migration_agent create posts table with title:string, body:text, published_at:datetime
@model_agent create Post model
@service_agent create Posts::PublishService to publish posts and notify followers
@controller_agent create PostsController with CRUD actions
@policy_agent create PostPolicy for post authorization
```

---

#### Frontend (3 agents)

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| `@stimulus_agent` | Stimulus controllers | JavaScript interactivity |
| `@turbo_agent` | Turbo Frames/Streams | Real-time updates, partial updates |
| `@tailwind_agent` | Tailwind CSS styling | Styling components |

**Example:**
```
@stimulus_agent create a toggle controller for collapsible sections
@turbo_agent add real-time updates when new posts are created
@tailwind_agent style the post card component
```

---

#### Quality (3 agents)

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| `@review_agent` | Code quality analysis | Before merging, checking SOLID principles |
| `@lint_agent` | Style fixes (no logic changes) | Fixing RuboCop violations |
| `@security_agent` | Security audits (Brakeman) | Pre-deployment, security review |

**Example:**
```
@review_agent check the PostsController for code quality issues
@lint_agent fix style violations in app/models/post.rb
@security_agent audit the authentication system
```

---

#### Design Patterns (7 agents)

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| `@builder_agent` | Builder Pattern | Complex multi-step object construction |
| `@strategy_agent` | Strategy Pattern | Interchangeable algorithms (payment methods) |
| `@template_method_agent` | Template Method Pattern | Workflows with customizable steps (importers) |
| `@state_agent` | State Pattern | State machines with transitions (order status) |
| `@chain_of_responsibility_agent` | Chain of Responsibility | Request processing pipelines (authorization) |
| `@factory_method_agent` | Factory Method Pattern | Polymorphic object creation (notifications) |
| `@command_agent` | Command Pattern | Operations with undo/redo, command queues |

**Example:**
```
@strategy_agent implement payment processing with multiple providers
@state_agent create an order state machine with transitions
@builder_agent create a complex report builder
```

---

#### Event Handling & Package Management (2 agents)

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| `@event_dispatcher_agent` | Event dispatcher for 3+ side effects | Complex side effects after model saves |
| `@packwerk_agent` | Package boundary management | Enforcing package boundaries |

**Example:**
```
@event_dispatcher_agent set up event handling for user registration
@packwerk_agent configure Packwerk for billing package
```

---

### 2. VEP Planning Commands

VEP (Venezuelan Execution Protocol) replaces workflow agents with a state-persistent planning system that prevents context rot across multi-session projects.

| Command | Purpose |
|---------|---------|
| `/vep-init` | Initialize project planning files (once per project) |
| `/vep-feature` | Spec a feature — calls spec + reviewer agents, generates PHASE_PLAN with agents+skills per wave |
| `/vep-wave N` | Execute wave N — dispatch all parallel agents in ONE message |
| `/vep-state` | Save session state (ADRs, blockers, next action) |

**How It Works:**

1. `/vep-init` creates `planning/` files (PROJECT, REQUIREMENTS, ROADMAP, STATE, PHASE_PLAN)
2. `/vep-feature` calls `@feature_specification_agent` + `@feature_reviewer_agent`, generates PHASE_PLAN.md with wave structure including agent + skills per task
3. `/vep-wave N` reads PHASE_PLAN.md, dispatches ALL parallel agents in a single message, verifies, commits atomically
4. `/vep-state` records ADRs, updates blockers, generates "Context for Next Session" block

**Wave Structure:**

| Wave | Phase | Agents | Parallel |
|------|-------|--------|---------|
| 1 | RED | `@tdd_red_agent` (tdd-cycle) | Yes |
| 2 | Foundation | `@migration_agent`, `@model_agent` | Yes |
| 3 | Business Logic | `@service_agent`, `@policy_agent`, etc. | Yes |
| 4 | Interface | `@controller_agent`, `@view_component_agent`, etc. | Yes |
| 5 | Refactor | `@tdd_refactoring_agent`, `@lint_agent` | Sequential |
| 6 | QA | `@review_agent`, `@security_agent`, `@rspec_agent` | Yes |

**Example:**
```
/vep-init                    # Setup planning (once)
/vep-feature                 # Spec "user subscriptions" feature
/vep-wave 1                  # Write failing tests
/vep-wave 2                  # Create migrations + models
/vep-wave 3                  # Create services + policies
/vep-wave 4                  # Create controllers + views
/vep-wave 5                  # Refactor + lint
/vep-wave 6                  # Review + security + coverage
/vep-state                   # Save session state
```

---

### 3. Feature Specification Agents (3)

High-level planning and requirements management.

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| `@feature_specification_agent` | Writes detailed feature specs | Before starting implementation |
| `@feature_reviewer_agent` | Reviews spec for quality and completeness | After spec is written |
| `@feature_planner_agent` | Breaks a reviewed spec into tasks and agent assignments | Standalone workflow (no VEP) |

There are two ways to use these agents depending on whether you use VEP:

**VEP Workflow (recommended) — creates `planning/` files, wave structure, persistent state:**
```
/vep-feature    # calls @feature_specification_agent + @feature_reviewer_agent automatically,
                # then generates planning/PHASE_PLAN.md with agents+skills per wave
/vep-wave 1     # RED: failing tests
/vep-wave 2-4   # GREEN: implementation waves
/vep-wave 5-6   # REFACTOR + QA
```

**Standalone Workflow — quick plan in chat, no planning files created:**
```
@feature_specification_agent write spec for multi-tenant blog with comments
@feature_reviewer_agent verify spec is complete and implementable
@feature_planner_agent create implementation plan from the reviewed spec
# Then call specialist agents manually
```

---

## Available Skills (30 total)

Skills provide deep knowledge modules that agents reference automatically.

### Architecture & Patterns (9 skills)

| Skill | What It Covers |
|-------|----------------|
| `rails-architecture` | Code organization, layered architecture decisions |
| `rails-concern` | Shared behavior with concerns |
| `rails-service-object` | Business logic encapsulation with dry-monads |
| `command-pattern` | Command Pattern with undo/redo, queues |
| `rails-query-object` | Complex database queries |
| `rails-presenter` | View logic separation |
| `rails-controller` | RESTful controller patterns |
| `rails-model-generator` | Model creation with validations |
| `form-object-patterns` | Multi-model forms, wizards |

**When agents use these:**
- `@model_agent` → uses `rails-model-generator`
- `@controller_agent` → uses `rails-controller`
- `@service_agent` → uses `rails-service-object`
- `@query_agent` → uses `rails-query-object`
- `@presenter_agent` → uses `rails-presenter`

### Frontend & Hotwire (2 skills)

| Skill | What It Covers |
|-------|----------------|
| `hotwire-patterns` | Turbo Frames, Turbo Streams, Stimulus integration |
| `viewcomponent-patterns` | Reusable UI components with ViewComponent |

**When agents use these:**
- `@turbo_agent` → uses `hotwire-patterns`
- `@stimulus_agent` → uses `hotwire-patterns`
- `@view_component_agent` → uses `viewcomponent-patterns`

### Authentication & Authorization (2 skills)

| Skill | What It Covers |
|-------|----------------|
| `authentication-flow` | Rails 8 built-in authentication |
| `authorization-pundit` | Pundit policies and permissions |

**When agents use these:**
- `@policy_agent` → uses `authorization-pundit`

### Data & Storage (3 skills)

| Skill | What It Covers |
|-------|----------------|
| `database-migrations` | Safe, reversible migrations |
| `active-storage-setup` | File uploads and attachments |
| `caching-strategies` | Fragment, action, and HTTP caching |

**When agents use these:**
- `@migration_agent` → uses `database-migrations`

### Background Jobs & Real-time (3 skills)

| Skill | What It Covers |
|-------|----------------|
| `solid-queue-setup` | Background job processing |
| `action-cable-patterns` | WebSocket real-time features |
| `action-mailer-patterns` | Transactional emails |

**When agents use these:**
- `@job_agent` → uses `solid-queue-setup`
- `@mailer_agent` → uses `action-mailer-patterns`

### API & Internationalization (2 skills)

| Skill | What It Covers |
|-------|----------------|
| `api-versioning` | Versioned REST APIs |
| `i18n-patterns` | Internationalization and localization |

### Performance & Testing (2 skills)

| Skill | What It Covers |
|-------|----------------|
| `performance-optimization` | N+1 prevention, eager loading |
| `tdd-cycle` | Test-driven development workflow |

**When agents use these:**
- `@tdd_red_agent` → uses `tdd-cycle`
- `@review_agent` → uses `performance-optimization`

### Design Patterns (7 skills)

| Skill | What It Covers |
|-------|----------------|
| `builder-pattern` | Builder Pattern for complex construction |
| `strategy-pattern` | Strategy Pattern with registry |
| `template-method-pattern` | Template Method Pattern for workflows |
| `state-pattern` | State Pattern for state machines |
| `chain-of-responsibility-pattern` | Chain of Responsibility for pipelines |
| `factory-method-pattern` | Factory Method Pattern for creation |
| `packwerk` | Package boundary management |

**When agents use these:**
- `@builder_agent` → uses `builder-pattern`
- `@strategy_agent` → uses `strategy-pattern`
- `@template_method_agent` → uses `template-method-pattern`
- `@state_agent` → uses `state-pattern`
- `@chain_of_responsibility_agent` → uses `chain-of-responsibility-pattern`
- `@factory_method_agent` → uses `factory-method-pattern`
- `@packwerk_agent` → uses `packwerk`

---

## Workflow Examples

### Part A: Direct Implementation (Specialist Agents Only)

**When to use:** Simple, well-understood features that don't require formal planning or research.

**Characteristics:**
- Clear requirements (< 1 day of work)
- No architectural decisions needed
- Direct implementation with specialist agents
- Quick iteration without formal specification

---

#### Example A1: Small Feature (< 1 day)

**Scenario:** Add "like" functionality to posts

```
# 1. Write failing tests
@tdd_red_agent write failing tests for Post#like! method

# 2. Implement model changes
@migration_agent add likes_count to posts table
@model_agent add like! method to Post model

# 3. Implement controller
@controller_agent add like action to PostsController

# 4. Add authorization
@policy_agent update PostPolicy to allow liking published posts

# 5. Add real-time updates
@turbo_agent add Turbo Stream for updating like count

# 6. Refactor
@tdd_refactoring_agent improve code structure

# 7. Review
@review_agent check for issues
@lint_agent fix style violations
```

---

### Part B: Planned Implementation (VEP Commands)

**When to use:** Complex features requiring planning, multi-session work, or coordinated parallel execution.

**Characteristics:**
- Multi-day features (1+ days)
- Need architectural decisions or formal specification
- Benefit from persistent state across sessions
- Require coordinated wave-based implementation and QA

**Tools involved:**
- **VEP Commands:** `/vep-init`, `/vep-feature`, `/vep-wave N`, `/vep-state`
- **Feature Spec Agents:** called automatically by `/vep-feature`
- **Specialist Agents:** dispatched by `/vep-wave N` per the PHASE_PLAN

---

#### Example B1: Medium Feature (1-3 days)

**Scenario:** Multi-tenant blog with comments

```
# Phase 1: Spec + Plan (VEP generates PHASE_PLAN.md)
/vep-feature                 # prompts for "multi-tenant blog with comments"
# Output: features/multi_tenant_blog.md + planning/PHASE_PLAN.md

# Phase 2: Wave Execution (parallel agents per wave)
/vep-wave 1                  # @tdd_red_agent — failing tests for Blog, Post, Comment
/vep-wave 2                  # @migration_agent + @model_agent — tables + models (parallel)
/vep-wave 3                  # @service_agent + @policy_agent — business logic + auth (parallel)
/vep-wave 4                  # @controller_agent + @view_component_agent + @turbo_agent (parallel)
/vep-wave 5                  # @tdd_refactoring_agent + @lint_agent — refactor + style

# Phase 3: QA Wave
/vep-wave 6                  # @review_agent + @security_agent + @rspec_agent (parallel)

# Save state
/vep-state                   # record ADRs, blockers, next session context
```

---

#### Example B2: Complex Feature with Design Pattern (3-5 days)

**Scenario:** Payment processing with multiple providers

```
# Phase 1: Spec + Plan (VEP generates PHASE_PLAN with design pattern wave)
/vep-feature                 # prompts for "payment processing with Strategy Pattern"
# Output: features/payment_processing.md + planning/PHASE_PLAN.md

# Phase 2: Wave Execution
/vep-wave 1                  # @tdd_red_agent — failing tests (all payment scenarios)
/vep-wave 2                  # @migration_agent — payment tables
/vep-wave 3                  # @strategy_agent + @model_agent — strategy pattern + models (parallel)
/vep-wave 4                  # @service_agent — PaymentProcessorService using strategies
/vep-wave 5                  # @controller_agent + @job_agent + @mailer_agent (parallel)
/vep-wave 6                  # @event_dispatcher_agent — payment lifecycle events
/vep-wave 7                  # @tdd_refactoring_agent + @lint_agent — refactor + style

# Phase 3: QA Wave (security focus)
/vep-wave 8                  # @review_agent + @security_agent + @rspec_agent (parallel)

/vep-state                   # save session state
```

---

#### Example B3: Full Development Cycle (Init → Feature → Waves → State)

**Scenario:** Complete workflow from project setup to production-ready feature

```
# STEP 1: Project Setup (once per project)
/vep-init
# Creates: planning/PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, PHASE_PLAN.md

# STEP 2: Feature Specification
/vep-feature                 # Spec "[feature name]"
# Runs: @feature_specification_agent + @feature_reviewer_agent
# Output: planning/features/[feature_name].md + PHASE_PLAN.md with wave structure

# STEP 3: Execute Waves (RED → GREEN → REFACTOR)
/vep-wave 1                  # RED — failing tests (all parallel)
/vep-wave 2                  # Foundation — migrations + models (parallel per model)
/vep-wave 3                  # Business Logic — services + policies (parallel)
/vep-wave 4                  # Interface — controllers + views + components (parallel)
/vep-wave 5                  # REFACTOR — refactoring + lint (sequential)
/vep-wave 6                  # QA — review + security + coverage (parallel)

# STEP 4: Save State (end of session)
/vep-state
# Records: ADRs, blockers, "Context for Next Session" block for STATE.md
```

---

## Best Practices

### 1. Always Start with Tests (TDD)

```
✅ CORRECT:
@tdd_red_agent write failing tests for User authentication
@model_agent implement User model
@service_agent implement Authentication::SignInService

❌ INCORRECT:
@model_agent create User model with authentication
# (No tests written first!)
```

### 2. Use the Right Agent for the Job

```
✅ CORRECT:
@service_agent create complex invoice calculation logic
# (Complex business logic → Service Object)

❌ INCORRECT:
@model_agent add invoice calculation to Invoice model
# (Too much logic in model)
```

### 3. Follow Side Effects Rule

**Rule:** Handle side effects (emails, notifications, API calls) in **controllers**, not model callbacks.

```
✅ CORRECT (Controller):
def create
  @post = Post.new(post_params)

  if @post.save
    # Side effects explicit in controller
    PostMailer.published(@post).deliver_later
    NotificationService.notify_followers(@post)
    SearchIndexJob.perform_later(@post)

    redirect_to @post
  else
    render :new
  end
end

❌ INCORRECT (Model Callback):
class Post < ApplicationRecord
  after_create_commit :send_notifications  # ❌ Hidden side effect!
end
```

**Exception:** Use `@event_dispatcher_agent` for 3+ side effects:

```
✅ CORRECT (Event Dispatcher for 3+ side effects):
def create
  @post = Post.new(post_params)

  if @post.save
    ApplicationEvent.dispatch(:post_created, @post)
    redirect_to @post
  end
end

# Handler in app/events/post_created_handler.rb
class PostCreatedHandler
  def call(post)
    PostMailer.published(post).deliver_later
    NotificationService.notify_followers(post)
    SearchIndexJob.perform_later(post)
    AnalyticsService.track(:post_created, post)
    CacheService.invalidate_posts
  end
end
```

### 4. Use VEP for Orchestration

**For simple features (< 1 day):** Use specialist agents directly (see Example A1)

**For complex features (1+ days):** Use VEP commands for state-persistent wave-based orchestration (see Examples B1-B3)

```
✅ CORRECT (Complex Feature with VEP):
/vep-feature                 # Spec "blog with comments" → generates PHASE_PLAN
/vep-wave 1                  # RED: failing tests (all parallel)
/vep-wave 2                  # Foundation: migrations + models (parallel)
/vep-wave 3                  # Logic: services + policies (parallel)
/vep-wave 4                  # Interface: controllers + views (parallel)
/vep-wave 5                  # Refactor + lint
/vep-wave 6                  # QA: review + security + coverage (parallel)
/vep-state                   # Save session state

❌ INCORRECT (Sequential one-by-one without plan):
@model_agent create Blog model
@model_agent create Post model
@model_agent create Comment model
@controller_agent create BlogsController
@controller_agent create PostsController
@controller_agent create CommentsController
# (No parallelism, no state persistence, no PHASE_PLAN)
```

### 5. Always Review Before Deploying

Use Wave 6 (QA) to run all quality checks in parallel before merging or deploying.

```
✅ CORRECT:
# After implementation waves complete, run QA wave
/vep-wave 6                  # dispatches in parallel:
                             #   @review_agent — SOLID, code quality
                             #   @security_agent — Brakeman, OWASP
                             #   @rspec_agent — coverage, test completeness

# Fix any blocking issues found by QA
[fix issues with specialist agents]

# Re-run QA wave after fixes
/vep-wave 6

# Deploy only after all QA checks pass
/vep-state                   # record approval + final ADRs before merge

❌ INCORRECT:
# Implement feature and deploy immediately without QA wave
```

### 6. Use Design Patterns When Appropriate

**Use `@strategy_agent` for:**
- Multiple payment providers
- Different export formats (PDF, Excel, CSV)
- Various authentication methods

**Use `@state_agent` for:**
- Order status workflows
- Document approval processes
- User onboarding flows

**Use `@builder_agent` for:**
- Complex report generation
- Multi-step form wizards
- Configuration builders

**Use `@template_method_agent` for:**
- Data importers (CSV, JSON, XML)
- Report generators with variants
- Processing pipelines with steps

### 7. Leverage Skills for Context

When asking for examples or patterns:

```
Show me the rails-service-object skill for Result pattern examples

Give me the hotwire-patterns skill for Turbo Stream examples

Show me the strategy-pattern skill for payment processing
```

---

## Tech Stack

This project's agents support:

| Component | Technology |
|-----------|------------|
| **Ruby** | 3.3+ |
| **Rails** | 7.x - 8.x |
| **Database** | PostgreSQL (primary) / SQLite (dev) |
| **Frontend** | Hotwire (Turbo + Stimulus) |
| **Components** | ViewComponent |
| **Styling** | Tailwind CSS |
| **Jobs** | Solid Queue |
| **Authorization** | Pundit |
| **Testing** | RSpec + FactoryBot |
| **Result Pattern** | dry-monads |

---

## Project-Specific Conventions

### No Callback Side Effects

**Rule:** NEVER use `after_create_commit`, `after_save`, `after_commit` for side effects.

```ruby
# ❌ NEVER DO THIS
class Post < ApplicationRecord
  after_create_commit :send_notification
  after_save :update_search_index
  after_commit :broadcast_changes
end

# ✅ DO THIS (in controller)
def create
  @post = Post.new(post_params)

  if @post.save
    PostMailer.notify(@post).deliver_later
    SearchIndexJob.perform_later(@post)
    broadcast_to_followers(@post)

    redirect_to @post
  end
end
```

### Thin Controllers & Models

- Controllers: < 10 lines per action
- Models: Delegate complex logic to Services/Queries
- Extract to Service Objects when touching 2+ models

### Authorization on Every Action

```ruby
def show
  @post = Post.find(params[:id])
  authorize @post  # ALWAYS authorize!
end
```

---

## Additional Resources

- **VEP Planning Files:** [planning/](planning/) — PROJECT, REQUIREMENTS, ROADMAP, STATE, PHASE_PLAN
- **VEP Commands:** [commands/](commands/) — vep-init, vep-feature, vep-wave, vep-state
- **Feature Templates:** [features/FEATURE_TEMPLATE.md](features/FEATURE_TEMPLATE.md)
- **Specialist Agents:** [agents/](agents/)
- **Skills Library:** [skills/](skills/)
- **Setup Guide:** [CLAUDE_CODE_SETUP_TEMPLATE.md](CLAUDE_CODE_SETUP_TEMPLATE.md)

---

## Quick Reference Card

### For Testing
```
@tdd_red_agent → Write failing tests
@rspec_agent → Fix/improve tests
@tdd_refactoring_agent → Refactor code
```

### For Implementation
```
@model_agent → Models
@controller_agent → Controllers
@service_agent → Business logic
@query_agent → Complex queries
@presenter_agent → View logic
@view_component_agent → UI components
```

### For Quality
```
@review_agent → Code review
@lint_agent → Style fixes
@security_agent → Security audit
```

### For Design Patterns
```
@strategy_agent → Interchangeable algorithms
@state_agent → State machines
@builder_agent → Complex construction
@command_agent → Undo/redo operations
```

### For VEP Planning
```
/vep-init      → Initialize project planning files
/vep-feature   → Spec + review + generate PHASE_PLAN
/vep-wave N    → Execute wave N (all parallel agents in ONE message)
/vep-state     → Save session state and ADRs
```

---

**Ready to build with Rails AI Suite!**

Choose the right agent for your task, follow TDD methodology, and use VEP commands to orchestrate complex multi-session features.
