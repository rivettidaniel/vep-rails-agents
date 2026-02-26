# /vep-feature - Bridge Feature Spec to Phase Plan

You are a **feature planner**. Your job is to guide the user through defining a feature, generating a reviewed spec, and producing a complete wave-based PHASE_PLAN.md ready for `/vep-wave` execution.

---

## Step 1: Gather Feature Context

Ask the user these 5 questions before doing anything else. Wait for all answers before proceeding.

**Questions to ask:**

1. **Feature name** — provide a slug (e.g. `user-subscriptions`, `coffee-search`, `order-checkout`)
2. **Problem it solves** — 1-2 sentences describing the user problem this feature addresses
3. **Affected personas** — which of these apply: `visitor` / `user` / `owner` / `admin` (can select multiple)
4. **Estimate** — `small` (< 1 day) / `medium` (1-3 days) / `large` (> 3 days)
5. **Optional components** — check all that apply:
   - [ ] Background jobs (Solid Queue)
   - [ ] Email notifications (ActionMailer)
   - [ ] External API integration
   - [ ] State machine
   - [ ] Payment processing (Stripe)
   - [ ] File uploads (ActiveStorage)
   - [ ] Real-time Turbo Streams
   - [ ] Complex authorization (Pundit policies)
   - [ ] Design patterns (Builder / Strategy / Template Method / State / Chain / Factory / Command)

Record all answers. They drive agent selection in Steps 4 and 5.

---

## Step 2: Generate Feature Spec

Call `@feature_specification_agent` with the following instruction:

```
Create a complete feature specification for "[feature-name]" following the structure in features/FEATURE_TEMPLATE.md.

Feature context:
- Name: [feature-name]
- Problem: [user's answer]
- Personas: [user's answer]
- Estimate: [user's answer]
- Optional components: [user's answer]

Save the output to: features/[feature-name].md
```

Wait for the spec to be written before proceeding.

---

## Step 3: Review Spec

Call `@feature_reviewer_agent` with:

```
Review features/[feature-name].md against features/FEATURE_TEMPLATE.md.

Score it out of 10. Provide:
- Score: X/10
- Strengths (bullet list)
- Gaps or missing sections (bullet list)
- Suggested revisions if score < 7

Return the score clearly so I can check if we should proceed.
```

**Gate:**
- Score **< 7/10**: Ask `@feature_specification_agent` to revise the spec based on the reviewer's feedback, then re-run `@feature_reviewer_agent`. Repeat until score >= 7.
- Score **>= 7/10**: Proceed to Step 4.

Record the final score for use in Step 5.

---

## Step 4: Generate PHASE_PLAN.md

Based on the approved spec and the user's answers from Step 1, overwrite `planning/PHASE_PLAN.md` with a complete wave plan.

### Agent-to-Skill Reference Table

Use this table to assign correct skills to every agent in the plan:

| Agent | Skills | Typical Wave |
|-------|--------|-------------|
| `tdd_red_agent` | `tdd-cycle` | Wave 1 (RED) |
| `migration_agent` | `database-migrations` | Wave 2 |
| `model_agent` | `rails-model-generator`, `rails-concern` | Wave 2 |
| `service_agent` | `rails-service-object`, `rails-architecture` | Wave 3 |
| `policy_agent` | `authorization-pundit` | Wave 3 |
| `form_agent` | `form-object-patterns` | Wave 3 |
| `query_agent` | `rails-query-object`, `performance-optimization` | Wave 3 |
| `presenter_agent` | `rails-presenter` | Wave 3 |
| `event_dispatcher_agent` | _(none)_ | Wave 3 |
| `builder_agent` | `builder-pattern` | Wave 3 |
| `strategy_agent` | `strategy-pattern` | Wave 3 |
| `template_method_agent` | `template-method-pattern` | Wave 3 |
| `state_agent` | `state-pattern` | Wave 3 |
| `chain_of_responsibility_agent` | `chain-of-responsibility-pattern` | Wave 3 |
| `factory_method_agent` | `factory-method-pattern` | Wave 3 |
| `command_agent` | `command-pattern` | Wave 3 |
| `packwerk_agent` | `packwerk` | Wave 3-4 |
| `controller_agent` | `rails-controller` | Wave 4 |
| `view_component_agent` | `viewcomponent-patterns` | Wave 4 |
| `turbo_agent` | `hotwire-patterns` | Wave 4 |
| `stimulus_agent` | `hotwire-patterns` | Wave 4 |
| `mailer_agent` | `action-mailer-patterns` | Wave 4 |
| `job_agent` | `solid-queue-setup` | Wave 4 |
| `tdd_refactoring_agent` | `tdd-cycle`, `rails-architecture` | Wave 5 |
| `lint_agent` | _(none)_ | Wave 5 |
| `review_agent` | `rails-architecture` | Wave 6 |
| `security_agent` | _(none)_ | Wave 6 |
| `rspec_agent` | `tdd-cycle` | Wave 6 |

### Standard 6-Wave Structure

Generate only the waves and tasks relevant to the feature. Skip waves or agents that do not apply.

**Wave 1 — RED (parallel=true)**
Always included. One `@tdd_red_agent` task per independent test file. Common task splits:
- Model specs (one task per model)
- Service specs
- Request/integration specs
- Policy specs (if complex authorization selected)
- Component specs (if ViewComponents used)

**Wave 2 — Foundation (parallel=true)**
Always included. Migrations first, then models. Multiple models can run in parallel if they have no cross-references.
- `@migration_agent` (skills: `database-migrations`)
- `@model_agent` (skills: `rails-model-generator`, `rails-concern`)

**Wave 3 — Business Logic (parallel=true)**
Include only agents the feature needs (based on Step 1 answers):
- `@service_agent` — always include for any real business logic
- `@policy_agent` — if "complex authorization" was selected
- `@form_agent` — if multi-model forms are needed
- `@query_agent` — if complex DB queries / N+1 risk
- `@presenter_agent` — if significant view logic
- `@event_dispatcher_agent` — if 3+ side effects to coordinate
- Design pattern agents — only if the feature genuinely benefits from the pattern:
  - `@builder_agent`, `@strategy_agent`, `@template_method_agent`
  - `@state_agent` — if "state machine" selected
  - `@chain_of_responsibility_agent`, `@factory_method_agent`, `@command_agent`

All Wave 3 tasks are parallel because they work on different files.

**Wave 4 — Interface (parallel=true)**
Include only what the feature needs:
- `@controller_agent` — always included if there are HTTP endpoints
- `@view_component_agent` — if reusable UI components are needed
- `@turbo_agent` — if "real-time Turbo Streams" selected
- `@stimulus_agent` — if JavaScript interactivity needed
- `@mailer_agent` — if "email notifications" selected
- `@job_agent` — if "background jobs" selected

**Wave 5 — Refactor (parallel=false, sequential)**
Always included. Run sequentially — lint depends on refactor being done first:
1. `@tdd_refactoring_agent` (skills: `tdd-cycle`, `rails-architecture`)
2. `@lint_agent` (no skills)

**Wave 6 — QA (parallel=true)**
Always included. All three run in parallel:
- `@review_agent` (skills: `rails-architecture`)
- `@security_agent` (no skills)
- `@rspec_agent` (skills: `tdd-cycle`)

### XML Task Format

Every task must use this exact format:

```xml
<task id="N.M" agent="agent_name" skills="skill1,skill2" depends_on="prev_id_or_empty">
  <title>Short descriptive title</title>
  <files>specific files to create or modify</files>
  <verification>exact shell command to verify task is complete</verification>
  <commit>conventional commit message</commit>
</task>
```

Field rules:
- `id`: wave number dot task number (e.g. `1.1`, `3.2`)
- `agent`: snake_case agent name without `@`
- `skills`: comma-separated skill names, or empty string `""` if none
- `depends_on`: space-separated task IDs that must be done first, or empty string `""`
- `files`: specific paths, not vague descriptions
- `verification`: must be a runnable shell command (not "manual review" unless truly unavoidable)
- `commit`: conventional commit format (`feat:`, `test:`, `style:`, `refactor:`, `security:`)

Max 10 tasks per wave.

### Progress Tracker

End the PHASE_PLAN.md with a markdown progress tracker table:

```markdown
## Progress Tracker

| Task | Agent | Skills | Wave | Status | Commit |
|------|-------|--------|------|--------|--------|
| 1.1 [title] | tdd_red_agent | tdd-cycle | 1 | ⏳ Pending | - |
```

Include every task from all waves in the table.

---

## Step 5: Update STATE.md

Append the following entry to `planning/STATE.md` under the current session heading. If STATE.md does not exist, create it.

```markdown
### Active Feature: [feature-name]
**Spec:** features/[feature-name].md (score: X/10)
**Plan:** planning/PHASE_PLAN.md (N tasks, 6 waves)
**Branch:** feature/[feature-name]
**Status:** Ready for /vep-wave 1
```

---

## Step 6: Output Kickoff Instructions

After all files are written, display this summary to the user:

```
Feature Planning Complete

Feature:   [feature-name]
Problem:   [1-sentence summary]
Spec:      features/[feature-name].md (score: X/10)
Plan:      planning/PHASE_PLAN.md (N tasks across 6 waves)
Branch:    feature/[feature-name]

Next steps — run these in order:

  /vep-wave 1   Wave 1: RED — failing tests (N tasks, parallel)
  /vep-wave 2   Wave 2: Foundation — migrations + models (N tasks, parallel)
  /vep-wave 3   Wave 3: Business Logic — services + policies (N tasks, parallel)
  /vep-wave 4   Wave 4: Interface — controllers + views (N tasks, parallel)
  /vep-wave 5   Wave 5: Refactor — cleanup + lint (sequential)
  /vep-wave 6   Wave 6: QA — review + security + coverage (parallel)

Create your feature branch before starting Wave 1:
  git checkout -b feature/[feature-name]
```

---

## Rules

- Spec score MUST be >= 7/10 before generating PHASE_PLAN.md — do not skip the gate.
- Wave 1 is ALWAYS RED: failing tests only, zero implementation.
- Wave 6 is ALWAYS QA: review + security + coverage — never skip it.
- Only include agents and waves the feature actually needs — do not add agents speculatively.
- Max 10 tasks per wave — split into sub-waves if needed.
- Tasks within a parallel wave MUST be truly independent (no shared files, no ordering requirement).
- Every task needs a runnable verification command — prefer commands that fail visibly when the task is incomplete.
- Skills field: use comma-separated list from the reference table, or empty string `""` for agents with no skills.
- Do not generate a PHASE_PLAN.md that re-uses the template example tasks — generate tasks specific to this feature.
