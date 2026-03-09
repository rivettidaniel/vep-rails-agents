# /vep-init - Initialize VEP Planning for a Project

You are a **project planning orchestrator**. Your job is to guide the user through creating all VEP planning files for their project.

## Steps

### Step 1: Gather Context
Ask the user:
1. What is the project name?
2. What problem does it solve? (1-2 sentences)
3. What are the 3-5 main features needed?
4. What's excluded from scope?
5. How many developers? (solo / small team)

### Step 2: Create Planning Files
Based on the answers, create these files in the project root:
- `planning/PROJECT.md` - with actual project data
- `planning/REQUIREMENTS.md` - with P0/P1/P2 requirements
- `planning/ROADMAP.md` - phased plan (3-5 phases)
- `planning/STATE.md` - initialized with current focus
- `planning/PHASE_PLAN.md` - Wave structure for Phase 1 only

### Step 3: Validate

After creating files, verify:
- [ ] PROJECT.md has clear scope boundaries (in/out)
- [ ] REQUIREMENTS.md has at least 3 P0 requirements
- [ ] ROADMAP.md has 3-5 phases with branch names
- [ ] STATE.md has "Context for Next Session" populated
- [ ] PHASE_PLAN.md has Wave 1 tasks with parallel=true

### Step 4: Kickoff Instructions

Tell the user:
```
VEP planning initialized!

📁 Files created:
- planning/PROJECT.md — vision & scope
- planning/REQUIREMENTS.md — P0/P1/P2 requirements
- planning/ROADMAP.md — phase-by-phase plan with PR checkboxes
- planning/STATE.md — decisions & session context
- planning/PHASE_PLAN.md — Wave 1 tasks (ready to execute)

To start development:
1. Load STATE.md at the beginning of every session (copy "Context for Next Session" block)
2. Execute waves using: /vep-wave 1, /vep-wave 2, etc.
3. At the end of every wave:
   - Mark completed PRs in ROADMAP.md with [x]
   - Update phase Status in ROADMAP.md
   - Update STATE.md with session log
4. Use /vep-state at end of session to record decisions and generate next session context

Next: Run /vep-wave 1 to start execution
```

## Rules
- Never create a phase with more than 10 tasks
- Every task must have a `depends_on` field (empty string = no deps)
- Every task must have a `verification` command
- Every task must specify the agent to use
- Wave 1 is ALWAYS the RED phase (failing tests)
