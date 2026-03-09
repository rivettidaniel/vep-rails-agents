# Roadmap: [Project Name]

> Phase-by-phase plan derived from REQUIREMENTS.md and PHASE_PLAN.md.
> Each phase = one feature branch = multiple incremental PRs.
> Update PR checkboxes at the end of each wave using `/vep-wave` or `/vep-state`.

## Phase 1: Foundation [Status: Pending / In Progress / Completed]

**Goal:** Set up core data layer
**Branch:** `feature/phase-1-foundation`
**Requirements covered:** REQ-001, REQ-002

### PRs (ordered by dependency - maps to PHASE_PLAN waves)
- [ ] PR #1: Failing tests for models (Wave 1: RED)
- [ ] PR #2: Database migrations + model implementation (Wave 2: Foundation)
- [ ] PR #3: Services + policies (Wave 3: Business Logic)
- [ ] PR #4: Controllers + views (Wave 4: Interface)
- [ ] PR #5: Refactoring + lint fixes (Wave 5: Refactor)

**Wave 6 (QA): Review + security audit** ← check all PRs above before merging

**Estimated time:** 2 days
**Actual time:** -

---

## Phase 2: Business Logic [Status: Pending]

**Goal:** Service objects and background jobs
**Branch:** `feature/phase-2-business-logic`
**Requirements covered:** REQ-003, REQ-004

### PRs
- [ ] PR #4: Service objects (Step 1)
- [ ] PR #5: Background jobs (Step 2)

**Estimated time:** 3 days

---

## Progress Summary

| Phase | Total PRs | Completed | Status | Requirements |
|-------|-----------|-----------|--------|--------------|
| Phase 1: Foundation | 5 | 0/5 | ⏳ Pending | REQ-001, REQ-002 |
| Phase 2: Business Logic | 4 | 0/4 | ⏳ Pending | REQ-003, REQ-004 |

**Overall Progress:** 0/9 PRs merged

**Legend:**
- ⏳ **Pending:** Not started
- 🔄 **In Progress:** Currently executing waves
- ✅ **Completed:** All PRs merged + Wave 6 QA passed
