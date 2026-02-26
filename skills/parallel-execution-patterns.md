---
skill: parallel-execution-patterns
description: Comprehensive guide to parallel execution patterns, dependency analysis, and wave-based orchestration for maximizing development speed
---

# Parallel Execution Patterns

## Overview

Parallel execution reduces development time by 40-60% by identifying and executing independent tasks simultaneously.

**Key Principle:** To execute in parallel, call ALL agents in ONE message.

---

## 🤖 Available Agents for Parallel Execution

**Use these specific agents in your parallel execution plans:**

### Data Layer
- `@migration_agent` - Database migrations (safe, reversible)
- `@model_agent` - ActiveRecord models (validations, associations, scopes)

### Business Logic
- `@service_agent` - Service Objects (Dry::Monads Result pattern)
- `@query_agent` - Query Objects (complex database queries)
- `@form_agent` - Form Objects (multi-model forms)
- `@command_agent` - Command Pattern (undo/redo operations)

### Design Patterns
- `@builder_agent` - Builder Pattern (complex object construction)
- `@strategy_agent` - Strategy Pattern (interchangeable algorithms)
- `@template_method_agent` - Template Method (workflow with hooks)
- `@state_agent` - State Pattern (state machines)
- `@chain_of_responsibility_agent` - Chain of Responsibility (pipelines)
- `@factory_method_agent` - Factory Method (polymorphic creation)
- `@event_dispatcher_agent` - Event Dispatcher (3+ side effects)

### Presentation Layer
- `@controller_agent` - Thin RESTful controllers
- `@presenter_agent` - Presenters/Decorators (view logic)
- `@view_component_agent` - ViewComponents (reusable UI)
- `@turbo_agent` - Turbo Streams (real-time updates)
- `@stimulus_agent` - Stimulus controllers (JS interactivity)
- `@tailwind_agent` - Tailwind CSS styling

### Authorization & Background
- `@policy_agent` - Pundit policies (authorization)
- `@job_agent` - Background jobs (async processing)
- `@mailer_agent` - Action Mailers (email templates)

### Testing & Quality
- `@tdd_red_agent` - Write failing tests FIRST (RED phase)
- `@rspec_agent` - RSpec tests (all types)
- `@tdd_refactoring_agent` - Refactor while keeping tests green
- `@lint_agent` - RuboCop style fixes
- `@review_agent` - Code quality review (SOLID, patterns)
- `@security_agent` - Security audit (Brakeman, vulnerabilities)

### Architecture
- `@packwerk_agent` - Package boundaries (modularization)

### Orchestrators (use for complex multi-agent coordination)
- `@senior_developer` - Coordinates multiple agents (TDD workflow)
- `@senior_qa_reviewer` - Coordinates QA review agents

**Total:** 29 specialist agents + 2 orchestrators

---

## Core Concepts

### The Parallelism Rule

❌ **Sequential (Slow):**
```
Message 1: Agent A
[wait]
Message 2: Agent B
[wait]
Message 3: Agent C
```
Time: A + B + C

✅ **Parallel (Fast):**
```
One Message:
1. Agent A
2. Agent B
3. Agent C
```
Time: max(A, B, C)

---

## Dependency Analysis

### Types of Dependencies

1. **Data Dependency:** Task B needs output from Task A
   - Example: Model needs migration to run first
   - Solution: Sequential execution (A → B)

2. **Logical Dependency:** Task B logically follows Task A
   - Example: Tests come after implementation
   - Solution: Sequential execution (A → B)

3. **Resource Dependency:** Tasks compete for same resource
   - Example: Two migrations modifying same table
   - Solution: Sequential execution

4. **No Dependency:** Tasks are completely independent
   - Example: Creating different models
   - Solution: **Parallel execution** ⚡

### Dependency Analysis Template

```markdown
## Task Dependencies

| Task | Description | Requires | Blocks | Independent With | Time |
|------|-------------|----------|--------|------------------|------|
| A | Create User migration | None | B | C, D | 30m |
| B | Create User model | A | E | C, D | 1h |
| C | Create Product migration | None | D | A, B | 30m |
| D | Create Product model | C | E | A, B | 1h |
| E | Create UserService | B, D | None | None | 2h |

## Wave Grouping

**Wave 1 (Parallel - 30m):**
- Task A (User migration) ↘
- Task C (Product migration) → Execute simultaneously
Duration: max(30m, 30m) = 30m

**Wave 2 (Parallel - 1h):**
- Task B (User model) ↘
- Task D (Product model) → Execute simultaneously
Duration: max(1h, 1h) = 1h

**Wave 3 (Sequential - 2h):**
- Task E (UserService)
Duration: 2h

**Time Comparison:**
- Sequential: 30m + 1h + 30m + 1h + 2h = 5h
- Parallel: 30m + 1h + 2h = 3.5h
- **Savings: 30%**
```

---

## Pattern Library

### Pattern 1: Database Layer Parallelism

**Scenario:** Creating multiple independent tables

```ruby
# Independent migrations can run in parallel
Execute in parallel:

1. @migration_agent - CreateUsers
   - id, email, password_digest
   - timestamps

2. @migration_agent - CreateProducts
   - id, name, price_cents
   - timestamps

3. @migration_agent - CreateCategories
   - id, name, slug
   - timestamps

All tables are independent, execute simultaneously.
```

**When to Use:** Tables with no foreign keys between them

**Time Savings:** 3 tasks × 30m = 1.5h → 30m parallel = **67% faster**

---

### Pattern 2: Model Layer Parallelism

**Scenario:** Creating models after migrations are complete

```ruby
# After migrations are done, create models in parallel
Execute in parallel:

1. @model_agent - User model:
   - has_secure_password
   - validates :email, presence: true
   - has_many :orders

2. @model_agent - Product model:
   - validates :name, presence: true
   - monetize :price_cents
   - belongs_to :category

3. @model_agent - Category model:
   - validates :name, presence: true
   - has_many :products
   - friendly_id :name

All models are independent, execute simultaneously.
```

**When to Use:** Models that don't call each other's methods

**Time Savings:** 3 tasks × 1h = 3h → 1h parallel = **67% faster**

---

### Pattern 3: Service Layer Parallelism

**Scenario:** Creating services that don't call each other

```ruby
# Independent services (no cross-calls)
Execute in parallel:

1. @service_agent - Users::CreateService
   - Validates user data
   - Creates user
   - Sends welcome email

2. @service_agent - Products::PublishService
   - Validates product data
   - Publishes product
   - Notifies admin

3. @service_agent - Orders::CalculateShippingService
   - Calculates shipping cost
   - Returns Money object

All services are independent, execute simultaneously.
```

**When to Use:** Services in different domains

**Time Savings:** 3 tasks × 2h = 6h → 2h parallel = **67% faster**

⚠️ **Warning:** If UserService calls ProductService, they must be sequential.

---

### Pattern 4: Controller Layer Parallelism

**Scenario:** Creating controllers for different resources

```ruby
# Independent controllers
Execute in parallel:

1. @controller_agent - UsersController
   - CRUD actions
   - Strong parameters
   - Authorization

2. @controller_agent - ProductsController
   - CRUD actions
   - Strong parameters
   - Authorization

3. @controller_agent - OrdersController
   - CRUD actions
   - Strong parameters
   - Authorization

All controllers are independent, execute simultaneously.
```

**When to Use:** RESTful controllers for different resources

**Time Savings:** 3 tasks × 1.5h = 4.5h → 1.5h parallel = **67% faster**

---

### Pattern 5: View Layer Parallelism

**Scenario:** Creating ViewComponents

```ruby
# Independent UI components
Execute in parallel:

1. @view_component_agent - ButtonComponent
   - Variants: primary, secondary, outline
   - Sizes: small, medium, large
   - Tailwind styling

2. @view_component_agent - CardComponent
   - Header, body, footer slots
   - Shadow variants
   - Responsive design

3. @view_component_agent - ModalComponent
   - Open/close functionality
   - Backdrop
   - Stimulus controller

4. @view_component_agent - AlertComponent
   - Types: success, error, warning, info
   - Dismissible option

All components are independent, execute simultaneously.
```

**When to Use:** Components that don't nest or reference each other

**Time Savings:** 4 tasks × 1h = 4h → 1h parallel = **75% faster**

---

### Pattern 6: Test Layer Parallelism

**Scenario:** Writing tests for different files

```ruby
# Independent test files
Execute in parallel:

1. @tdd_red_agent - User model specs:
   - Validation tests
   - Association tests
   - Method tests

2. @tdd_red_agent - Product model specs:
   - Validation tests
   - Association tests
   - Scope tests

3. @tdd_red_agent - Order model specs:
   - Validation tests
   - Association tests
   - State machine tests

4. @tdd_red_agent - UserService specs:
   - Success cases
   - Failure cases
   - Edge cases

All test files are independent, execute simultaneously.
```

**When to Use:** Always (tests are inherently parallelizable)

**Time Savings:** 4 tasks × 45m = 3h → 45m parallel = **75% faster**

---

### Pattern 7: QA Review Parallelism

**Scenario:** Comprehensive code review

```ruby
@senior_qa_reviewer

Coordinate QA review in PARALLEL:

1. @security_agent - Security audit:
   - Brakeman scan
   - SQL injection check
   - XSS vulnerability check
   - CSRF protection
   - Authorization checks

2. @review_agent - Code quality:
   - SOLID principles
   - Design patterns
   - DRY violations
   - Code complexity

3. @lint_agent - Style check:
   - Rubocop offenses
   - Naming conventions
   - Line length
   - Method complexity

4. @rspec_agent - Test coverage:
   - Coverage percentage
   - Missing specs
   - Test quality

All reviews are independent, execute simultaneously.
Consolidate findings into single report.
```

**When to Use:** Before merging any PR

**Time Savings:** 4 tasks × 30m = 2h → 30m parallel = **75% faster**

---

### Pattern 8: Multi-Wave Feature Implementation

**Scenario:** Implementing complete feature with dependencies

```ruby
# User Authentication Feature

WAVE 1 - Foundation (Parallel - 1h):
Execute simultaneously:
1. @migration_agent - AddAuthToUsers (password_digest, etc.)
2. @migration_agent - CreateSessions
3. @gem_agent - Add bcrypt to Gemfile

WAVE 2 - Models (Parallel - 1h):
Execute simultaneously (after Wave 1):
1. @model_agent - User model (has_secure_password)
2. @model_agent - Session model
3. @policy_agent - UserPolicy

WAVE 3 - Services (Sequential - 2h):
Execute after Wave 2:
1. @service_agent - Auth::LoginService (needs User model)

WAVE 4 - Controllers (Parallel - 1.5h):
Execute simultaneously (after Wave 3):
1. @controller_agent - SessionsController
2. @controller_agent - UsersController

WAVE 5 - Views (Parallel - 2h):
Execute simultaneously (after Wave 4):
1. @view_component_agent - LoginFormComponent
2. @view_component_agent - RegistrationFormComponent
3. @stimulus_agent - form-validation-controller

WAVE 6 - Tests (Parallel - 2h):
Execute simultaneously (after implementation):
1. @tdd_red_agent - All model specs
2. @tdd_red_agent - All service specs
3. @tdd_red_agent - All controller specs
4. @tdd_red_agent - All component specs

Time Comparison:
- Sequential: 1h + 1h + 2h + 1.5h + 2h + 2h = 9.5h
- Parallel: 1h + 1h + 2h + 1.5h + 2h + 2h = 9.5h
  BUT within waves: 9.5h → ~6h with internal parallelism
- **Savings: 37%**
```

---

## Decision Tree: Parallel or Sequential?

```
                    START
                      ↓
          ┌───────────────────────┐
          │ Does Task B need      │
          │ output from Task A?   │
          └───────────┬───────────┘
                      |
        ┌─────────────┴─────────────┐
        │                           │
       YES                         NO
        │                           │
        ↓                           ↓
   SEQUENTIAL                  ┌─────────────────────┐
   A → B                        │ Do they modify      │
                                │ same code/file?     │
                                └──────────┬──────────┘
                                           |
                             ┌─────────────┴─────────────┐
                             │                           │
                            YES                         NO
                             │                           │
                             ↓                           ↓
                        SEQUENTIAL                   PARALLEL
                        A → B                        A ║ B
                                                     (simultaneously)
```

---

## Time Calculation Formulas

### Sequential Time
```
T_sequential = T₁ + T₂ + T₃ + ... + Tₙ
```

Example: 1h + 2h + 1.5h + 3h = 7.5h

### Parallel Time (Single Wave)
```
T_parallel = max(T₁, T₂, T₃, ..., Tₙ)
```

Example: max(1h, 2h, 1.5h, 3h) = 3h

### Multi-Wave Parallel Time
```
T_total = T_wave1 + T_wave2 + ... + T_waveN

where T_waveN = max(tasks in waveN)
```

Example:
- Wave 1: max(1h, 1h, 1h) = 1h
- Wave 2: max(2h, 2h) = 2h
- Wave 3: 3h (single task)
- Total: 1h + 2h + 3h = 6h

### Savings Percentage
```
Savings = ((T_sequential - T_parallel) / T_sequential) × 100%
```

Example:
```
Sequential: 12h
Parallel: 7h
Savings: ((12 - 7) / 12) × 100% = 41.67%
```

---

## Common Dependency Patterns

### Pattern: Parent → Child (Sequential)

```
Migration: CreateUsers
         ↓
Migration: CreateProducts (has user_id foreign key)
```

**Must be sequential** because products table needs users table to exist for foreign key.

### Pattern: Independent Resources (Parallel)

```
Migration: CreateUsers  ↘
Migration: CreateProducts → All parallel
Migration: CreateCategories ↗
```

**Can be parallel** because no foreign keys between them.

### Pattern: Base → Extension (Sequential)

```
Model: User (base)
         ↓
Concern: Authenticatable (uses User methods)
```

**Must be sequential** because concern calls methods from User.

### Pattern: Siblings (Parallel)

```
Model: User     ↘
Model: Product  → All parallel (independent siblings)
Model: Category ↗
```

**Can be parallel** because they don't reference each other.

---

## Wave Grouping Strategies

### Strategy 1: By Layer

Group tasks by architectural layer:

```
WAVE 1: Data Layer (migrations)
WAVE 2: Model Layer (models, concerns)
WAVE 3: Logic Layer (services, queries)
WAVE 4: Presentation Layer (controllers, views)
WAVE 5: Async Layer (jobs, mailers)
```

**Pros:**
- Clear separation
- Easy to understand
- Natural dependencies

**Cons:**
- May not maximize parallelism within layers

### Strategy 2: By Feature Slice

Group by vertical feature slices:

```
WAVE 1: User Feature (migration → model → controller → view)
WAVE 2: Product Feature (migration → model → controller → view)
WAVE 3: Order Feature (migration → model → controller → view)
```

**Pros:**
- Features are complete units
- Can deploy incrementally
- Clear feature boundaries

**Cons:**
- Less parallel than layer approach

### Strategy 3: Hybrid (Recommended)

Combine both approaches:

```
WAVE 1: All Migrations (parallel within wave)
├─ User migration
├─ Product migration
└─ Order migration

WAVE 2: All Models (parallel within wave)
├─ User model
├─ Product model
└─ Order model

WAVE 3: Services by dependency
├─ ProductService (no deps)
└─ OrderService (needs ProductService) → Sequential

WAVE 4: All Controllers (parallel)
├─ UsersController
├─ ProductsController
└─ OrdersController
```

**Pros:**
- Maximizes parallelism
- Respects dependencies
- Best time savings

**Cons:**
- Requires careful dependency analysis

---

## Verification Patterns

### After Each Wave

```bash
# Verify all agents completed
git status  # Should show new files

# Verify tests pass
bundle exec rspec

# Verify style
bundle exec rubocop

# Verify security
bundle exec brakeman
```

### Between Waves

```bash
# Ensure Wave 1 complete before Wave 2
git log --oneline -5  # Check commits

# Ensure database up to date
rails db:migrate:status

# Ensure dependencies installed
bundle list | grep [gem-name]
```

---

## Anti-Patterns

### Anti-Pattern 1: Premature Parallelization

**Problem:** Forcing parallelism on dependent tasks

```ruby
❌ WRONG:
Execute in parallel:
1. @migration_agent - CreateUsers
2. @model_agent - User model

Problem: Model tries to load before migration runs
```

**Solution:** Analyze dependencies first
```ruby
✅ CORRECT:
WAVE 1: @migration_agent - CreateUsers
WAVE 2: @model_agent - User model
```

### Anti-Pattern 2: False Independence

**Problem:** Assuming tasks are independent when they're not

```ruby
❌ WRONG:
Execute in parallel:
1. @service_agent - OrderService (calls ProductService.find_available)
2. @service_agent - ProductService

Problem: OrderService depends on ProductService
```

**Solution:** Check for cross-references
```ruby
✅ CORRECT:
WAVE 1: @service_agent - ProductService
WAVE 2: @service_agent - OrderService
```

### Anti-Pattern 3: Over-Sequencing

**Problem:** Running independent tasks sequentially

```ruby
❌ WRONG:
Step 1: Create User model
Step 2: Create Product model
Step 3: Create Category model

Problem: These are independent, wasting time
```

**Solution:** Group independent tasks
```ruby
✅ CORRECT:
Execute in parallel:
1. @model_agent - User
2. @model_agent - Product
3. @model_agent - Category
```

---

## Templates

### Template 1: Single Wave Prompt

```
Execute in parallel:

1. @[agent_name] - [Task 1]:
   - [Specification line 1]
   - [Specification line 2]
   - [Specification line 3]

2. @[agent_name] - [Task 2]:
   - [Specification line 1]
   - [Specification line 2]
   - [Specification line 3]

3. @[agent_name] - [Task 3]:
   - [Specification line 1]
   - [Specification line 2]
   - [Specification line 3]

All tasks are independent, execute simultaneously.

Verification:
[command to verify]

Time: [estimated time]
```

### Template 2: Multi-Wave Prompt

```
# [Feature Name] - Parallel Execution Plan

## Summary
- Sequential Time: [X hours]
- Parallel Time: [Y hours]
- Savings: [Z%]

## WAVE 1: [Layer Name] ([Time])

Execute in parallel:

1. @[agent] - [Task 1]
2. @[agent] - [Task 2]
3. @[agent] - [Task 3]

Verification: [commands]

---

## WAVE 2: [Layer Name] ([Time])

Execute in parallel (after WAVE 1):

1. @[agent] - [Task 1]
2. @[agent] - [Task 2]

Verification: [commands]

---

[Continue for all waves]

## Total Time
- Sequential: [X hours]
- Parallel: [Y hours]
- **Savings: [Z%]**
```

---

## Quick Reference

### When Can Tasks Run in Parallel?

✅ **YES - Parallel:**
- Different database tables (no foreign keys between them)
- Different models (no method calls between them)
- Different services (no cross-calls)
- Different controllers (different resources)
- Different views/components
- Different test files
- All QA tasks (security, quality, style, coverage)

❌ **NO - Sequential:**
- Migration → Model (model needs table)
- Parent Model → Child Model (if child has foreign key to parent)
- Service A → Service B (if B calls A)
- Implementation → Tests (tests need code)
- Base Class → Subclass
- Concern → Model that includes it

### Time Savings by Pattern

| Pattern | Tasks | Sequential | Parallel | Savings |
|---------|-------|-----------|----------|---------|
| Database Layer | 3 migrations | 1.5h | 30m | 67% |
| Model Layer | 3 models | 3h | 1h | 67% |
| Service Layer | 3 services | 6h | 2h | 67% |
| Controller Layer | 3 controllers | 4.5h | 1.5h | 67% |
| View Layer | 4 components | 4h | 1h | 75% |
| Test Layer | 4 specs | 3h | 45m | 75% |
| QA Review | 4 checks | 2h | 30m | 75% |

**Average Savings: 40-70%**

---

## Resources

- **Workflow Agent:** `parallel-execution-orchestrator.md`
- **Example Features:** Check `/doc/features/*-PARALLEL-EXECUTION.md` files
- **Dependency Analysis Tools:** Mermaid diagrams, dependency tables

---

**Remember:** The key to parallelism is identifying truly independent work. When in doubt, analyze dependencies carefully before executing in parallel.
