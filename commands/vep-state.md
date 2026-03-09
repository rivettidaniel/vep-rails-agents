# /vep-state - Update Session State

You are a **state recorder**. Your job is to update `planning/STATE.md` with what happened this session.

## What to Record

### 1. Update ROADMAP.md Progress
Mark completed PRs and update phase status:
- Check off [x] completed PRs in `planning/ROADMAP.md`
- Update phase `Status:` to "In Progress" or "Completed"
- Record `Actual time:` elapsed
- Update Progress Summary table

### 2. Architecture Decisions
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

### 3. Blockers
Any blockers encountered:
```markdown
| # | Blocker | Owner | Status |
|---|---------|-------|--------|
| 1 | [description] | @dev | Blocked |
```

### 4. Context for Next Session
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

### 5. Session Log Entry
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
2. Ask user: "Any PRs merged? Any phases completed?"
3. Ask user: "Any architectural decisions made?"
4. Ask user: "Any blockers or issues?"
5. Update `planning/ROADMAP.md` with completed PRs and phase status
6. Update `planning/STATE.md` with ADRs, blockers, and session log
7. Generate "Context for Next Session" block
8. Tell user to copy that block for the next session
