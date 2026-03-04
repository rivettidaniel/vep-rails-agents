# Rails AI Suite - Project Guide for Claude Code

> **Project-specific conventions, rules, and guidelines for working with this Rails agent collection.**

---

## Project Overview

This is the **Rails AI Suite** - a comprehensive collection of specialized AI agents and skills for Rails development. The project itself is a **documentation and agent library**, not a traditional Rails application.

**Purpose:** Provide curated agents and skills that help developers build Rails applications following best practices.

**Structure:**
- `agents/` - 31 specialist agents (TDD, implementation, quality, design patterns)
- `feature_spec_agents/` - 3 feature specification agents
- `commands/` - VEP planning commands (vep-init, vep-feature, vep-wave, vep-state)
- `planning/` - VEP planning file templates (PROJECT, REQUIREMENTS, ROADMAP, STATE, PHASE_PLAN)
- `skills/` - 30 reusable knowledge modules
- `features/` - Feature specification templates

---

## Tech Stack

### Rails Architecture Philosophy

These agents promote a **modern Rails architecture** with:

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Framework** | Rails 7.x - 8.x | Web application framework |
| **Ruby** | 3.3+ | Programming language |
| **Database** | PostgreSQL | Primary database (SQLite for dev/test) |
| **Frontend** | Hotwire (Turbo + Stimulus) | SPA-like experience without heavy JS |
| **Components** | ViewComponent | Reusable, tested UI components |
| **Styling** | Tailwind CSS | Utility-first CSS |
| **Jobs** | Solid Queue | Background job processing |
| **Authorization** | Pundit | Policy-based authorization |
| **Testing** | RSpec + FactoryBot | Test framework + test data |
| **Result Pattern** | dry-monads | Result monad for service objects |

---

## Core Architectural Principles

### 1. Thin Models & Controllers

**Models:**
- Validations and associations only
- Simple instance methods for data manipulation
- No business logic or side effects
- Extract complex logic to Service Objects

**Controllers:**
- RESTful actions (< 10 lines ideal)
- Handle HTTP concerns only
- Authorization on every action
- Side effects explicit after successful save

### 2. Service Objects for Business Logic

Use Service Objects when:
- Operation touches 2+ models
- Complex business logic involved
- Operation could fail in multiple ways

```ruby
# Example: Posts::PublishService
module Posts
  class PublishService < ApplicationService
    def call
      # Returns Success(post) or Failure(error)
      # Uses dry-monads Result pattern
    end
  end
end
```

### 3. No Callback Side Effects ⚠️ **CRITICAL RULE**

**Rule:** NEVER use model callbacks for side effects (emails, notifications, API calls, jobs).

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
    # All side effects explicit in controller
    PostMailer.notify(@post).deliver_later
    SearchIndexJob.perform_later(@post)
    broadcast_to_followers(@post)

    redirect_to @post
  else
    render :new, status: :unprocessable_entity
  end
end
```

**Exception:** Use Event Dispatcher pattern for 3+ side effects:

```ruby
# Controller
if @post.save
  ApplicationEvent.dispatch(:post_created, @post)
  redirect_to @post
end

# Event Handler
class PostCreatedHandler
  def call(post)
    PostMailer.notify(post).deliver_later
    SearchIndexJob.perform_later(post)
    NotificationService.notify_followers(post)
    AnalyticsService.track(:post_created, post)
    CacheService.invalidate_posts
  end
end
```

**Only acceptable callbacks:**
- `before_validation` - Data normalization (strip whitespace, downcase email)
- `before_save` - Setting default values
- `after_initialize` - Setting initial state

### 4. Query Objects for Complex Queries

Extract complex queries to Query Objects to prevent N+1 and keep models clean:

```ruby
# app/queries/posts/search_query.rb
module Posts
  class SearchQuery
    def call(params)
      Post.all
        .then { |rel| filter_by_status(rel, params[:status]) }
        .then { |rel| search_by_title(rel, params[:q]) }
        .then { |rel| order_by(rel, params[:sort]) }
    end
  end
end
```

### 5. Authorization on Every Action

**Rule:** ALWAYS authorize with Pundit, deny by default.

```ruby
def show
  @post = Post.find(params[:id])
  authorize @post  # REQUIRED!
end

def create
  @post = Post.new(post_params)
  authorize @post  # REQUIRED!

  if @post.save
    redirect_to @post
  end
end
```

### 6. TDD Methodology (RED → GREEN → REFACTOR)

**Always follow TDD:**
1. **RED:** Write failing test first (`@tdd_red_agent`)
2. **GREEN:** Implement minimal code to pass
3. **REFACTOR:** Improve code quality (`@tdd_refactoring_agent`)

```
@tdd_red_agent write failing tests for Post model
@model_agent implement Post model (minimal)
@tdd_refactoring_agent improve Post model structure
@lint_agent fix style issues
```

---

## Agent Usage Guidelines

### When to Use Which Agent

#### For Testing
- `@tdd_red_agent` - Always start here (write failing tests FIRST)
- `@rspec_agent` - Fix/improve existing tests
- `@tdd_refactoring_agent` - Refactor after tests pass

#### For Implementation
- `@model_agent` - Models (thin, validations only)
- `@controller_agent` - Controllers (RESTful, thin)
- `@service_agent` - Business logic (2+ models, complex operations)
- `@query_agent` - Complex database queries
- `@form_agent` - Multi-model forms
- `@presenter_agent` - View formatting logic
- `@policy_agent` - Authorization rules (Pundit)
- `@view_component_agent` - Reusable UI components
- `@job_agent` - Background jobs
- `@mailer_agent` - Email sending
- `@migration_agent` - Database changes
- `@gem_agent` - Gemfile and gem management
- `@implementation_agent` - General implementation tasks

#### For Frontend
- `@turbo_agent` - Turbo Frames/Streams (partial updates, real-time)
- `@stimulus_agent` - JavaScript interactivity
- `@tailwind_agent` - Styling

#### For Quality
- `@review_agent` - Code quality review (SOLID, patterns)
- `@lint_agent` - Style fixes (RuboCop)
- `@security_agent` - Security audit (Brakeman, OWASP)

#### For Design Patterns
- `@builder_agent` - Complex multi-step construction
- `@strategy_agent` - Interchangeable algorithms (payment providers, exporters)
- `@template_method_agent` - Workflows with customizable steps (importers)
- `@state_agent` - State machines with transitions (order status)
- `@chain_of_responsibility_agent` - Request processing pipelines
- `@factory_method_agent` - Polymorphic object creation
- `@command_agent` - Operations with undo/redo

#### For Event Handling
- `@event_dispatcher_agent` - Complex side effects (3+ actions)

#### For Package Management
- `@packwerk_agent` - Package boundaries with Packwerk

#### For VEP Orchestration
- `/vep-init` - Initialize project planning files (once per project)
- `/vep-feature` - Spec feature + generate PHASE_PLAN with wave structure
- `/vep-wave N` - Execute wave N with all parallel agents in ONE message
- `/vep-state` - Save session state, ADRs, and next session context
- `/frame-problem` - Reframe a stakeholder request into real problem + architectural alternatives
- `/refine-specification` - Ask clarifying questions to refine a draft feature spec

#### For Feature Planning
- `@feature_specification_agent` - Write detailed specs
- `@feature_planner_agent` - Break into tasks, recommend agents
- `@feature_reviewer_agent` - Review against spec

---

## Conventions

### File Organization

```
app/
├── controllers/        # Thin controllers (< 10 lines/action)
├── models/             # Thin models (validations only)
├── services/           # Business logic (Posts::PublishService)
├── queries/            # Complex queries (Posts::SearchQuery)
├── forms/              # Multi-model forms (UserRegistrationForm)
├── presenters/         # View logic (PostPresenter)
├── policies/           # Authorization (PostPolicy)
├── components/         # ViewComponents (Post::CardComponent)
├── jobs/               # Background jobs (ProcessPaymentJob)
├── mailers/            # Mailers (PostMailer)
├── events/             # Event handlers (PostCreatedHandler)
└── javascript/
    └── controllers/    # Stimulus controllers (toggle_controller.js)
```

### Naming Conventions

**Service Objects:**
```
module Posts
  class PublishService < ApplicationService
  class UnpublishService < ApplicationService
  class CreateService < ApplicationService
end
```

**Query Objects:**
```
module Posts
  class SearchQuery
  class PopularQuery
  class ArchivedQuery
end
```

**Presenters:**
```
class PostPresenter < ApplicationPresenter
class UserPresenter < ApplicationPresenter
```

**Policies:**
```
class PostPolicy < ApplicationPolicy
class CommentPolicy < ApplicationPolicy
```

**ViewComponents:**
```
module Post
  class CardComponent < ViewComponent::Base
  class FormComponent < ViewComponent::Base
end
```

**Event Handlers:**
```
class PostCreatedHandler
class PaymentProcessedHandler
```

### Testing Conventions

**File Structure:**
```
spec/
├── models/             # Model specs
├── services/           # Service object specs
├── queries/            # Query object specs
├── presenters/         # Presenter specs
├── policies/           # Policy specs
├── requests/           # Request specs (controllers)
├── components/         # ViewComponent specs
├── jobs/               # Job specs
├── mailers/            # Mailer specs
└── support/
    ├── factories/      # FactoryBot factories
    └── shared_examples/ # Shared RSpec examples
```

**Test Structure:**
```ruby
require "rails_helper"

RSpec.describe Post, type: :model do
  describe "validations" do
    it { should validate_presence_of(:title) }
    it { should validate_length_of(:title).is_at_most(255) }
  end

  describe "associations" do
    it { should belong_to(:user) }
    it { should have_many(:comments) }
  end

  describe "scopes" do
    describe ".published" do
      it "returns only published posts" do
        # Test implementation
      end
    end
  end

  describe "#publish!" do
    it "sets published_at and published flag" do
      # Test implementation
    end
  end
end
```

---

## Code Quality Standards

### Method Length
- Controller actions: < 10 lines
- Service object methods: < 15 lines
- Model methods: < 10 lines
- Extract to private methods or separate classes if longer

### Class Length
- Controllers: < 100 lines
- Models: < 150 lines
- Service Objects: < 100 lines
- Extract to multiple classes or concerns if longer

### Complexity
- Cyclomatic complexity: < 10
- Nesting: < 3 levels
- Extract to methods if more complex

### SOLID Principles
- **Single Responsibility:** One class, one reason to change
- **Open/Closed:** Open for extension, closed for modification
- **Liskov Substitution:** Subtypes must be substitutable
- **Interface Segregation:** Many specific interfaces > one general
- **Dependency Inversion:** Depend on abstractions, not concretions

---

## Security Rules

### Never Expose
- Credentials (`.env`, `config/master.key`)
- API keys or tokens
- Database passwords
- Session secrets
- Private keys (`.pem`, `.key`)

### Always
- Use strong parameters in controllers
- Authorize every action with Pundit
- Sanitize user input
- Escape HTML output
- Use parameterized SQL queries (prevent SQL injection)
- Validate file uploads
- Rate limit public endpoints
- Enable CSRF protection

### Tools
- **Brakeman** - Rails security scanner
- **Bundler-audit** - Gem vulnerabilities
- **RuboCop** - Code style and security
- **Pundit** - Authorization

---

## Development Workflow

### Feature Development Flow

```
1. Plan Feature (VEP)
   /vep-feature               # spec + review + generate PHASE_PLAN

2. RED Phase — Wave 1
   /vep-wave 1                # @tdd_red_agent — all failing tests in parallel

3. GREEN Phase — Waves 2-4
   /vep-wave 2                # @migration_agent + @model_agent (parallel)
   /vep-wave 3                # @service_agent + @policy_agent (parallel)
   /vep-wave 4                # @controller_agent + @view_component_agent + @turbo_agent (parallel)

4. REFACTOR Phase — Wave 5
   /vep-wave 5                # @tdd_refactoring_agent + @lint_agent

5. QA Review — Wave 6
   /vep-wave 6                # @review_agent + @security_agent + @rspec_agent (parallel)

6. Fix Issues
   [use specialist agents to fix blocking issues]

7. Save State + Deploy
   /vep-state                 # record ADRs and final decisions
   # Deploy after all QA checks pass
```

---

## Resources

### Documentation
- [CLAUDE_CODE_PROJECT_GUIDE.md](CLAUDE_CODE_PROJECT_GUIDE.md) - How to use agents and skills
- [README.md](README.md) - Project overview

### Agent Files
- [agents/](agents/) - 31 specialist agents
- [feature_spec_agents/](feature_spec_agents/) - 3 feature spec agents

### VEP Planning
- [commands/](commands/) - VEP commands (vep-init, vep-feature, vep-wave, vep-state)
- [planning/](planning/) - Planning file templates (PROJECT, REQUIREMENTS, ROADMAP, STATE, PHASE_PLAN)

### Skills
- [skills/](skills/) - 30 skills library

### Templates
- [features/FEATURE_TEMPLATE.md](features/FEATURE_TEMPLATE.md) - Feature specification template
- [CLAUDE_CODE_SETUP_TEMPLATE.md](CLAUDE_CODE_SETUP_TEMPLATE.md) - General Rails setup

---

## Quick Commands

### For Claude Code Users

Reference agents with `@agent_name`:

```
@tdd_red_agent write tests for User authentication
@model_agent create User model
@service_agent create Authentication::SignInService
@controller_agent create SessionsController
@policy_agent create SessionPolicy
@review_agent review the authentication implementation
```

### For Complex Features

Use VEP commands:

```
/vep-feature                 # spec "blog feature" → generates PHASE_PLAN

/vep-wave 1                  # RED: @tdd_red_agent (all tests in parallel)
/vep-wave 2                  # @migration_agent + @model_agent (parallel)
/vep-wave 3                  # @service_agent + @policy_agent (parallel)
/vep-wave 4                  # @controller_agent + @view_component_agent + @turbo_agent (parallel)
/vep-wave 5                  # @tdd_refactoring_agent + @lint_agent
/vep-wave 6                  # QA: @review_agent + @security_agent + @rspec_agent (parallel)

/vep-state                   # save session state
```

---

## Remember

✅ **Always do:**
- Start with tests (TDD)
- Keep controllers thin (< 10 lines/action)
- Keep models thin (validations only)
- Extract business logic to Service Objects
- Handle side effects in controllers (NOT callbacks)
- Authorize every action
- Follow SOLID principles

❌ **Never do:**
- Skip tests
- Put business logic in models or controllers
- Use model callbacks for side effects
- Skip authorization checks
- Commit secrets
- Deploy without running Wave 6 (QA)

---

**Rails AI Suite** - Building better Rails apps with AI agents 🚀

---

## VEP Planning Commands

The **VEP (Venezuelan Execution Protocol)** system adds project-level planning and session state management on top of the agent library. It prevents context rot across long multi-session projects by externalizing decisions, blockers, and progress into persistent `planning/*.md` files.

### Commands (Claude Code slash commands)

| Command | File | Purpose |
|---------|------|---------|
| `/vep-init` | `commands/vep-init.md` | Initialize all planning files for a new project |
| `/vep-feature` | `commands/vep-feature.md` | Spec a feature — calls spec+reviewer agents, generates PHASE_PLAN with agents+skills per wave |
| `/vep-wave` | `commands/vep-wave.md` | Execute one wave of parallel tasks |
| `/vep-state` | `commands/vep-state.md` | Update STATE.md at the end of a session |
| `/frame-problem` | `commands/frame-problem.md` | Challenge a stakeholder request — reframe the real problem, propose architectural alternatives |
| `/refine-specification` | `commands/refine-specification.md` | Ask clarifying questions to refine a draft feature spec before planning |

### Planning File Templates (in `planning/`)

| Template | Purpose |
|----------|---------|
| `planning/PROJECT.md` | Project vision, scope (in/out), tech stack, success metrics |
| `planning/REQUIREMENTS.md` | P0/P1/P2 requirements with acceptance criteria and estimates |
| `planning/ROADMAP.md` | Phase-by-phase plan with branch names and PR checklists |
| `planning/STATE.md` | Architecture Decision Records (ADRs), blockers, session log |
| `planning/PHASE_PLAN.md` | XML-structured atomic tasks with wave groupings and verifications |
| `planning/features/[name].md` | Feature specification output from `/vep-feature` (via @feature_specification_agent) |

### How It Works

1. Run `/vep-init` once to generate filled-in planning files for your project
2. Run `/vep-feature` to spec a feature — calls `@feature_specification_agent` + `@feature_reviewer_agent`, then generates `planning/PHASE_PLAN.md` with agent + skills per wave
3. At the start of every session, paste the "Context for Next Session" block from `STATE.md`
4. Run `/vep-wave N` to execute Wave N - all parallel tasks dispatched in ONE message
5. Each task maps to one agent, one commit, one verification command
6. Run `/vep-state` at session end to record ADRs, blockers, and next action

### VEP Workflow

```
/vep-init
  └─> planning/PROJECT.md (vision + scope)
  └─> planning/REQUIREMENTS.md (P0/P1/P2)
  └─> planning/ROADMAP.md (phases + PRs)
  └─> planning/STATE.md (decisions + blockers)
  └─> planning/PHASE_PLAN.md (wave tasks XML)

/vep-feature
  └─> @feature_specification_agent writes planning/features/[name].md
  └─> @feature_reviewer_agent verifies spec completeness
  └─> PHASE_PLAN.md updated with wave structure (agent + skills per task)

Session start: paste STATE.md "Context for Next Session"

/vep-wave 1  →  dispatch all Wave 1 agents in parallel
/vep-wave 2  →  dispatch all Wave 2 agents in parallel (after Wave 1 verified)
/vep-wave 3  →  dispatch QA agents in parallel

/vep-state   →  record decisions, update session log, generate next context
```

### Integration with Existing Agents

VEP orchestrates the same specialist agents already in this library:

```
Wave 1 (RED):  @tdd_red_agent (all models in parallel)
Wave 2 (GREEN): @migration_agent + @model_agent (parallel per model)
Wave 3 (REFACTOR): @tdd_refactoring_agent (parallel per concern)
Wave 4 (QA): @lint_agent + @security_agent + @review_agent (parallel)
```

### Key Principles

- **One task = one agent call = one atomic commit** - granular, recoverable
- **Wave 1 is always RED** - failing tests written before any implementation
- **Never skip verification** - each task's `<verification>` command must pass before next wave
- **STATE.md is the source of truth** - decisions and blockers live here, not in chat history
- **Max 10 tasks per phase** - keeps phases focused and completable

### Related Documentation

- `features/README.md` - How VEP relates to feature templates
- `planning/PHASE_PLAN.md` - Full XML task format reference
- `commands/vep-init.md` - Detailed init steps and validation checklist
