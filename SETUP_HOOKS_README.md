# Claude Code Hooks Setup

> **Optional global security & quality configuration for Claude Code**

This script sets up Claude Code hooks to protect your Rails projects from accidental mistakes and security issues. Hooks are installed **globally** in `~/.claude/` and apply to **all Rails projects** on your machine.

---

## What Are Hooks?

Hooks are automated scripts that run **before** or **after** Claude Code uses tools:

- **PreToolUse hooks** - Run before Claude reads/writes/edits files (e.g., block access to `.env`)
- **PostToolUse hooks** - Run after Claude edits files (e.g., auto-run RuboCop)

This script provides three optional hooks for Rails developers:

1. **block-secrets.py** - Blocks access to sensitive files (`.env`, `master.key`, etc.)
2. **block-dangerous-commands.sh** - Blocks dangerous bash commands (`rm -rf /`, force push, etc.)
3. **rails-after-edit.sh** - Auto-runs RuboCop on Ruby files (optional)

---

## Quick Start

### Installation

Run this command **once per machine**:

```bash
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/setup-hooks.sh | bash
```

The script will:
- Ask which hooks you want to install
- Create `~/.claude/hooks/` with the selected hooks
- Create/update `~/.claude/settings.json` with hook configuration
- Test that everything is working

### Interactive Setup

The script is interactive and asks you to confirm each hook:

```
╔══════════════════════════════════════════════════╗
║  Claude Code Hooks Setup - Global Configuration  ║
╚══════════════════════════════════════════════════╝

This script sets up global Claude Code hooks for Rails security.

Hooks are stored in: ~/.claude/hooks/
Configuration in:    ~/.claude/settings.json

⚠️ These hooks will apply to ALL Rails projects on this machine.

Do you want to proceed? (y/n): y

▸ Creating hooks directory at ~/.claude/hooks
✓ Hooks directory created

Install block-secrets.py (prevent reading .env, master.key, etc)? (y/n): y
```

---

## What Gets Installed

### File Structure

```
~/.claude/
├── settings.json              # Hook configuration (matcher + command)
└── hooks/
    ├── block-secrets.py       # Blocks sensitive file access
    ├── block-dangerous-commands.sh  # Blocks dangerous commands
    └── rails-after-edit.sh    # Auto-runs RuboCop (optional)
```

### Hook 1: block-secrets.py

**What it does:** Prevents Claude from reading or exposing sensitive files.

**Blocks access to:**
- `.env`, `.env.local`, `.env.development`, `.env.production`, `.env.staging`
- `config/master.key` (Rails credentials key)
- `config/credentials.yml.enc` (encrypted credentials)
- `.kamal/secrets` (deployment secrets)
- SSH keys (`id_rsa`, `id_ed25519`, `id_ecdsa`)
- Any file with "secret", "credential", "password" in the name
- `.pem`, `.key`, `.p12` files (certificates/keys)

**When it triggers:** When Claude Code tries to Read, Edit, or Write to a sensitive file.

**Recommended:** ✅ **Always install this**

---

### Hook 2: block-dangerous-commands.sh

**What it does:** Prevents Claude from running dangerous bash commands.

**Blocks:**
- `rm -rf /` (delete root)
- `rm -rf ~` (delete home directory)
- `rm -rf ..` (delete parent directory)
- `git push --force main` (force push to protected branches)
- `chmod 777` (world-writable permissions)
- `curl URL | bash` (pipe remote scripts to shell)
- `rails db:drop` / `rails db:reset` in production
- Reading `.env` via `cat`, `less`, `more`, `head`, `tail`, `vim`, `nano`
- Exposing `master.key` via shell commands

**When it triggers:** When Claude Code tries to run a bash command.

**Recommended:** ✅ **Always install this**

---

### Hook 3: rails-after-edit.sh

**What it does:** Automatically runs RuboCop on Ruby files after Claude edits them.

**Benefits:**
- Auto-formats code to project style
- Catches style violations immediately
- No manual `rubocop -a` needed

**Requirements:**
- RuboCop must be installed in your project (`bundle exec rubocop`)

**When it triggers:** After Claude Code edits any `.rb` file.

**Recommended:** ✅ **Optional but useful**

---

## Usage

### Normal Installation

Install interactively with prompts for each hook:

```bash
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/setup-hooks.sh | bash
```

### Silent Installation (All Hooks)

Install all hooks without prompts:

```bash
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/setup-hooks.sh | bash -s -- --all
```

(Note: The current version requires interactive confirmation. For silent install, see below.)

### Local Installation

If you have the script locally:

```bash
bash setup-hooks.sh              # Interactive setup
bash setup-hooks.sh --help       # Show help
bash setup-hooks.sh --uninstall  # Remove all hooks
```

---

## Configuration

### View Current Configuration

```bash
cat ~/.claude/settings.json
```

### Edit Settings Manually

```bash
vim ~/.claude/settings.json
```

### Structure of settings.json

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "python3 ~/.claude/hooks/block-secrets.py"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/block-dangerous-commands.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/rails-after-edit.sh"
          }
        ]
      }
    ]
  },
  "permissions": {
    "deny": [
      "Read(.env)",
      "Read(config/master.key)",
      "Bash(rm -rf /)"
    ]
  }
}
```

**Key fields:**
- `matcher` - Which tools trigger this hook (e.g., "Read|Edit|Write", "Bash")
- `command` - The script to run (e.g., `python3 ~/.claude/hooks/block-secrets.py`)
- `PreToolUse` - Runs BEFORE the tool executes
- `PostToolUse` - Runs AFTER the tool executes

---

## Uninstallation

### Remove All Hooks

```bash
bash setup-hooks.sh --uninstall
```

Or manually:

```bash
rm -rf ~/.claude/hooks
rm ~/.claude/settings.json
```

**Note:** Settings are backed up before removal:
```bash
~/.claude/settings.json.backup.1234567890
```

---

## Troubleshooting

### Hooks Not Working

1. **Verify hooks are executable:**
   ```bash
   ls -la ~/.claude/hooks/
   # Should show: -rwxr-xr-x (executable)
   ```

2. **Check settings.json is valid:**
   ```bash
   jq . ~/.claude/settings.json  # Should print without errors
   ```

3. **Test a hook manually:**
   ```bash
   echo '{"tool_input": {"file_path": ".env"}}' | python3 ~/.claude/hooks/block-secrets.py
   # Should exit with code 2 (blocked)
   ```

### RuboCop Hook Not Running

1. **Verify RuboCop is installed:**
   ```bash
   bundle exec rubocop --version
   ```

2. **Check hook is executable:**
   ```bash
   ls -la ~/.claude/hooks/rails-after-edit.sh
   ```

### Hooks Blocking Legitimate Files

If a hook is too strict, you can:

1. **Edit the hook script** (e.g., `~/.claude/hooks/block-secrets.py`)
2. **Modify settings.json** to disable a specific hook
3. **Ask Claude to use a different approach** (e.g., "Use bin/rails credentials:edit instead")

---

## For Project Creators

If you want to include hook setup in your project documentation:

### Add to Your README

```markdown
## Security Setup

To set up Claude Code hooks for Rails security:

```bash
curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/setup-hooks.sh | bash
```

This sets up global protections to:
- Block access to `.env` files and Rails credentials
- Prevent dangerous bash commands
- Auto-format Ruby code with RuboCop
```

### Add to Your CLAUDE.md

```markdown
## Setup Instructions

1. Install VEP Rails Agents:
   ```bash
   mkdir -p .claude
   curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/install.sh | bash
   ```

2. (Optional) Set up global hooks for security:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/rivettidaniel/vep-rails-agents/main/setup-hooks.sh | bash
   ```
```

---

## FAQ

### Q: Will hooks slow down Claude Code?

**A:** No. Hooks run in parallel and are very fast (<10ms typically). The block-secrets hook just checks filename patterns. The dangerous-commands hook uses grep to check bash strings.

### Q: Do I need to run setup for each project?

**A:** No. Hooks are **global** and apply to **all Rails projects**. Install once per machine.

### Q: Can I disable a hook?

**A:** Yes. Edit `~/.claude/settings.json` and remove or comment out the hook you want to disable.

### Q: What if a hook blocks something legitimate?

**A:** You can:
1. Temporarily uninstall hooks: `bash setup-hooks.sh --uninstall`
2. Use alternative approaches (e.g., `bin/rails credentials:edit` instead of editing files directly)
3. Edit the hook scripts to whitelist specific files
4. Contact support with examples of false positives

### Q: Can I customize the hooks?

**A:** Yes! The hook scripts are stored in `~/.claude/hooks/` and you can edit them. Common customizations:

- **block-secrets.py**: Add more file patterns to `SENSITIVE_FILES` or `SENSITIVE_PATTERNS`
- **block-dangerous-commands.sh**: Add more grep patterns for commands you want to block
- **rails-after-edit.sh**: Add more post-edit actions (e.g., run other linters)

### Q: Where's the documentation for Claude Code hooks?

**A:** See [CLAUDE_CODE_SETUP_TEMPLATE.md](CLAUDE_CODE_SETUP_TEMPLATE.md) for comprehensive documentation on hooks, including Phase 3: Security Hooks.

---

## Support

- **Issues:** Report bugs at [GitHub Issues](https://github.com/rivettidaniel/vep-rails-agents/issues)
- **Questions:** Check [CLAUDE_CODE_SETUP_TEMPLATE.md](CLAUDE_CODE_SETUP_TEMPLATE.md) Phase 3
- **Manual Setup:** See [CLAUDE_CODE_SETUP_TEMPLATE.md](CLAUDE_CODE_SETUP_TEMPLATE.md) for step-by-step instructions

---

**Built for [VEP Rails Agents](https://github.com/rivettidaniel/vep-rails-agents)**
