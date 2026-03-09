# /vep-wave - Execute a Wave of Parallel Tasks

You are a **wave orchestrator**. Your job is to execute one wave from PHASE_PLAN.md by dispatching parallel agents and verifying results.

## Pre-flight Checklist

Before executing a wave:

### 0. Branch Setup (automatic)
Read `planning/STATE.md` to get the feature branch name (field `Branch:` under Active Feature).
Then run:
```bash
git branch --show-current
```
- If already on the correct branch → continue
- If on `main` or a different branch → create and switch automatically:
```bash
git checkout -b [branch-from-STATE.md]
```
Never ask the user to do this manually. Do it as part of pre-flight.

### 1. Standard checks
- [ ] Previous wave tasks are all committed (check git log)
- [ ] All tests pass: `bundle exec rspec`
- [ ] You have the current PHASE_PLAN.md open
- [ ] You know which wave number to execute

## Execution Protocol

### 1. Parse Wave Tasks
From PHASE_PLAN.md, extract all tasks for the requested wave number.

### 2. Identify Parallelizable Tasks
Tasks with no unmet `depends_on` can run in parallel.

### 3. Dispatch in ONE Message
Call ALL parallel agents in a SINGLE message (not sequentially). Include the agent's skills so it loads the correct patterns:

```
# Example for Wave 1 (2 parallel tasks):
"Execute these tasks in parallel:

Task 1.1 - @tdd_red_agent (skills: tdd-cycle):
[full task description from XML, including files and verification]

Task 1.2 - @tdd_red_agent (skills: tdd-cycle):
[full task description from XML, including files and verification]

Both are independent. Execute simultaneously."
```

```
# Example for Wave 3 (3 parallel tasks):
"Execute these tasks in parallel:

Task 3.1 - @service_agent (skills: rails-service-object, rails-architecture):
[full task description from XML, including files and verification]

Task 3.2 - @policy_agent (skills: authorization-pundit):
[full task description from XML, including files and verification]

Task 3.3 - @query_agent (skills: rails-query-object, performance-optimization):
[full task description from XML, including files and verification]

All independent. Execute simultaneously."
```

### 4. Verify Each Task
After agents complete, run each task's `<verification>` command. Also verify skills were loaded by agent — check agent used correct patterns from referenced skills.

### 5. Commit Atomically
Use the `<commit>` message from each task:
```bash
git add [specific files]
git commit -m "[commit message from task XML]"
```

### 6. Update Progress
Mark task as completed in PHASE_PLAN.md progress tracker:
`| 1.1 User specs | tdd_red_agent | 1 | Done | abc1234 |`

### 7. Update ROADMAP.md & STATE.md
After all tasks complete, update both:

**ROADMAP.md:**
- Mark completed PRs with [x]
- Update phase `Status:` field
- Update `Actual time:` elapsed
- Update Progress Summary table

**STATE.md:**
```markdown
### Session YYYY-MM-DD
**Completed:**
- Wave 1: [task names]
**Decisions made:**
- [ADR references if any]
**Next session:**
- Start Wave 2: [next wave description]
```

## Execution with Permissions Flag

For faster parallel execution without permission prompts between tasks, use the `--dangerously-skip-permissions` flag:

```bash
/vep-wave 1 --dangerously-skip-permissions
```

This flag:
- ✅ Skips permission confirmations between parallel agent calls
- ✅ Allows all agents to execute without blocking on user input
- ✅ Ideal for large multi-task waves where you've already verified the task scope
- ⚠️ Use only when you've reviewed the full PHASE_PLAN.md and trust the task definitions
- ⚠️ Not recommended for first-time or high-risk waves without careful review

**When to use:**
- Wave 2-6 after Wave 1 RED phase validates the overall approach
- Multiple parallel tasks with proven patterns
- Large features where stopping to confirm each agent adds context overhead

**When NOT to use:**
- Wave 1 (RED phase) - review failing tests carefully
- First time running a new feature pattern
- When modifying core architecture
- When you haven't reviewed the full task scope

## Wave Completion Report

After all tasks in a wave are done, output:
```
Wave [N] Complete

Completed tasks: X/X
Tests passing: yes / no
Commits:
  - abc1234: task 1.1 commit message
  - def5678: task 1.2 commit message

Next: Run /vep-wave for Wave [N+1]
Pre-flight: Verify all Wave [N] tasks are committed first
```

## Failure Protocol
If a task fails:
1. Do NOT proceed to next wave
2. Fix the failing task first
3. Re-run verification
4. Only then continue

## Agent & Skills Reference

Use this table when building the dispatch message to know which skills to pass to each agent:

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
| `tailwind_agent` | _(none)_ | Wave 4-5 |
| `tdd_refactoring_agent` | `tdd-cycle`, `rails-architecture` | Wave 5 |
| `lint_agent` | _(none)_ | Wave 5 |
| `review_agent` | `rails-architecture` | Wave 6 |
| `security_agent` | _(none)_ | Wave 6 |
| `rspec_agent` | `tdd-cycle` | Wave 6 |

## Rules
- NEVER run tasks from different waves simultaneously (respects dependencies)
- ALWAYS commit atomically (one commit per task, not one big commit)
- ALWAYS update STATE.md after wave completes
- NEVER skip verification steps
