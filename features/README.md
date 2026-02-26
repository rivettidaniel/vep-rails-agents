# Feature Templates

Templates for documenting and planning feature implementations.

## Overview

This directory contains templates that guide the feature development process from specification to parallel execution optimization.

---

## 🤖 Available Agents Quick Reference

When using these templates, you'll reference these specialist agents:

**Most Common:**
- `@migration_agent` - Database migrations
- `@model_agent` - ActiveRecord models
- `@service_agent` - Service Objects
- `@controller_agent` - Controllers
- `@view_component_agent` - ViewComponents
- `@tdd_red_agent` - Write failing tests first

**See full list:** Check the "Available Agents Reference" section in `PARALLEL_EXECUTION_TEMPLATE.md` for all 29 agents organized by category (Data, Business Logic, Design Patterns, Presentation, Testing, etc.)

---

## Available Templates

### 1. FEATURE_TEMPLATE.md

**Purpose:** Document a feature specification BEFORE developing it.

**Use when:**
- Starting a new feature
- Need to define requirements, user stories, acceptance criteria
- Planning implementation scope
- Creating Gherkin scenarios for tests

**Sections:**
- General Information (priority, estimate)
- Objective (problem, value, success criteria)
- User Stories (main + secondary with Gherkin)
- Edge Cases & Error Handling
- Breaking into Incremental PRs (critical for large features)
- Technical Scope (models, migrations, services, controllers, views)
- Testing Strategy
- Security & Performance Considerations
- UI/UX Guidelines
- Deployment Plan

**Output:** Complete feature specification ready for review by `@feature_reviewer_agent`

**Next Step:** Use `@feature_planner_agent` to create implementation plan with PR breakdown

---

### 2. PARALLEL_EXECUTION_TEMPLATE.md ⚡ NEW

**Purpose:** Optimize feature implementation by identifying independent tasks and executing them in parallel.

**Use when:**
- Have a feature plan with multiple PRs/tasks
- Want to reduce development time by 40-60%
- Need to understand task dependencies
- Ready to execute implementation efficiently

**Key Concept:** **Execute independent agents in ONE message for parallel execution**

**Sections:**
- Summary (time savings calculation)
- Dependency Analysis (task table + graph)
- Execution Waves (groups of parallel tasks)
- Execution Prompts (copy-paste ready)
- Verification Steps (per wave)
- Time Comparison (sequential vs parallel)
- Critical Notes (bottlenecks, risks)
- Execution Checklist

**Output:** Wave-by-wave execution plan with prompts for parallel agent execution

**Typical Savings:** 40-60% reduction in development time

---

## Workflow: From Spec to Parallel Execution

```
1. FEATURE_TEMPLATE.md
   └─> Write complete feature specification
       └─> Review with @feature_reviewer_agent
           ↓
2. @feature_planner_agent
   └─> Generate implementation plan with PR breakdown
       └─> Creates: [feature-name]-plan.md
           ↓
3. PARALLEL_EXECUTION_TEMPLATE.md
   └─> Analyze plan dependencies
   └─> Group into parallel waves
   └─> Generate execution prompts
       └─> Creates: [feature-name]-PARALLEL-EXECUTION.md
           ↓
4. Execute Feature
   └─> Follow wave-by-wave execution
   └─> Verify each wave
   └─> Complete in 40-60% less time
```

---

## Example File Structure

After following the workflow, you'll have:

```
doc/features/
├── subscription-system.md                    # From FEATURE_TEMPLATE.md
├── subscription-system-plan.md               # From @feature_planner_agent
└── subscription-system-PARALLEL-EXECUTION.md # From PARALLEL_EXECUTION_TEMPLATE.md
```

---

## Quick Start Examples

### Example 1: Small Feature (< 1 day)

```bash
# 1. Create spec
cp vep-rails-agents/features/FEATURE_TEMPLATE.md doc/features/quick-filter.md
# ... fill in specification ...

# 2. Skip parallel planning (too small)
# Just implement directly with TDD

# 3. Use @senior_developer for orchestration
@senior_developer implement feature from doc/features/quick-filter.md
```

### Example 2: Medium Feature (1-3 days)

```bash
# 1. Create spec
cp vep-rails-agents/features/FEATURE_TEMPLATE.md doc/features/user-profiles.md
# ... fill in specification ...

# 2. Create implementation plan
@feature_planner_agent create plan from doc/features/user-profiles.md

# 3. Create parallel execution plan
cp vep-rails-agents/features/PARALLEL_EXECUTION_TEMPLATE.md \
   doc/features/user-profiles-PARALLEL-EXECUTION.md
# ... analyze dependencies and create waves ...

# 4. Execute waves
# [Copy prompts from parallel plan and execute]
```

### Example 3: Large Feature (3-5 days)

```bash
# 1. Create spec (critical for large features)
cp vep-rails-agents/features/FEATURE_TEMPLATE.md doc/features/subscription-system.md
# ... comprehensive specification with edge cases ...

# 2. Review spec
@feature_reviewer_agent review doc/features/subscription-system.md

# 3. Create plan with PR breakdown
@feature_planner_agent create detailed plan from doc/features/subscription-system.md

# 4. Create parallel execution strategy
cp vep-rails-agents/features/PARALLEL_EXECUTION_TEMPLATE.md \
   doc/features/subscription-system-PARALLEL-EXECUTION.md
# ... map all dependencies, identify waves ...

# 5. Execute incrementally
# Follow wave-by-wave execution
# WAVE 1: [execute all tasks in parallel]
# WAVE 2: [execute after WAVE 1 verified]
# etc.
```

---

## Parallel Execution Principles

### The Golden Rule

**To execute agents in parallel, call ALL agents in ONE message.**

❌ **WRONG (Sequential):**
```
Message 1: @migration_agent CreateUsers
[wait]
Message 2: @model_agent User model
[wait]
Message 3: @service_agent UserService
```
Time: 30m + 1h + 2h = 3.5h

✅ **CORRECT (Parallel):**
```
Single Message:

Execute in parallel:

1. @migration_agent CreateUsers (30m)
2. @migration_agent CreateProducts (30m)
3. @migration_agent CreateOrders (30m)

All independent, execute simultaneously.
```
Time: max(30m, 30m, 30m) = 30m

### When Can Tasks Run in Parallel?

✅ **YES - Parallel:**
- Different migrations (no foreign keys between tables)
- Different models (no associations/method calls between them)
- Different services (no cross-service calls)
- Different controllers (different resources)
- Different ViewComponents
- Different test files
- All QA checks (security, quality, style, coverage)

❌ **NO - Sequential:**
- Migration → Model (model needs table)
- Parent model → Child model (if foreign key)
- Service A → Service B (if B calls A)
- Implementation → Tests
- Base class → Subclass

---

## Time Savings by Feature Size

| Feature Size | Tasks | Sequential | Parallel | Savings |
|--------------|-------|-----------|----------|---------|
| Small (< 1 day) | 3-5 | 6h | 4h | 33% |
| Medium (1-3 days) | 6-12 | 18h | 10h | 44% |
| Large (3-5 days) | 13-20 | 40h | 22h | 45% |
| Epic (> 5 days) | 21+ | 80h | 45h | 44% |

**Average:** 40-50% time savings with proper parallelization

---

## Common Patterns

### Pattern 1: Layered Architecture

```
WAVE 1: All migrations (parallel)
WAVE 2: All models (parallel, after migrations)
WAVE 3: All services (parallel, after models)
WAVE 4: Controllers + Views (parallel, after services)
WAVE 5: All tests (parallel, after implementation)
```

### Pattern 2: Independent Slices

```
WAVE 1: User slice + Product slice (parallel, independent)
WAVE 2: Order slice (sequential, depends on User & Product)
```

### Pattern 3: Mixed Dependencies

```
WAVE 1: Independent migrations (parallel)
WAVE 2: Independent models (parallel)
WAVE 3: Dependent models (sequential)
WAVE 4: Services (mixed parallel/sequential based on calls)
```

---

## Tools & Skills

**Related Skills:**
- `parallel-execution-patterns.md` - Detailed patterns and examples
- `rails-architecture.md` - Architecture decisions
- `tdd-cycle.md` - TDD methodology

**Related Agents:**
- `@feature_specification_agent` - Creates feature specs
- `@feature_planner_agent` - Creates implementation plans
- `@feature_reviewer_agent` - Reviews specifications
- `@senior_developer` - Orchestrates implementation
- `@senior_qa_reviewer` - Reviews completed work

---

## FAQ

**Q: When should I use parallel execution?**
A: For any feature with 4+ independent tasks. Smaller features (1-3 tasks) don't benefit much.

**Q: How do I know if tasks are independent?**
A: Ask: "Does Task B need output from Task A?" If NO → parallel. If YES → sequential.

**Q: What if I'm not sure about dependencies?**
A: Default to sequential. It's safer. You can optimize later.

**Q: Can I mix parallel and sequential?**
A: Yes! That's what waves are for. Each wave runs in parallel, waves run sequentially.

**Q: What's the biggest risk?**
A: Starting Task B before Task A completes when B depends on A. Always verify previous wave completed.

**Q: How accurate are time estimates?**
A: ±20% typically. Adjust based on actual times for future planning.

---

## Best Practices

1. **Always spec first** - Use FEATURE_TEMPLATE.md for medium/large features
2. **Review before planning** - Get spec approved by @feature_reviewer_agent
3. **Plan before executing** - Use @feature_planner_agent for PR breakdown
4. **Parallelize when beneficial** - Use PARALLEL_EXECUTION_TEMPLATE.md for 4+ tasks
5. **Verify each wave** - Don't skip verification between waves
6. **Document learnings** - Note actual times vs estimates
7. **Iterate and improve** - Use learnings for next feature

---

## Support

**Template Issues:**
- Check examples in this README
- Review filled examples in project's `doc/features/` directory
- Ask for clarification on unclear sections

**Parallel Execution Questions:**
- Review `skills/parallel-execution-patterns.md`
- Check dependency analysis rules
- Test with small feature first

**Integration with Agents:**
- Templates are designed to work with feature_spec_agents
- Follow the workflow: Spec → Plan → Parallel → Execute
- Each step feeds into the next

---

**Last Updated:** 2026-02-24
**Templates:** 2 (FEATURE_TEMPLATE.md, PARALLEL_EXECUTION_TEMPLATE.md)
**Typical Time Savings:** 40-60% with parallel execution

---

## VEP Planning System

The **VEP (Venezuelan Execution Protocol) planning system** is a meta-layer above the feature templates that manages multi-phase project state across sessions and orchestrates wave-based parallel execution.

### Problem Solved

Long projects suffer from "context rot" - decisions, blockers, and architectural choices get lost between sessions. VEP externalizes this state into persistent `.md` files so every session starts with full context.

### Planning Files (in `planning/`)

| File | Purpose | Update Frequency |
|------|---------|-----------------|
| `PROJECT.md` | Vision, scope boundaries, tech stack | Once at project start |
| `REQUIREMENTS.md` | P0/P1/P2 requirements with acceptance criteria | When requirements change |
| `ROADMAP.md` | Phase-by-phase plan with PR tracking | As PRs merge |
| `STATE.md` | Architecture decisions, blockers, session log | Every session |
| `PHASE_PLAN.md` | XML task definitions with wave structure | Per phase |

### VEP Commands (Claude Code slash commands)

| Command | Purpose |
|---------|---------|
| `/vep-init` | Initialize all planning files for a new project |
| `/vep-wave` | Execute one wave of parallel tasks from PHASE_PLAN.md |
| `/vep-state` | Update STATE.md at end of session |

### How VEP Relates to Feature Templates

```
VEP Planning Layer (project scope):
  planning/PROJECT.md       <- vision and scope
  planning/REQUIREMENTS.md  <- what to build
  planning/ROADMAP.md       <- phases and PRs
  planning/STATE.md         <- persistent decisions
  planning/PHASE_PLAN.md    <- atomic tasks + waves
        |
        v
Feature Template Layer (single feature scope):
  features/FEATURE_TEMPLATE.md           <- feature spec
  features/PARALLEL_EXECUTION_TEMPLATE.md <- execution plan
```

VEP operates at the **project level** across multiple phases. Feature templates operate at the **feature level** within a single phase.

### Workflow with VEP

```
1. /vep-init
   └─> Creates all planning/ files
       └─> PHASE_PLAN.md for Phase 1

2. Load STATE.md at session start (paste "Context for Next Session")

3. /vep-wave [wave number]
   └─> Reads PHASE_PLAN.md wave tasks
   └─> Dispatches parallel agents in ONE message
   └─> Verifies each task's completion command
   └─> Commits atomically (one commit per task)
   └─> Updates PHASE_PLAN.md progress tracker

4. /vep-state at session end
   └─> Records architecture decisions as ADRs
   └─> Logs blockers
   └─> Generates "Context for Next Session" block

5. Repeat waves until phase complete
   └─> Update ROADMAP.md checkboxes
   └─> Create new PHASE_PLAN.md for next phase
```

### Key VEP Principle: Atomic Tasks

Every task in PHASE_PLAN.md follows this contract:
- One agent call
- One atomic commit
- One verification command
- Explicit `depends_on` field

This makes failure recovery trivial: if a task fails, fix it, re-verify, re-commit. The plan always reflects reality.

### Templates

Copy from `planning/` to your project root:
```bash
cp vep-rails-agents/planning/PROJECT.md your-project/planning/PROJECT.md
cp vep-rails-agents/planning/REQUIREMENTS.md your-project/planning/REQUIREMENTS.md
cp vep-rails-agents/planning/ROADMAP.md your-project/planning/ROADMAP.md
cp vep-rails-agents/planning/STATE.md your-project/planning/STATE.md
cp vep-rails-agents/planning/PHASE_PLAN.md your-project/planning/PHASE_PLAN.md
```

Or use `/vep-init` to have Claude fill them in automatically based on your project answers.
