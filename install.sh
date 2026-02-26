#!/usr/bin/env bash
set -e

# ============================================================
#  VENEZUELAN EXECUTION PROTOCOL v1.1
#  Install script for vep-rails-agents
# ============================================================

REPO_URL="https://github.com/rivettidaniel/vep-rails-agents.git"
INSTALL_DIR="${VEP_DIR:-$HOME/.vep}"
CLAUDE_DIR=".claude"

GREEN='\033[0;32m'
BRIGHT_GREEN='\033[1;32m'
DIM='\033[2m'
RESET='\033[0m'
BOLD='\033[1m'

banner() {
  echo ""
  echo -e "${BRIGHT_GREEN}"
  echo "  ██╗   ██╗███████╗██████╗ "
  echo "  ██║   ██║██╔════╝██╔══██╗"
  echo "  ╚██╗ ██╔╝█████╗  ██████╔╝"
  echo "   ╚████╔╝ ██╔══╝  ██╔═══╝ "
  echo "    ╚██╔╝  ███████╗██║     "
  echo "     ╚═╝   ╚══════╝╚═╝     "
  echo ""
  echo -e "  ${GREEN}[ VENEZUELAN EXECUTION PROTOCOL v1.1 ]${RESET}"
  echo ""
}

step() {
  echo -e "${GREEN}▸${RESET} ${BOLD}$1${RESET}"
}

ok() {
  echo -e "${GREEN}✓${RESET} $1"
}

fail() {
  echo -e "\033[0;31m✗${RESET} $1" >&2
  exit 1
}

# ── Check dependencies ──────────────────────────────────────
check_deps() {
  command -v git >/dev/null 2>&1 || fail "git is required but not installed."
}

# ── Clone or update repo ────────────────────────────────────
install_vep() {
  step "Installing VEP to $INSTALL_DIR"

  if [ -d "$INSTALL_DIR/.git" ]; then
    echo -e "  ${DIM}Existing installation found, updating...${RESET}"
    git -C "$INSTALL_DIR" pull --quiet --ff-only
    ok "Updated to latest version"
  else
    git clone --depth=1 --quiet "$REPO_URL" "$INSTALL_DIR"
    ok "Cloned vep-rails-agents to $INSTALL_DIR"
  fi
}

# ── Link into project ────────────────────────────────────────
link_project() {
  if [ ! -d "$CLAUDE_DIR" ]; then
    echo ""
    echo -e "  ${DIM}No .claude/ directory found in current directory.${RESET}"
    echo -e "  ${DIM}Run from your Rails project root to link VEP into it.${RESET}"
    echo ""
    return
  fi

  step "Linking VEP into $(pwd)/$CLAUDE_DIR/"

  COMPONENTS=("agents" "commands" "skills" "features" "planning")

  for component in "${COMPONENTS[@]}"; do
    target="$CLAUDE_DIR/$component"
    source="$INSTALL_DIR/$component"

    if [ -L "$target" ]; then
      rm "$target"
    fi

    if [ -d "$source" ]; then
      ln -s "$source" "$target"
      ok "Linked $component"
    fi
  done
}

# ── Uninstall ────────────────────────────────────────────────
uninstall_vep() {
  step "Removing VEP symlinks from $(pwd)/$CLAUDE_DIR/"

  COMPONENTS=("agents" "commands" "skills" "features" "planning")

  for component in "${COMPONENTS[@]}"; do
    target="$CLAUDE_DIR/$component"
    if [ -L "$target" ]; then
      rm "$target"
      ok "Removed $target"
    fi
  done

  step "Removing VEP from $INSTALL_DIR"
  if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    ok "Removed $INSTALL_DIR"
  else
    echo -e "  ${DIM}$INSTALL_DIR not found, skipping.${RESET}"
  fi

  echo ""
  echo -e "${BOLD}  VEP uninstalled.${RESET}"
  echo ""
}

# ── Print next steps ─────────────────────────────────────────
next_steps() {
  echo ""
  echo -e "${BRIGHT_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}  VEP installed successfully. Now execute:${RESET}"
  echo ""
  echo -e "  ${GREEN}/vep-init${RESET}      initialize project planning files"
  echo -e "  ${GREEN}/vep-feature${RESET}   spec + review + generate PHASE_PLAN"
  echo -e "  ${GREEN}/vep-wave 1${RESET}    run RED phase (failing tests)"
  echo -e "  ${GREEN}/vep-state${RESET}     save session state"
  echo ""
  echo -e "  ${DIM}Full docs: https://github.com/rivettidaniel/vep-rails-agents${RESET}"
  echo -e "${BRIGHT_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
}

# ── Main ─────────────────────────────────────────────────────
main() {
  if [ "${1:-}" = "--uninstall" ]; then
    banner
    uninstall_vep
  else
    banner
    check_deps
    install_vep
    link_project
    next_steps
  fi
}

main "$@"
