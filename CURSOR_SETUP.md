# Cursor Setup Guide for VEP Rails Agents

> Use the same 39 agents and 52 skills from the Rails AI Suite in **Cursor**. Agents appear as subagents; skills are loaded as Agent Skills.

---

## Installation

From your **Rails project root**:

```bash
mkdir -p .cursor
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/install.sh | bash -s -- --cursor
```

This installs VEP once to `~/.vep/` and creates symlinks in your project’s `.cursor/` directory:

| Symlink           | Cursor role        | Contents                                      |
|-------------------|--------------------|-----------------------------------------------|
| `.cursor/agents/` | **Subagents**      | 31 specialist agents (TDD, models, services, etc.) |
| `.cursor/skills/` | **Agent Skills**   | 30 Rails knowledge modules (SKILL.md format)  |
| `.cursor/commands/` | Reference only   | VEP command docs (vep-init, vep-feature, etc.) |
| `.cursor/planning/` | Reference only   | PROJECT, REQUIREMENTS, ROADMAP, STATE, PHASE_PLAN |
| `.cursor/features/` | Reference only  | Feature specification templates               |

**Uninstall (Cursor):**

```bash
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/install.sh | bash -s -- --cursor --uninstall
```

---

## Using Agents (Subagents)

VEP agents are Cursor **subagents**. Invoke them by **name** (with `@` or `/`):

- **@-mention:** e.g. `@model_agent create a User model with email and role`
- **Slash:** e.g. `/model_agent create a User model with email and role`

Agent names use underscores in the repo (e.g. `model_agent`); Cursor may show them with hyphens (e.g. `model-agent`). Use either form when invoking.

**Examples:**

```
@tdd_red_agent write failing tests for Post model with title, body, published_at
@model_agent implement the Post model
@service_agent create Posts::PublishService
@controller_agent create PostsController with CRUD
@policy_agent create PostPolicy
@review_agent check the implementation
```

Same workflows as in the [Claude Code Project Guide](CLAUDE_CODE_PROJECT_GUIDE.md)—TDD, thin controllers, service objects, no callback side effects.

**Note:** The repo also includes 3 feature-spec agents in `feature_spec_agents/`; they are not symlinked by default. For the VEP feature workflow, ask the agent to follow `.cursor/commands/vep-feature.md`; it describes how to run the spec and review steps.

---

## Using Skills

Skills in `.cursor/skills/` are **Agent Skills**. Cursor discovers them automatically and applies them when relevant. You can also invoke a skill explicitly by typing `/` in Agent chat and choosing the skill.

No extra setup; the 30 Rails skills (e.g. `rails-service-object`, `hotwire-patterns`, `database-migrations`) are available to the agent.

---

## VEP Planning Workflow in Cursor

VEP commands (`/vep-init`, `/vep-feature`, `/vep-wave N`, `/vep-state`) are **not** built-in Cursor slash commands. You run the same workflow by asking the agent and pointing it at the command/planning files:

1. **Initialize (once):**  
   Ask: *“Initialize VEP planning for this project using the instructions in `.cursor/commands/vep-init.md`.”*  
   This creates (or updates) `planning/` files in your repo.

2. **Spec a feature:**  
   Ask: *“Run the VEP feature workflow from `.cursor/commands/vep-feature.md` for [feature name].”*  
   The agent should call the feature spec and reviewer agents and produce a `planning/PHASE_PLAN.md` with wave structure.

3. **Run a wave:**  
   Ask: *“Execute Wave N from `planning/PHASE_PLAN.md` using the agents and skills listed for each task.”*  
   The agent runs the corresponding subagents (e.g. `@tdd_red_agent`, `@model_agent`) in parallel where the plan says so.

4. **Save state:**  
   Ask: *“Update `planning/STATE.md` using the instructions in `.cursor/commands/vep-state.md` and record current ADRs, blockers, and context for next session.”*

Keeping `planning/` (and optionally `.cursor/commands/`, `.cursor/planning/`) in version control keeps the workflow consistent across sessions and teammates.

---

## Project Rules (Rails Conventions)

For the same Rails conventions (thin models, service objects, no callback side effects, Pundit, etc.) as in the main guide:

- **Option A:** Copy or symlink the repo’s **CLAUDE.md** into your project root as **AGENTS.md**, or into `.cursor/rules/` as a rule (e.g. `rails-vep-conventions.mdc`). That gives Cursor the same “project guide” content.
- **Option B:** Add a rule in `.cursor/rules/` that says: “Follow the Rails AI Suite conventions in the project’s CLAUDE.md (or AGENTS.md).”

Then your Cursor Agent will follow the same architecture and patterns as when using Claude Code with this suite.

---

## Quick Reference

| Goal                    | In Cursor |
|-------------------------|-----------|
| Use a specialist agent  | `@model_agent`, `@service_agent`, etc. or `/model_agent`, … |
| Use a skill             | Auto-applied when relevant, or invoke via `/` in chat |
| VEP init                | Ask agent to follow `.cursor/commands/vep-init.md` |
| VEP feature             | Ask agent to follow `.cursor/commands/vep-feature.md` |
| VEP wave N              | Ask agent to run Wave N from `planning/PHASE_PLAN.md` |
| VEP state               | Ask agent to follow `.cursor/commands/vep-state.md` |
| Rails conventions       | Put CLAUDE.md content in AGENTS.md or `.cursor/rules/` |

---

## More Detail

- **Full agent list and workflows:** [CLAUDE_CODE_PROJECT_GUIDE.md](CLAUDE_CODE_PROJECT_GUIDE.md) (same agents and skills, different IDE).
- **Install options and troubleshooting:** [INSTALLATION_GUIDE.md](INSTALLATION_GUIDE.md).
- **Project conventions and rules:** [CLAUDE.md](CLAUDE.md) in this repo.
