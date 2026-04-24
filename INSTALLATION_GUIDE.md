# Complete Installation Guide

> Step-by-step guide to install VEP Rails Agents and optional security hooks

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    YOUR RAILS PROJECT                           │
│                                                                 │
│  .claude/                                                       │
│  ├── agents/                                                    │
│  │   ├── model-agent.md → ~/.vep/agents/model-agent.md         │
│  │   ├── service-agent.md → ~/.vep/agents/service-agent.md     │
│  │   ├── my-custom-agent.md  ← your own files coexist safely   │
│  │   └── ... (per-file symlinks)                               │
│  ├── commands/                                                  │
│  │   └── ... (per-file symlinks → ~/.vep/commands/)            │
│  ├── skills/                                                    │
│  │   ├── rspec-testing/ → ~/.vep/skills/rspec-testing/         │
│  │   ├── my-custom-skill/  ← your own skills coexist safely    │
│  │   └── ... (per-skill-dir symlinks)                          │
│  ├── planning/  ← real directory, project-specific data        │
│  │   ├── PROJECT.md, REQUIREMENTS.md, STATE.md ...             │
│  │   └── features/[name].md                                    │
│  └── CLAUDE.md (project-specific rules)                        │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│          GLOBAL VEP INSTALLATION (installed once)              │
│                                                                 │
│  ~/.vep/                                                        │
│  ├── agents/ (31 specialist agents)                            │
│  ├── commands/ (vep-init, vep-feature, vep-wave, vep-state)   │
│  ├── skills/ (30 Rails knowledge modules)                      │
│  ├── planning/ (PROJECT, REQUIREMENTS, ROADMAP, etc.)          │
│  └── features/ (feature specification templates)               │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│      GLOBAL CLAUDE CODE CONFIGURATION (optional setup)         │
│                                                                 │
│  ~/.claude/                                                     │
│  ├── settings.json (hooks configuration)                       │
│  ├── CLAUDE.md (global rules for all projects)                │
│  └── hooks/ (security & quality scripts)                       │
│      ├── block-secrets.py                                      │
│      ├── block-dangerous-commands.sh                           │
│      └── rails-after-edit.sh                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Installation Steps

### Step 1: Install VEP Rails Agents (Per Project)

Navigate to your Rails project root and run:

```bash
# Navigate to project root
cd ~/my-rails-app/

# Create .claude directory if it doesn't exist
mkdir -p .claude

# Install VEP
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/install.sh | bash
```

**What it does:**
1. Clones `vep-rails-agents` to `~/.vep/` (only once)
2. Creates symlinks in `.claude/` to agents, commands, skills, planning
3. You're ready to use `/vep-init`, `/vep-feature`, etc.

**Result:**
```
~/.vep/                    (shared by all projects, updated via git pull)
├── agents/
├── commands/
├── skills/
└── planning/

my-rails-app/.claude/
├── agents/                     (real dir — VEP files symlinked per-file)
├── commands/                   (real dir — VEP files symlinked per-file)
├── skills/                     (real dir — VEP skills symlinked per-skill-dir)
├── planning/                   (real dir — project-specific, NOT shared)
└── CLAUDE.md (you create this)
```

**Key behavior:**
- Existing files in `.claude/agents/`, `.claude/skills/`, etc. are **never deleted**
- VEP agents/skills are added alongside your own files
- Running install again is safe — only updates VEP symlinks, skips user files
- `planning/` is project-specific — templates are copied once, never overwritten

**For Cursor:** Create `.cursor/` and pass `--cursor` so symlinks are created in `.cursor/` instead:

```bash
cd ~/my-rails-app/
mkdir -p .cursor
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/install.sh | bash -s -- --cursor
```

Result: agents appear as Cursor **subagents** (`.cursor/agents/`), skills as **Agent Skills** (`.cursor/skills/`). See [CURSOR_SETUP.md](CURSOR_SETUP.md) for usage.

**Uninstall from Cursor project:**
```bash
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/install.sh | bash -s -- --cursor --uninstall
```

---

### Step 2: (Optional) Set Up Global Security Hooks

Set up global protections for Claude Code. Run **once per machine**:

```bash
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/setup-hooks.sh | bash
```

**What it does:**
1. Creates `~/.claude/hooks/` directory
2. Asks which hooks you want to install
3. Creates hook scripts (Python + Bash)
4. Updates/creates `~/.claude/settings.json` with hook configuration

**Features:**
- ✅ Interactive setup (you choose each hook)
- ✅ Tests hooks after installation
- ✅ Creates backups of existing configuration
- ✅ Shows clear summary at the end

**Result:**
```
~/.claude/
├── settings.json          (global hook config)
├── CLAUDE.md             (global rules)
└── hooks/
    ├── block-secrets.py
    ├── block-dangerous-commands.sh
    └── rails-after-edit.sh
```

---

## Full Example: From Scratch

### Scenario: Starting a new Rails project

```bash
# 1. Create new Rails app
rails new my-awesome-app --css=tailwind --database=postgresql
cd my-awesome-app

# 2. Create .claude directory
mkdir -p .claude

# 3. Install VEP (first time users need to set up hooks too)
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/install.sh | bash

# 4. (First time on this machine) Set up global hooks
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/setup-hooks.sh | bash

# 5. Initialize project planning files
# (In Claude Code:)
/vep-init

# 6. Spec a feature
/vep-feature

# 7. Execute Wave 1 (RED phase - write failing tests)
/vep-wave 1 --dangerously-skip-permissions
```

---

## Multi-Project Setup

### Installing in a Second Project

If you already installed VEP and hooks on your machine:

```bash
cd ~/another-rails-app/
mkdir -p .claude
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/install.sh | bash
```

**Benefits:**
- ✅ VEP is already in `~/.vep/` (no re-download)
- ✅ Hooks are already in `~/.claude/` (no re-setup)
- ✅ Automatic updates across all projects
- ✅ New project immediately has agents, commands, skills, AND security hooks

---

## Configuration

### Create Project-Specific CLAUDE.md

After installation, create `.claude/CLAUDE.md` in your project:

```bash
cat > .claude/CLAUDE.md << 'EOF'
# My Rails Project

## Tech Stack
- Rails 8.1
- PostgreSQL
- Hotwire (Turbo + Stimulus)
- Tailwind CSS

## Development Workflow

Use VEP commands to orchestrate work:
- `/vep-init` - Initialize project planning
- `/vep-feature` - Spec and plan features
- `/vep-wave N` - Execute waves
- `/vep-state` - Save session state

## Agent Recommendations

- Use `@tdd_red_agent` to start features (write tests first)
- Use `@service_agent` for business logic (2+ models)
- Use `@review_agent` before merging

See CLAUDE_CODE_PROJECT_GUIDE.md for full agent list.
EOF
```

### Customize Global Hooks

Edit `~/.claude/settings.json` to customize hooks:

```bash
vim ~/.claude/settings.json
```

Remove hooks you don't want, add custom matchers, etc.

---

## Verification

### Test Installation

1. **Verify VEP is linked:**
   ```bash
   ls -la .claude/
   # Should show: agents, commands, skills, planning as symlinks → ~/.vep/
   ```

2. **Verify hooks are working:**
   ```bash
   # Test block-secrets hook
   echo '{"tool_input": {"file_path": ".env"}}' | python3 ~/.claude/hooks/block-secrets.py
   # Should exit with code 2 (blocked)

   # Test settings.json is valid
   jq . ~/.claude/settings.json
   # Should print without errors
   ```

3. **Check Claude Code can use agents:**
   - Open Claude Code
   - Try referencing an agent: `@tdd_red_agent write tests for a User model`
   - It should auto-complete and work

---

## Updating

### Update VEP (All Projects)

Update VEP to the latest version:

```bash
# Option 1: From any project directory
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/install.sh | bash

# Option 2: Manual update
cd ~/.vep
git pull
```

**Result:**
- All projects automatically get latest agents, commands, skills
- No need to re-run install in each project
- Symlinks automatically use new versions

### Update Hooks

If hooks are updated, re-run setup:

```bash
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/setup-hooks.sh | bash
```

You'll be asked to confirm each hook (can skip unchanged ones).

---

## Troubleshooting

### VEP not found in .claude/

**Problem:** Commands like `/vep-init` don't work

**Solution:**
```bash
# Check symlinks
ls -la .claude/

# If missing, re-run install
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/install.sh | bash
```

### Hooks not blocking sensitive files

**Problem:** Claude can still read `.env` files

**Solution:**
1. Check hook is executable:
   ```bash
   ls -la ~/.claude/hooks/block-secrets.py
   # Should show: -rwxr-xr-x
   ```

2. Check settings.json is valid:
   ```bash
   jq . ~/.claude/settings.json
   ```

3. Re-run hook setup:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/setup-hooks.sh | bash
   ```

### Different projects need different hooks

**Solution:**
1. You can have different `settings.json` per project (not recommended)
2. Or disable specific hooks in global `~/.claude/settings.json`
3. Or customize hook scripts in `~/.claude/hooks/`

---

## Uninstallation

### Remove VEP from One Project

```bash
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/install.sh | bash -s -- --uninstall
```

This removes symlinks from `.claude/` but keeps `~/.vep/` for other projects.

### Remove VEP Globally

```bash
rm -rf ~/.vep
```

All projects lose VEP symlinks. To restore, run install script in each project.

### Remove All Hooks

```bash
bash setup-hooks.sh --uninstall

# Or manually:
rm -rf ~/.claude/hooks
rm ~/.claude/settings.json
```

Backups are created: `~/.claude/settings.json.backup.1234567890`

---

## File Structure Reference

### What Gets Installed

```
~/.vep/                           (git repo, ~1MB — shared by all projects)
├── agents/
│   ├── model-agent.md
│   ├── controller-agent.md
│   ├── service-agent.md
│   └── ... (36 total)
├── commands/
│   ├── vep-init.md
│   ├── vep-feature.md
│   ├── vep-wave.md
│   └── vep-state.md
├── skills/
│   ├── rails-architecture/
│   ├── rails-service-object/
│   └── ... (56 total)
├── planning/                     (templates — copied to each project on first install)
│   ├── PROJECT.md
│   ├── REQUIREMENTS.md
│   ├── ROADMAP.md
│   ├── STATE.md
│   └── PHASE_PLAN.md
├── features/
│   └── FEATURE_TEMPLATE.md
└── install.sh

~/.claude/                        (configuration, ~10KB)
├── settings.json                 (hook matchers)
├── CLAUDE.md                     (global rules)
└── hooks/
    ├── block-secrets.py          (~6KB)
    ├── block-dangerous-commands.sh (~3KB)
    └── rails-after-edit.sh       (~1KB)

my-project/.claude/               (per-file symlinks — safe to add own files)
├── agents/
│   ├── model-agent.md → ~/.vep/agents/model-agent.md
│   └── ... (one symlink per agent)
├── commands/
│   └── ... (one symlink per command)
├── skills/
│   ├── rails-architecture/ → ~/.vep/skills/rails-architecture/
│   └── ... (one symlink per skill dir)
└── planning/                     (real dir — project-specific, not shared)
    ├── PROJECT.md
    └── STATE.md ...
```

---

## Next Steps

1. **Read Documentation:**
   - [CLAUDE_CODE_PROJECT_GUIDE.md](CLAUDE_CODE_PROJECT_GUIDE.md) - How to use 34 agents
   - [SETUP_HOOKS_README.md](SETUP_HOOKS_README.md) - Hook configuration details
   - [CLAUDE_CODE_SETUP_TEMPLATE.md](CLAUDE_CODE_SETUP_TEMPLATE.md) - Manual setup guide

2. **Start Your First Feature:**
   ```bash
   /vep-init                # Initialize planning files
   /vep-feature             # Spec your first feature
   /vep-wave 1              # Write failing tests (RED)
   ```

3. **Join the Community:**
   - GitHub: [rivettidaniel/vep-rails-agents](https://github.com/rivettidaniel/vep-rails-agents)
   - Report issues and suggest improvements

---

**Happy Rails Development! 🚀**
