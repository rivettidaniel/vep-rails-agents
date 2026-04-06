---
name: skill-creator
description: Create new Rails skills, modify and improve existing ones. Use when the user wants to build a new skill from scratch, improve an existing skill, capture a workflow as a reusable skill, or turn a repeated Rails pattern into a skill. Triggers on: "create a skill", "new skill for", "turn this into a skill", "skill for X", "add a skill", "improve this skill".
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Skill Creator

A skill for creating and improving Rails skills in this project.

The process:
1. Understand what the skill should do and when it should trigger
2. Write a draft SKILL.md
3. Test it with 2-3 realistic prompts
4. Audit with `skill-auditor` for code correctness
5. Iterate until satisfied

Figure out where the user is in this process and jump in. If they say "I want a skill for X", start from step 1. If they already have a draft, go straight to testing and auditing.

---

## Step 1: Capture Intent

Start by understanding what the user wants. If the current conversation already shows a workflow they want to capture, extract the answers from history first.

Ask:

1. **What should this skill enable Claude to do?** (one sentence)
2. **When should it trigger?** — what phrases, contexts, Rails layers? (e.g., "when creating service objects", "when user mentions Pundit")
3. **Which Rails layer does it cover?**
   - [ ] Model / migration
   - [ ] Service object / query object / form object
   - [ ] Controller
   - [ ] View / ViewComponent / Turbo / Stimulus
   - [ ] Background job / mailer
   - [ ] Design pattern (Strategy / Builder / State / etc.)
   - [ ] Authorization / security
   - [ ] Testing (TDD / RSpec)
   - [ ] Infrastructure (gems, deployment, performance)
4. **Does it have objectively verifiable outputs?** (file transformations, code generation, fixed steps → yes; writing style, design decisions → probably not)
5. **Is there an existing skill this overlaps with?** Run `ls skills/` and check.

Wait for the answers before writing anything.

---

## Step 2: Interview and Research

Before writing the skill, dig deeper:

- What are the edge cases?
- What anti-patterns should the skill explicitly warn against?
- What does the happy path look like step by step?
- Are there project-specific conventions to enforce? (e.g., dry-monads, Solid Queue, Pundit)
- What other skills in the project does this relate to? See `references/rails-layer-map.md`.

Search existing skills for overlap:
```bash
grep -r "[keyword]" skills/*/SKILL.md -l
```

Come prepared with context to reduce burden on the user.

---

## Step 3: Write the SKILL.md

Every skill in this project uses this exact frontmatter:

```yaml
---
name: skill-name              # matches directory name in skills/
description: [one paragraph]  # WHEN to use + WHAT it does — this is the trigger mechanism
allowed-tools: Read, Write, Edit, Bash, Glob, Grep  # only what the skill actually needs
---
```

### Description field — most important part

The description is what determines whether Claude invokes this skill. Make it slightly "pushy" to counter under-triggering:

- Include WHAT it does AND WHEN to use it
- List trigger phrases explicitly: "Use when user mentions X, Y, Z"
- Name Rails concepts it covers even if the user doesn't say them explicitly

**Weak description:**
```yaml
description: Helps with service objects.
```

**Strong description:**
```yaml
description: Creates service objects following single-responsibility principle with dry-monads Result pattern. Use when extracting business logic from controllers, creating complex operations, implementing interactors, or when user mentions service objects, POROs, business logic, or operations touching 2+ models.
```

### Body structure

Use this as the skeleton — adapt based on the skill's domain:

```markdown
# [Skill Name]

## Overview
[2-5 bullets: what this skill enforces, why it matters]

## When to Use [Skill Name]

| Scenario | Use this skill? |
|----------|-----------------|
| ...      | Yes             |
| ...      | No (use X instead) |

## Workflow Checklist
[copy-paste progress tracker with checkboxes]

## Step 1: [First step]
[concrete instructions + code examples]

## Step 2: [Second step]
...

## Related Skills
| Skill | Use When |
|-------|----------|
| ...   | ...      |
```

### Content rules

- **Imperative form:** "Create the spec first", not "You should create the spec first"
- **Explain the why:** Don't just say MUST — say why. LLMs follow reasoning better than mandates.
- **Both ❌ and ✅ examples:** Show the anti-pattern before the correct pattern
- **Project conventions are non-negotiable:**
  - dry-monads: `Success()` / `Failure()` / `result.value!` / `result.failure`
  - No callback side effects (`after_create_commit :send_email` → in controller)
  - Specs in `spec/requests/` not `spec/controllers/`
  - Turbo: `data: { turbo_method: :delete }` not `method: :delete`
  - Nil-guard: `user&.admin?` when user can be nil
- **Under 500 lines:** If approaching the limit, move reference material to `references/` and link to it clearly

Run `ls skills/` and grep existing skill descriptions to check for overlap before writing.

---

## Step 4: Write Test Cases

After the draft, write 2-3 realistic test prompts — what a real user would actually say. Show them to the user:

> "Here are the test cases I want to try. Do these look right, or would you add more?"

Good test cases are specific, not generic:

**Weak:** `"Create a service object"`

**Strong:** `"I need a service to handle subscription upgrades — it touches the User, Subscription, and BillingHistory models, calls Stripe, and sends a confirmation email. Should I use a service object?"`

Save them here so they can be rerun after iterations:

```
skills/[skill-name]-workspace/
└── test-cases.md
```

Format:
```markdown
# Test Cases: [skill-name]

## Case 1: [name]
**Prompt:** [exact user message]
**Expected behavior:** [what the skill should produce]
**Pass criteria:** [how to know it worked]

## Case 2: ...
```

---

## Step 5: Run and Evaluate

Run each test case manually — read the skill, follow its instructions, execute the task as if you were an agent with access to it.

For each result, evaluate:

```
Evaluation: [case name]
- [ ] Did the skill trigger correctly?
- [ ] Did it follow the workflow checklist?
- [ ] Are code examples syntactically correct?
- [ ] Do examples follow project conventions (dry-monads, no callbacks, etc.)?
- [ ] Is the output copy-paste useful?
- [ ] Would this mislead a developer into an anti-pattern?
```

Then run `skill-auditor` on the new SKILL.md:

```
Usa la skill skill-auditor para auditar skills/[skill-name]/SKILL.md
```

Audit covers: dry-monads API, callback side effects, spec paths, Turbo syntax, nil-guards, migration safety, and documentation completeness.

---

## Step 6: Iterate

Based on test results and the audit:

### How to think about improvements

1. **Generalize, don't overfit.** The skill will be used across thousands of different prompts. If your fix only works for the specific test case that broke, it's the wrong fix. Find the underlying principle and express it.

2. **Keep it lean.** Remove anything that isn't pulling its weight. If the skill makes agents waste time on unproductive steps, cut those sections.

3. **Explain the why.** If you're tempted to write ALWAYS or NEVER in all caps, stop and ask: can I explain *why* instead? A model that understands the reasoning will generalize better than one following rigid rules.

4. **Bundle repeated work.** If test runs all independently wrote the same helper logic, that's a signal the skill should provide it in `references/` or `scripts/`.

Repeat until:
- All test cases pass their criteria
- `skill-auditor` gives score ≥ 8/10
- No CRITICAL issues remain

---

## Step 7: Register the Skill

After the skill is complete, register it in three places:

### 1. Update README.md
Add to the correct category under `## Skills Library`:
```markdown
#### [Category]
- **`skill-name`** - One-line description of what it does
```

### 2. Update CLAUDE.md
Increment the skills count:
```markdown
- `skills/` - 32 reusable knowledge modules   # was 31
```

### 3. Update vep-feature.md and vep-wave.md (if the skill maps to an agent)
Add a row to the Agent-to-Skill Reference Table if the skill pairs with an existing agent:
```markdown
| `agent_name` | `skill-name` | Wave N |
```

---

## Step 8: Description Optimization (optional)

After the skill is working, you can optimize the description for better triggering.

Generate 15-20 trigger eval queries — a mix of should-trigger and should-not-trigger. The key is realism:

**Weak (too obvious):**
- `"write a service object"` → should trigger
- `"make a chart"` → should NOT trigger

**Strong (edge cases):**
- `"I have some business logic in my controller that calls 3 different models and a Stripe API — where should this live?"` → should trigger
- `"I need to run a SQL query that joins 5 tables"` → should NOT trigger (use `rails-query-object` instead)

For each query:
```json
{"query": "...", "should_trigger": true}
{"query": "...", "should_trigger": false}
```

Test by asking: "If you saw this message with access to skill X, would you load the skill?" Adjust description until the right queries trigger and the wrong ones don't.

---

## Reference files

- Run `ls skills/` and `grep -r "description:" skills/*/SKILL.md` to find overlapping skills

---

## Core loop summary

1. Understand the intent (Step 1-2)
2. Write SKILL.md draft (Step 3)
3. Write test cases (Step 4)
4. Run tests + skill-auditor audit (Step 5)
5. Iterate until score ≥ 8/10 (Step 6)
6. Register in project docs (Step 7)
7. Optionally optimize description (Step 8)
