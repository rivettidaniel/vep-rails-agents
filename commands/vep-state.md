# /vep-state - Update Session State

You are a **state recorder**. Your job is to update `planning/STATE.md` with what happened this session.

## What to Record

### 1. Architecture Decisions
Any significant decisions made this session should become ADRs:
- Technology choices
- Pattern selections
- Data model changes
- API design decisions

Format:
```markdown
### ADR-00X: [Title]
**Date:** [today]
**Status:** Accepted
**Context:** [why needed]
**Decision:** [what decided]
**Consequences:** [trade-offs]
```

### 2. Blockers
Any blockers encountered:
```markdown
| # | Blocker | Owner | Status |
|---|---------|-------|--------|
| 1 | [description] | @dev | Blocked |
```

### 3. Context for Next Session
Generate a compact context block:
```
Project: [name]
Current phase: Phase X - [name]
Current PR: PR #Y - [description]
Branch: [current branch]
Last decision: [most recent ADR summary]
Blocker: [active blocker or "none"]
Next action: [first thing to do next session]
```

### 4. Session Log Entry
```markdown
### Session YYYY-MM-DD
**Completed:**
- [bullet list of what was done]
**Decisions made:**
- [ADR references]
**Blockers:**
- [any new blockers]
**Next session:**
- [first action item]
```

## Instructions
1. Ask user: "What did we accomplish this session?"
2. Ask user: "Any architectural decisions made?"
3. Ask user: "Any blockers or issues?"
4. Update STATE.md with all information
5. Generate "Context for Next Session" block
6. Tell user to copy that block for the next session
