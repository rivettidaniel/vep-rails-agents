#!/usr/bin/env bash
set -e

# ============================================================
#  CLAUDE CODE HOOKS SETUP
#  Optional global hook configuration for security & quality
# ============================================================

HOOKS_DIR="${HOME}/.claude/hooks"
SETTINGS_FILE="${HOME}/.claude/settings.json"

GREEN='\033[0;32m'
BRIGHT_GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
DIM='\033[2m'
RESET='\033[0m'
BOLD='\033[1m'

banner() {
  echo ""
  echo -e "${BRIGHT_GREEN}╔══════════════════════════════════════════════════╗${RESET}"
  echo -e "${BRIGHT_GREEN}║${RESET}  Claude Code Hooks Setup - Global Configuration  ${BRIGHT_GREEN}║${RESET}"
  echo -e "${BRIGHT_GREEN}╚══════════════════════════════════════════════════╝${RESET}"
  echo ""
}

step() {
  echo -e "${GREEN}▸${RESET} ${BOLD}$1${RESET}"
}

ok() {
  echo -e "${GREEN}✓${RESET} $1"
}

warning() {
  echo -e "${YELLOW}⚠${RESET} ${YELLOW}$1${RESET}"
}

fail() {
  echo -e "${RED}✗${RESET} $1" >&2
  exit 1
}

confirm() {
  local prompt="$1"
  local response

  while true; do
    read -p "$(echo -e ${BOLD}$prompt${RESET}) (y/n): " -n 1 -r response
    echo ""
    case $response in
      [yY]) return 0 ;;
      [nN]) return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

# ── Create hooks directory ──────────────────────────────────
create_hooks_dir() {
  step "Creating hooks directory at $HOOKS_DIR"
  mkdir -p "$HOOKS_DIR"
  ok "Hooks directory created"
}

# ── Create block-secrets.py ─────────────────────────────────
create_block_secrets() {
  step "Creating block-secrets.py hook"

  cat > "$HOOKS_DIR/block-secrets.py" << 'EOF'
#!/usr/bin/env python3
"""
PreToolUse hook to block access to sensitive Rails files.
Exit codes: 0 = allow, 1 = error, 2 = block
"""
import json
import sys
import re
from pathlib import Path

# Rails-specific sensitive files
SENSITIVE_FILES = {
    # Environment files
    '.env', '.env.local', '.env.development', '.env.test',
    '.env.production', '.env.staging',
    # Rails credentials
    'master.key', 'credentials.yml.enc',
    'development.key', 'test.key', 'production.key',
    # Kamal secrets
    'secrets',
    # SSH keys
    'id_rsa', 'id_ed25519', 'id_ecdsa',
    # Generic secrets
    'secrets.json', 'secrets.yaml', 'secrets.yml',
    # Database files
    'development.sqlite3', 'test.sqlite3', 'production.sqlite3',
}

SENSITIVE_EXTENSIONS = {
    '.pem', '.key', '.p12', '.pfx', '.jks', '.keystore'
}

SENSITIVE_PATTERNS = [
    r'\.env(\.|$)',
    r'master\.key$',
    r'credentials.*\.enc$',
    r'\.kamal/secrets$',
    r'secret', r'credential', r'private_key', r'api_key',
]

SENSITIVE_PATHS = [
    'config/master.key',
    'config/credentials.yml.enc',
    '.kamal/secrets',
]

def is_sensitive(file_path: str) -> tuple:
    """Check if file is sensitive. Returns (is_sensitive, reason)."""
    path = Path(file_path)
    path_str = str(path)

    for sensitive_path in SENSITIVE_PATHS:
        if path_str.endswith(sensitive_path):
            return True, f"Protected Rails file: {sensitive_path}"

    if path.name in SENSITIVE_FILES:
        return True, f"Sensitive filename: {path.name}"

    if path.suffix.lower() in SENSITIVE_EXTENSIONS:
        return True, f"Sensitive file type: {path.suffix}"

    path_lower = file_path.lower()
    for pattern in SENSITIVE_PATTERNS:
        if re.search(pattern, path_lower):
            return True, f"Matches sensitive pattern: {pattern}"

    return False, ""

def main():
    try:
        data = json.load(sys.stdin)
        tool_input = data.get('tool_input', {})
        file_path = tool_input.get('file_path', '')

        if file_path:
            sensitive, reason = is_sensitive(file_path)
            if sensitive:
                print(f"BLOCKED: {reason}", file=sys.stderr)
                print(f"File: {file_path}", file=sys.stderr)
                print("", file=sys.stderr)
                print("For secrets, use:", file=sys.stderr)
                print("  - bin/rails credentials:edit", file=sys.stderr)
                print("  - Environment variables via .env.example", file=sys.stderr)
                sys.exit(2)

        sys.exit(0)

    except json.JSONDecodeError:
        print("Hook error: Invalid JSON input", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Hook error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
EOF

  chmod +x "$HOOKS_DIR/block-secrets.py"
  ok "Created block-secrets.py"
}

# ── Create block-dangerous-commands.sh ───────────────────────
create_block_dangerous() {
  step "Creating block-dangerous-commands.sh hook"

  cat > "$HOOKS_DIR/block-dangerous-commands.sh" << 'EOF'
#!/bin/bash
#
# PreToolUse hook to block dangerous bash commands.
# Exit codes: 0 = allow, 1 = error, 2 = block
#

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('tool_input', {}).get('command', ''))" 2>/dev/null)

if [ -z "$COMMAND" ]; then
    exit 0
fi

# Block destructive rm commands
if echo "$COMMAND" | grep -qE 'rm\s+(-rf|-fr|-r\s+-f|-f\s+-r)\s+(/|~|\.\.|/\*|~/\*)'; then
    echo "BLOCKED: Destructive rm command" >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# Block force push to protected branches
if echo "$COMMAND" | grep -qE 'git\s+push\s+.*--force.*\s*(main|master|production|staging)'; then
    echo "BLOCKED: Force push to protected branch" >&2
    echo "Use a feature branch and create a PR instead." >&2
    exit 2
fi

# Block chmod 777
if echo "$COMMAND" | grep -qE 'chmod\s+777'; then
    echo "BLOCKED: chmod 777 makes files world-writable" >&2
    echo "Use restrictive permissions: 755 for dirs, 644 for files." >&2
    exit 2
fi

# Block piping curl/wget to shell
if echo "$COMMAND" | grep -qE '(curl|wget).*\|\s*(bash|sh|zsh|ruby)'; then
    echo "BLOCKED: Piping remote content to shell" >&2
    echo "Download first, review, then execute." >&2
    exit 2
fi

# Block dangerous database commands in production
if echo "$COMMAND" | grep -qE 'rails\s+(db:drop|db:reset).*production'; then
    echo "BLOCKED: Destructive database command in production" >&2
    exit 2
fi

# Block reading .env files via shell
if echo "$COMMAND" | grep -qE '(cat|less|more|head|tail|vim|nano)\s+.*\.env'; then
    echo "BLOCKED: Reading .env file via shell" >&2
    echo "Use .env.example for templates." >&2
    exit 2
fi

# Block exposing master.key
if echo "$COMMAND" | grep -qE '(cat|less|more|head|tail)\s+.*master\.key'; then
    echo "BLOCKED: Exposing Rails master key" >&2
    exit 2
fi

exit 0
EOF

  chmod +x "$HOOKS_DIR/block-dangerous-commands.sh"
  ok "Created block-dangerous-commands.sh"
}

# ── Create rails-after-edit.sh ──────────────────────────────
create_rails_after_edit() {
  step "Creating rails-after-edit.sh hook (optional)"

  cat > "$HOOKS_DIR/rails-after-edit.sh" << 'EOF'
#!/bin/bash
#
# PostToolUse hook to run after file edits.
# Runs RuboCop on edited Ruby files.
#

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('tool_input', {}).get('file_path', ''))" 2>/dev/null)

if [[ "$FILE_PATH" == *.rb ]]; then
    if command -v rubocop &> /dev/null; then
        rubocop "$FILE_PATH" --format simple 2>/dev/null || true
    fi
fi

exit 0
EOF

  chmod +x "$HOOKS_DIR/rails-after-edit.sh"
  ok "Created rails-after-edit.sh"
}

# ── Create settings.json ────────────────────────────────────
create_settings_json() {
  step "Creating settings.json configuration"

  # Check if settings.json already exists
  if [ -f "$SETTINGS_FILE" ]; then
    warning "settings.json already exists at $SETTINGS_FILE"
    if ! confirm "Overwrite existing settings.json?"; then
      warning "Skipping settings.json creation"
      return
    fi
  fi

  cat > "$SETTINGS_FILE" << 'EOF'
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
      "Read(.env.*)",
      "Read(config/master.key)",
      "Read(.kamal/secrets)",
      "Bash(rm -rf /)",
      "Bash(rm -rf ~)",
      "Bash(rm -rf ..)"
    ]
  }
}
EOF

  ok "Created settings.json"
}

# ── Test hooks ──────────────────────────────────────────────
test_hooks() {
  step "Testing hooks configuration"

  # Check if Python hook is executable
  if [ -x "$HOOKS_DIR/block-secrets.py" ]; then
    ok "block-secrets.py is executable"
  else
    warning "block-secrets.py is not executable"
  fi

  # Check if Bash hook is executable
  if [ -x "$HOOKS_DIR/block-dangerous-commands.sh" ]; then
    ok "block-dangerous-commands.sh is executable"
  else
    warning "block-dangerous-commands.sh is not executable"
  fi

  # Check if settings.json is valid JSON
  if command -v jq &> /dev/null; then
    if jq empty "$SETTINGS_FILE" 2>/dev/null; then
      ok "settings.json is valid JSON"
    else
      fail "settings.json is not valid JSON"
    fi
  else
    warning "jq not found, skipping JSON validation"
  fi
}

# ── Display setup summary ───────────────────────────────────
show_summary() {
  echo ""
  echo -e "${BRIGHT_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}Setup Complete!${RESET}"
  echo -e "${BRIGHT_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
  echo "Hooks installed at:"
  echo -e "  ${DIM}$HOOKS_DIR/${RESET}"
  echo ""
  echo "Configuration file:"
  echo -e "  ${DIM}$SETTINGS_FILE${RESET}"
  echo ""
  echo -e "${BOLD}Protections enabled:${RESET}"
  echo "  ✓ Block access to .env files (Read/Edit/Write)"
  echo "  ✓ Block dangerous bash commands (rm -rf, force push, etc.)"
  echo "  ✓ Auto-run RuboCop on Ruby file edits (optional)"
  echo ""
  echo -e "${BOLD}All Rails projects using Claude Code will now:${RESET}"
  echo "  • Prevent accidental exposure of secrets"
  echo "  • Block destructive operations"
  echo "  • Enforce code style automatically"
  echo ""
  echo -e "${DIM}Note: These hooks are GLOBAL and apply to all projects${RESET}"
  echo -e "${DIM}You can modify $SETTINGS_FILE anytime${RESET}"
  echo ""
}

# ── Uninstall mode ──────────────────────────────────────────
uninstall() {
  step "Removing hook configuration"

  if [ -d "$HOOKS_DIR" ]; then
    rm -rf "$HOOKS_DIR"
    ok "Removed $HOOKS_DIR"
  fi

  if [ -f "$SETTINGS_FILE" ]; then
    backup="$SETTINGS_FILE.backup.$(date +%s)"
    mv "$SETTINGS_FILE" "$backup"
    warning "Backed up $SETTINGS_FILE to $backup"
  fi

  echo ""
  echo -e "${BOLD}Hooks uninstalled.${RESET}"
  echo ""
}

# ── Main ────────────────────────────────────────────────────
main() {
  banner

  # Check for uninstall flag
  if [ "${1:-}" = "--uninstall" ]; then
    uninstall
    exit 0
  fi

  # Check for help flag
  if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  (none)          Install hooks interactively"
    echo "  --uninstall     Remove all hooks configuration"
    echo "  --help, -h      Show this help message"
    echo ""
    exit 0
  fi

  # Welcome message
  echo -e "${BOLD}This script sets up global Claude Code hooks for Rails security.${RESET}"
  echo ""
  echo "Hooks are stored in: ${DIM}~/.claude/hooks/${RESET}"
  echo "Configuration in:    ${DIM}~/.claude/settings.json${RESET}"
  echo ""
  echo -e "${YELLOW}These hooks will apply to ALL Rails projects on this machine.${RESET}"
  echo ""

  if ! confirm "Do you want to proceed?"; then
    echo "Setup cancelled."
    exit 0
  fi

  echo ""

  # Confirm each hook
  create_hooks_dir
  echo ""

  if confirm "Install block-secrets.py (prevent reading .env, master.key, etc)?"; then
    create_block_secrets
  else
    warning "Skipped block-secrets.py"
  fi

  echo ""

  if confirm "Install block-dangerous-commands.sh (prevent rm -rf, force push, etc)?"; then
    create_block_dangerous
  else
    warning "Skipped block-dangerous-commands.sh"
  fi

  echo ""

  if confirm "Install rails-after-edit.sh (auto-run RuboCop on edits - optional)?"; then
    create_rails_after_edit
  else
    warning "Skipped rails-after-edit.sh"
  fi

  echo ""

  # Create settings.json with selected hooks
  create_settings_json

  echo ""

  # Test hooks
  test_hooks

  echo ""

  # Show summary
  show_summary
}

main "$@"
