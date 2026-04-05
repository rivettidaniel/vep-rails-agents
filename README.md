<div align="center">

<img src="assets/banner.svg?v=1.2" alt="DÉJATE DE MARIQUERAS — Venezuelan Execution Protocol v1.2" width="900"/>

**A specialized AI agent suite for Rails development with wave-based parallel execution.**

[![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)](LICENSE)
[![Rails](https://img.shields.io/badge/Rails-7--8-red?style=for-the-badge&logo=rubyonrails)](https://rubyonrails.org)
[![Claude Code](https://img.shields.io/badge/Claude_Code-compatible-blueviolet?style=for-the-badge)](https://claude.ai/code)
[![Cursor](https://img.shields.io/badge/Cursor-compatible-00d4aa?style=for-the-badge&logo=cursor)](https://cursor.com)

**Claude Code (default):**
```bash
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/install.sh | bash
```
> Run from your Rails project root. Requires a `.claude/` directory — create it with `mkdir .claude` if needed.

**Cursor:**
```bash
mkdir -p .cursor
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/install.sh | bash -s -- --cursor
```
> Run from your Rails project root. Requires a `.cursor/` directory — create it with `mkdir .cursor` if needed.

**Uninstall:**
```bash
# Claude (default)
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/install.sh | bash -s -- --uninstall

# Cursor
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/install.sh | bash -s -- --cursor --uninstall
```

</div>

---

## How It Works

VEP installs once globally to `~/.vep/` and creates **symlinks** in each project's IDE directory (`.claude/` for Claude Code or `.cursor/` for Cursor):

```
~/.vep/                    (global installation)
├── agents/
├── commands/
├── skills/
├── features/
└── planning/

Your Project (Claude Code):
.claude/
├── agents → ~/.vep/agents         (symlink)
├── commands → ~/.vep/commands     (symlink)
├── skills → ~/.vep/skills         (symlink)
└── planning → ~/.vep/planning     (symlink)

Your Project (Cursor):
.cursor/
├── agents → ~/.vep/agents         (symlink) — subagents
├── commands → ~/.vep/commands     (symlink)
├── skills → ~/.vep/skills         (symlink) — Agent Skills
└── planning → ~/.vep/planning     (symlink)
```

**This means:**
- ✅ Install once, use everywhere
- ✅ Updates automatically across all projects
- ✅ No file duplication

---

## Updating to Latest Version

**Option 1:** Run the install script again (auto-detects and updates):
```bash
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/install.sh | bash
```

**Option 2:** Manual update (from anywhere):
```bash
cd ~/.vep
git pull
```

Both options automatically update agents in **all your projects** that use VEP. 🚀

---

## Optional: Set Up Global Security Hooks

Protect your Rails projects with global Claude Code hooks (one-time setup per machine):

```bash
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/setup-hooks.sh | bash
```

This sets up optional hooks to:
- ✅ **Block sensitive file access** - Prevents reading `.env`, `master.key`, credentials
- ✅ **Block dangerous commands** - Prevents `rm -rf /`, force push, `chmod 777`
- ✅ **Auto-format code** - Runs RuboCop after Ruby edits (optional)

**What happens:**
- Hooks install to `~/.claude/hooks/` (global, shared by all projects)
- Configuration goes in `~/.claude/settings.json`
- All your Rails projects automatically benefit from these protections
- You can uninstall anytime: `bash setup-hooks.sh --uninstall`

See [SETUP_HOOKS_README.md](SETUP_HOOKS_README.md) for detailed documentation.

</div>

---

A curated collection of specialized AI agents for Rails development, organized into four complementary components:

1. **Standard Rails Agents** - Modern Rails patterns with service objects, query objects, and presenters
2. **Feature Specification Agents** - High-level planning and feature management
3. **VEP Planning System** - State-persistent project planning with wave-based parallel execution
4. **Skills Library** - Reusable knowledge modules for specific Rails patterns and technologies

> **New:** Use this project's 34 agents and 34 skills in your IDE:
> - **Claude Code:** [Claude Code Project Guide](CLAUDE_CODE_PROJECT_GUIDE.md) — use `/vep-feature` to spec + plan any feature and generate a wave-structured PHASE_PLAN. For general Rails setup, see [Claude Code Setup Template](CLAUDE_CODE_SETUP_TEMPLATE.md).
> - **Cursor:** [Cursor Setup Guide](CURSOR_SETUP.md) — install with `--cursor` and use the same agents as subagents and skills in Cursor Agent.

Built using insights from [GitHub's analysis of 2,500+ agent.md files](https://github.blog/ai-and-ml/github-copilot/how-to-write-a-great-agents-md-lessons-from-over-2500-repositories/).

## Why This Exists

Most AI coding assistants lack deep Rails context. This suite provides a comprehensive architectural approach:

- 🏗️ **Standard Rails**: Service objects, query objects, presenters, form objects
- 📋 **Feature Planning**: Requirements analysis and implementation orchestration
- 📚 **Skills Library**: Deep knowledge modules for Rails patterns and technologies

---

## Standard Rails Agents

Modern Rails architecture with clear separation of concerns, SOLID principles, and comprehensive testing.

### Core Philosophy

- **Thin models & controllers** - Delegate to service/query/presenter objects
- **Service objects** - Encapsulate business logic with dry-monads Result pattern
- **No callback side effects** - Side effects (emails, notifications) in controllers, not model callbacks
- **Query objects** - Complex queries in dedicated classes (prevents N+1)
- **Presenters** - View logic separated from models
- **Form objects** - Multi-model forms
- **Pundit policies** - Authorization (deny by default)
- **ViewComponent** - Tested, reusable components
- **TDD workflow** - RED → GREEN → REFACTOR

### Available Agents

#### Testing & TDD
- **`@tdd_red_agent`** - Writes failing tests FIRST (RED phase)
- **`@rspec_agent`** - RSpec expert for all test types
- **`@tdd_refactoring_agent`** - Refactors while keeping tests green

#### Implementation
- **`@model_agent`** - Thin ActiveRecord models
- **`@controller_agent`** - Thin RESTful controllers
- **`@service_agent`** - Business logic service objects
- **`@command_agent`** - Command Pattern with undo/redo, command queues
- **`@query_agent`** - Complex query objects
- **`@form_agent`** - Multi-model form objects
- **`@presenter_agent`** - View logic presenters
- **`@policy_agent`** - Pundit authorization
- **`@view_component_agent`** - ViewComponent + Hotwire
- **`@job_agent`** - Background jobs (Solid Queue)
- **`@mailer_agent`** - Mailers with previews
- **`@migration_agent`** - Safe migrations
- **`@implementation_agent`** - General implementation

#### Frontend
- **`@stimulus_agent`** - Stimulus controllers
- **`@turbo_agent`** - Turbo Frames/Streams
- **`@tailwind_agent`** - Tailwind CSS styling

#### Quality
- **`@review_agent`** - Code quality analysis
- **`@lint_agent`** - Style fixes (no logic changes)
- **`@security_agent`** - Security audits (Brakeman)

#### Design Patterns
- **`@builder_agent`** - Builder Pattern for complex multi-step object construction
- **`@strategy_agent`** - Strategy Pattern with registry-based interchangeable algorithms
- **`@template_method_agent`** - Template Method Pattern for workflows with customizable hooks
- **`@state_agent`** - State Pattern for state machines with transitions
- **`@chain_of_responsibility_agent`** - Chain of Responsibility for request processing pipelines
- **`@factory_method_agent`** - Factory Method Pattern for polymorphic object creation

#### Event Handling & Package Management
- **`@event_dispatcher_agent`** - Event dispatcher for complex side effects (3+ actions)
- **`@packwerk_agent`** - Package boundary management with Packwerk

### Standard Rails Workflow Example

```
1. @feature_planner_agent analyze the user authentication feature

2. @tdd_red_agent write failing tests for User model

3. @model_agent implement the User model

4. @tdd_red_agent write failing tests for AuthenticationService

5. @service_agent implement AuthenticationService

6. @controller_agent create SessionsController

7. @policy_agent create authorization policies

8. @review_agent check implementation

9. @tdd_refactoring_agent improve code structure

10. @lint_agent fix style issues
```

### Key Patterns

**Service Objects:**
```ruby
module Users
  class CreateService < ApplicationService
    def call
      # Returns Success(data) or Failure(error)
      # Uses dry-monads for Result handling
    end
  end
end
```

**Thin Controllers:**
```ruby
def create
  authorize User
  result = Users::CreateService.call(params: user_params)

  if result.success?
    redirect_to result.value!
  else
    render :new, status: :unprocessable_entity
  end
end
```

**Query Objects:**
```ruby
class Users::SearchQuery
  def call(params)
    @relation
      .then { |rel| filter_by_status(rel, params[:status]) }
      .then { |rel| search_by_name(rel, params[:q]) }
  end
end
```

---

## Feature Specification Agents

High-level planning and orchestration for complex features.

### Available Agents

- **`@feature_specification_agent`** - Writes detailed feature specifications
- **`@feature_planner_agent`** - Breaks features into tasks, recommends agents
- **`@feature_reviewer_agent`** - Reviews completed features against specs

### VEP Feature Workflow

VEP (Venezuelan Execution Protocol) replaces manual orchestration with a state-persistent planning system. Use `/vep-feature` to automatically spec, review, and generate a wave-structured PHASE_PLAN:

```
1. /vep-init     → initialize project planning files (once per project)
2. /vep-feature  → spec + review + generate PHASE_PLAN with agents+skills per wave
3. /vep-wave 1   → failing tests (RED) — all parallel agents in ONE message
4. /vep-wave 2-4 → implementation (GREEN) — migrations, models, services, controllers
5. /vep-wave 5-6 → refactor + QA — lint, security, review
6. /vep-state    → save session state, ADRs, and "Context for Next Session" block
```

Feature specification agents are called automatically by `/vep-feature`:

```
1. @feature_specification_agent write spec for blog with comments

2. @feature_reviewer_agent verify spec is complete and implementable

3. [PHASE_PLAN.md generated with wave structure]

4. /vep-wave N  execute each wave
```

---

## Skills Library

Reusable knowledge modules that provide deep context on specific Rails patterns and technologies. Skills are referenced by agents and can be used directly to provide comprehensive guidance.

### What Are Skills?

Skills are focused knowledge documents that contain:
- **Patterns & best practices** - Proven approaches for specific domains
- **Code examples** - Real-world implementations
- **Reference materials** - Detailed documentation for complex topics
- **Decision guidance** - When and how to use specific patterns

### Available Skills

#### Architecture & Patterns
- **`rails-architecture`** - Code organization decisions, layered architecture
- **`rails-concern`** - Shared behavior with concerns
- **`rails-service-object`** - Business logic encapsulation
- **`command-pattern`** - Command Pattern with undo/redo, command queues, and history
- **`rails-query-object`** - Complex database queries
- **`rails-presenter`** - View logic separation
- **`rails-controller`** - RESTful controller patterns
- **`rails-model-generator`** - Model creation with validations
- **`form-object-patterns`** - Multi-model forms, wizards

#### Frontend & Hotwire
- **`hotwire-patterns`** - Turbo Frames, Turbo Streams, Stimulus integration
- **`viewcomponent-patterns`** - Reusable UI components with ViewComponent

#### Authentication & Authorization
- **`authentication-flow`** - Rails 8 built-in authentication
- **`authorization-pundit`** - Pundit policies and permissions

#### Data & Storage
- **`database-migrations`** - Safe, reversible migrations
- **`active-storage-setup`** - File uploads and attachments
- **`caching-strategies`** - Fragment, action, and HTTP caching

#### Background Jobs & Real-time
- **`solid-queue-setup`** - Background job processing
- **`action-cable-patterns`** - WebSocket real-time features
- **`action-mailer-patterns`** - Transactional emails

#### API & Internationalization
- **`api-versioning`** - Versioned REST APIs
- **`i18n-patterns`** - Internationalization and localization

#### Performance & Testing
- **`performance-optimization`** - N+1 prevention, eager loading, optimization
- **`tdd-cycle`** - Test-driven development workflow

#### Design Patterns (Skills)
- **`builder-pattern`** - Builder pattern for complex multi-step construction
- **`chain-of-responsibility-pattern`** - Pipeline/filter pattern
- **`command-pattern`** - Command pattern with undo/redo, queues, and history
- **`factory-method-pattern`** - Polymorphic object creation
- **`state-pattern`** - State machines with transitions
- **`strategy-pattern`** - Registry-based interchangeable algorithms
- **`template-method-pattern`** - Workflows with customizable hooks
- **`event-dispatcher-pattern`** - Explicit side effects (3+ actions)

#### Meta / Tooling
- **`skill-auditor`** - Audits and improves existing skill files for correctness, code quality, and completeness
- **`skill-creator`** - Creates new Rails skills from scratch following project conventions, with test cases and iteration loop
- **`playwright-system-testing`** - End-to-end system tests with Playwright

### Using Skills

Skills provide context that agents can reference. Each skill includes:

```
skills/
├── skill-name/
│   ├── SKILL.md           # Main skill documentation
│   └── reference/         # Optional detailed references
│       ├── patterns.md
│       └── examples.md
```

### Example: Architecture Decision

The `rails-architecture` skill provides a decision tree for where code should live:

```
Where should this code go?
├─ Complex business logic?      → Service Object
├─ Complex database query?      → Query Object
├─ View/display formatting?     → Presenter
├─ Shared behavior across models? → Concern
├─ Authorization logic?         → Policy
├─ Reusable UI with logic?      → ViewComponent
└─ Async/background work?       → Job
```

---

## Agent Design Principles

All agents follow best practices from GitHub's analysis:

### ✅ What Makes These Agents Effective

- **YAML Frontmatter** - Each has `name` and `description`
- **Executable Commands** - Specific commands (e.g., `bundle exec rspec spec/models/user_spec.rb:25`)
- **Three-Tier Boundaries**:
  - ✅ **Always** - Must do
  - ⚠️ **Ask first** - Requires confirmation
  - 🚫 **Never** - Hard limits
- **Code Examples** - Real good/bad patterns
- **Concise** - ~100-150 lines per agent (skills hold the details)

---

## Tech Stack Support

### Standard Agents Stack
- Ruby 3.3+
- Rails 7.x - 8.x
- PostgreSQL
- Hotwire (Turbo + Stimulus)
- ViewComponent
- Tailwind CSS
- Solid Queue
- Pundit
- **dry-monads** (Result monad for service objects)
- RSpec + FactoryBot

---

## IDE Setup

### Claude Code

**Quick Start:** [CLAUDE_CODE_PROJECT_GUIDE.md](CLAUDE_CODE_PROJECT_GUIDE.md)

This guide shows how to use the **34 agents** and **30 skills** in this project:

- **Specialist Agents (31)** - Testing, implementation, frontend, quality, design patterns
- **Feature Spec Agents (3)** - Specification, planner, reviewer
- **VEP Planning System** - `/vep-init`, `/vep-feature`, `/vep-wave`, `/vep-state`
- **Skills (34)** - Architecture patterns, Hotwire, design patterns, and more
- **Workflow Examples** - From simple features to complex multi-phase projects

### General Rails Setup Template

For configuring Claude Code with **any Rails project**, see [CLAUDE_CODE_SETUP_TEMPLATE.md](CLAUDE_CODE_SETUP_TEMPLATE.md):

- **Global Configuration** - CLAUDE.md, settings.json, directory structure
- **Security Hooks** - Block secrets, dangerous commands, Rails-specific protections
- **Custom Commands** - `/ci`, `/lint`, `/security`, `/rails-test`, `/generate`
- **MCP Servers** - GitHub, PostgreSQL, sequential thinking integration

### Cursor

**Quick Start:** [CURSOR_SETUP.md](CURSOR_SETUP.md)

After installing with `--cursor`, VEP agents appear as **subagents** in Cursor Agent (invoke with `@agent_name` or `/agent-name`), and the skills library is available under `.cursor/skills/`. Use the same workflows (TDD, service objects, VEP planning) as in the Claude Code guide; see CURSOR_SETUP.md for Cursor-specific details and VEP command usage.

---

## Contributing

These agents are designed to be customized. Feel free to:

- Adjust boundaries based on your workflow
- Add project-specific commands
- Include custom validation rules
- Extend with your own coding standards

## Credits

Built using insights from:
- [How to write a great agents.md](https://github.blog/ai-and-ml/github-copilot/how-to-write-a-great-agents-md-lessons-from-over-2500-repositories/) by GitHub

## License

MIT License - Feel free to use and adapt these agents for your projects.
