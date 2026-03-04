# Phase Plan: [Phase Name]

> Atomic tasks with explicit dependencies.
> Each task = one agent call = one atomic commit.
> Independent tasks within a wave run in PARALLEL.

## Agent-to-Skill Reference

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
| `event_dispatcher_agent` | `event-dispatcher-pattern` | Wave 3 |
| `builder_agent` | `builder-pattern` | Wave 3 |
| `strategy_agent` | `strategy-pattern` | Wave 3 |
| `template_method_agent` | `template-method-pattern` | Wave 3 |
| `state_agent` | `state-pattern` | Wave 3 |
| `chain_of_responsibility_agent` | `chain-of-responsibility-pattern` | Wave 3 |
| `factory_method_agent` | `factory-method-pattern` | Wave 3 |
| `command_agent` | `command-pattern` | Wave 3 |
| `packwerk_agent` | `packwerk` | Wave 3-4 |
| `gem_agent` | _(none)_ | Wave 1-4 (as needed) |
| `implementation_agent` | `rails-architecture` | Wave 2-4 (as needed) |
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

## Wave Structure

```
Wave 1 (Tests - no deps): task-1, task-2, task-3 → PARALLEL
Wave 2 (Models - needs Wave 1): task-4, task-5 → PARALLEL
Wave 3 (Services - needs Wave 2): task-6 → sequential
Wave 4 (QA - needs Wave 3): task-7, task-8, task-9 → PARALLEL
```

## Task Definitions

```xml
<phase name="Phase 1: Foundation" branch="feature/phase-1-foundation">

  <wave number="1" parallel="true" description="Failing tests (RED phase)">
    <task id="1.1" agent="tdd_red_agent" skills="tdd-cycle" depends_on="">
      <title>Failing tests for User model</title>
      <files>spec/models/user_spec.rb</files>
      <verification>bundle exec rspec spec/models/user_spec.rb --format documentation | grep "0 examples passed"</verification>
      <commit>test(red): failing specs for User model</commit>
    </task>

    <task id="1.2" agent="tdd_red_agent" skills="tdd-cycle" depends_on="">
      <title>Failing tests for Product model</title>
      <files>spec/models/product_spec.rb</files>
      <verification>bundle exec rspec spec/models/product_spec.rb --format documentation | grep "0 examples passed"</verification>
      <commit>test(red): failing specs for Product model</commit>
    </task>
  </wave>

  <wave number="2" parallel="true" description="Model implementation (GREEN phase)">
    <task id="2.1" agent="migration_agent" skills="database-migrations" depends_on="1.1">
      <title>Migration for users table</title>
      <files>db/migrate/TIMESTAMP_create_users.rb</files>
      <verification>bundle exec rails db:migrate db:rollback</verification>
      <commit>feat: migration for users table</commit>
    </task>

    <task id="2.2" agent="model_agent" skills="rails-model-generator,rails-concern" depends_on="1.1 2.1">
      <title>User model implementation</title>
      <files>app/models/user.rb</files>
      <verification>bundle exec rspec spec/models/user_spec.rb</verification>
      <commit>feat: User model with validations and scopes</commit>
    </task>
  </wave>

  <wave number="3" parallel="true" description="QA (REFACTOR + LINT + SECURITY)">
    <task id="3.1" agent="lint_agent" skills="" depends_on="2.1 2.2">
      <title>RuboCop fixes</title>
      <files>app/models/, spec/models/</files>
      <verification>bundle exec rubocop app/models/ spec/models/ --no-offense-counts</verification>
      <commit>style: rubocop fixes for Phase 1 models</commit>
    </task>

    <task id="3.2" agent="security_agent" skills="" depends_on="2.1 2.2">
      <title>Security audit</title>
      <files>app/models/</files>
      <verification>bundle exec brakeman --no-pager | grep "No warnings"</verification>
      <commit>security: fix brakeman warnings from Phase 1</commit>
    </task>

    <task id="3.3" agent="review_agent" skills="rails-architecture" depends_on="2.1 2.2">
      <title>Code quality review</title>
      <files>app/models/, spec/models/</files>
      <verification>Manual review - no HIGH/CRITICAL issues</verification>
      <commit>refactor: code quality improvements from review</commit>
    </task>
  </wave>

</phase>
```

## Execution Commands

```bash
# Wave 1: Launch 2 parallel agents in ONE message:
# "Execute Wave 1 tasks 1.1 and 1.2 in parallel: [paste task XMLs]"

# Wave 2: After Wave 1 commits:
# "Execute Wave 2 tasks 2.1 and 2.2 in parallel: [paste task XMLs]"

# Wave 3: After Wave 2 commits:
# "Execute Wave 3 tasks 3.1, 3.2, and 3.3 in parallel: [paste task XMLs]"
```

## Progress Tracker

| Task | Agent | Skills | Wave | Status | Commit |
|------|-------|--------|------|--------|--------|
| 1.1 User specs | tdd_red_agent | tdd-cycle | 1 | ⏳ Pending | - |
| 1.2 Product specs | tdd_red_agent | tdd-cycle | 1 | ⏳ Pending | - |
| 2.1 Users migration | migration_agent | database-migrations | 2 | ⏳ Pending | - |
| 2.2 User model | model_agent | rails-model-generator, rails-concern | 2 | ⏳ Pending | - |
| 3.1 Lint | lint_agent | | 3 | ⏳ Pending | - |
| 3.2 Security | security_agent | | 3 | ⏳ Pending | - |
| 3.3 Review | review_agent | rails-architecture | 3 | ⏳ Pending | - |
