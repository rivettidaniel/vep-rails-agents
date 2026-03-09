# Rails Layer Map — Existing Skills

Use this to avoid creating skills that duplicate existing coverage.

## Data Layer

| Skill | What it covers |
|-------|---------------|
| `rails-model-generator` | Model creation, validations, associations, scopes |
| `database-migrations` | Safe migrations, zero-downtime, indexes |
| `rails-concern` | Shared model behavior via modules |
| `rails-query-object` | Complex queries, N+1 prevention, filtering |
| `active-storage-setup` | File uploads, attachments, variants |

## Business Logic Layer

| Skill | What it covers |
|-------|---------------|
| `rails-service-object` | Service objects, dry-monads Result pattern |
| `form-object-patterns` | Multi-model forms, wizards |
| `rails-presenter` | View logic separation, decorators |
| `event-dispatcher-pattern` | 3+ side effects, ApplicationEvent bus |

## Authorization & Security

| Skill | What it covers |
|-------|---------------|
| `authorization-pundit` | Pundit policies, scopes, permitted attributes |

## Design Patterns

| Skill | What it covers |
|-------|---------------|
| `builder-pattern` | Complex multi-step object construction |
| `strategy-pattern` | Interchangeable algorithms (payment providers, exporters) |
| `template-method-pattern` | Workflows with customizable steps (importers) |
| `state-pattern` | State machines with transitions (order status) |
| `chain-of-responsibility-pattern` | Request processing pipelines |
| `factory-method-pattern` | Polymorphic object creation |
| `command-pattern` | Operations with undo/redo, queues |

## Controller & HTTP Layer

| Skill | What it covers |
|-------|---------------|
| `rails-controller` | RESTful controllers, strong params, thin actions |

## Frontend Layer

| Skill | What it covers |
|-------|---------------|
| `hotwire-patterns` | Turbo Frames, Turbo Streams, Stimulus |
| `viewcomponent-patterns` | Reusable UI components |

## Background & Async

| Skill | What it covers |
|-------|---------------|
| `solid-queue-setup` | Background jobs, SolidQueue configuration |
| `action-mailer-patterns` | Transactional emails, previews, testing |
| `action-cable-patterns` | WebSocket real-time features |

## Infrastructure

| Skill | What it covers |
|-------|---------------|
| `rails-architecture` | Layered architecture, structural decisions |
| `performance-optimization` | N+1 prevention, caching, eager loading |
| `caching-strategies` | Fragment, action, HTTP caching |
| `api-versioning` | Versioned REST APIs |
| `i18n-patterns` | Internationalization, localization |
| `authentication-flow` | Rails 8 built-in auth |
| `packwerk` | Package boundaries, enforcing privacy |

## Testing

| Skill | What it covers |
|-------|---------------|
| `tdd-cycle` | Red-Green-Refactor workflow |

## Meta / Tooling

| Skill | What it covers |
|-------|---------------|
| `skill-auditor` | Auditing and improving existing skill files |
| `skill-creator` | Creating new skills (this skill) |

---

## Gap detection

Before creating a new skill, ask: which row above does this fit under? If it fits under an existing skill, consider extending that skill instead. Create a new skill when:

- The domain is distinct enough to warrant its own file (different Rails layer, different pattern)
- The existing skill is already near 500 lines
- The new skill has a different "when to use" trigger from existing ones
