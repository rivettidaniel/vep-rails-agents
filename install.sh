#!/usr/bin/env bash
set -e

# ============================================================
#  VENEZUELAN EXECUTION PROTOCOL v1.3
#  Install script for vep-rails-agents
# ============================================================

REPO_URL="https://github.com/rivettidaniel/vep-rails-agents.git"
INSTALL_DIR="${VEP_DIR:-$HOME/.vep}"
# Target IDE directory: .claude (Claude Code) or .cursor (Cursor)
# Set via: install.sh --cursor  or  VEP_IDE=cursor install.sh
TARGET_DIR=".claude"
for arg in "$@"; do
  if [ "$arg" = "--cursor" ]; then TARGET_DIR=".cursor"; break; fi
done
if [ "${VEP_IDE:-}" = "cursor" ]; then TARGET_DIR=".cursor"; fi

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
  echo -e "  ${GREEN}[ VENEZUELAN EXECUTION PROTOCOL v1.3 ]${RESET}"
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

# ── Symlink individual .md files from src_dir into dst_dir ──
# Preserves existing real files (user content). Only touches symlinks.
# Prints "linked kept" counts to stdout; warnings go to stderr.
link_md_files() {
  local src_dir="$1"
  local dst_dir="$2"
  local linked=0
  local kept=0

  mkdir -p "$dst_dir"

  for src_file in "$src_dir"/*.md; do
    [ -f "$src_file" ] || continue
    local filename
    filename=$(basename "$src_file")
    local dst_file="$dst_dir/$filename"

    if [ -L "$dst_file" ]; then
      # Already a symlink — update only if it points somewhere else
      if [ "$(readlink "$dst_file")" = "$src_file" ]; then
        continue
      fi
      rm "$dst_file"
    elif [ -f "$dst_file" ]; then
      # Real user file — never overwrite
      echo -e "  ${DIM}  ⚠ kept existing: $filename${RESET}" >&2
      kept=$((kept + 1))
      continue
    fi

    ln -s "$src_file" "$dst_file"
    linked=$((linked + 1))
  done

  printf "%d %d" "$linked" "$kept"
}

# ── Symlink individual skill subdirs from src_dir into dst_dir ──
# Each skill lives in its own subdirectory (e.g. skills/rspec-testing/).
# Preserves existing real directories (user skills).
link_skill_subdirs() {
  local src_dir="$1"
  local dst_dir="$2"
  local linked=0
  local kept=0

  mkdir -p "$dst_dir"

  for src_skill in "$src_dir"/*/; do
    [ -d "$src_skill" ] || continue
    local skill_name
    skill_name=$(basename "$src_skill")
    local dst_skill="$dst_dir/$skill_name"

    if [ -L "$dst_skill" ]; then
      if [ "$(readlink "$dst_skill")" = "$src_skill" ]; then
        continue
      fi
      rm "$dst_skill"
    elif [ -d "$dst_skill" ]; then
      echo -e "  ${DIM}  ⚠ kept existing: $skill_name/${RESET}" >&2
      kept=$((kept + 1))
      continue
    fi

    ln -s "$src_skill" "$dst_skill"
    linked=$((linked + 1))
  done

  printf "%d %d" "$linked" "$kept"
}

# ── Link into project ────────────────────────────────────────
link_project() {
  if [ ! -d "$TARGET_DIR" ]; then
    echo ""
    echo -e "  ${DIM}No $TARGET_DIR/ directory found in current directory.${RESET}"
    echo -e "  ${DIM}Run from your Rails project root and create it first: ${BOLD}mkdir -p $TARGET_DIR${RESET}"
    echo -e "  ${DIM}Then run this script again to link VEP into it.${RESET}"
    echo ""
    return
  fi

  step "Linking VEP into $(pwd)/$TARGET_DIR/"

  # agents/, commands/, features/ — symlink individual .md files
  # This preserves any existing non-VEP files in those directories.
  for component in agents commands features; do
    local src="$INSTALL_DIR/$component"
    local dst="$TARGET_DIR/$component"
    [ -d "$src" ] || continue

    # Upgrade: old installs have a directory symlink — remove it first
    if [ -L "$dst" ]; then
      rm "$dst"
      echo -e "  ${DIM}  Converted $component: directory symlink → per-file symlinks${RESET}"
    fi

    local result linked kept
    result=$(link_md_files "$src" "$dst")
    read -r linked kept <<< "$result"
    local msg="$component"
    [ "$kept" -gt 0 ] && msg="$msg (${kept} existing files preserved)"
    ok "$msg"
  done

  # skills/ — symlink individual skill subdirectories
  local skills_src="$INSTALL_DIR/skills"
  local skills_dst="$TARGET_DIR/skills"
  if [ -d "$skills_src" ]; then
    if [ -L "$skills_dst" ]; then
      rm "$skills_dst"
      echo -e "  ${DIM}  Converted skills: directory symlink → per-skill symlinks${RESET}"
    fi

    local result linked kept
    result=$(link_skill_subdirs "$skills_src" "$skills_dst")
    read -r linked kept <<< "$result"
    local msg="skills"
    [ "$kept" -gt 0 ] && msg="$msg (${kept} existing skills preserved)"
    ok "$msg"
  fi

  # planning/ — never symlink; it's project-specific data.
  # Copy templates on first install; skip if the directory already exists.
  local plan_src="$INSTALL_DIR/planning"
  local plan_dst="$TARGET_DIR/planning"
  if [ -d "$plan_src" ]; then
    if [ -L "$plan_dst" ]; then
      # Upgrade: old installs have a planning symlink pointing to ~/.vep/planning.
      # Remove the symlink so the project gets its own real planning directory.
      rm "$plan_dst"
      echo -e "  ${DIM}  Removed shared planning symlink — run /vep-init to create project planning files${RESET}"
    elif [ ! -d "$plan_dst" ]; then
      cp -r "$plan_src" "$plan_dst"
      ok "planning/ (templates copied — run /vep-init to fill in)"
    else
      echo -e "  ${DIM}  planning/ already exists — skipping${RESET}"
    fi
  fi
}

# ── Uninstall ────────────────────────────────────────────────
uninstall_vep() {
  step "Removing VEP symlinks from $(pwd)/$TARGET_DIR/"

  for component in agents commands features; do
    local src="$INSTALL_DIR/$component"
    local dst="$TARGET_DIR/$component"

    if [ -L "$dst" ]; then
      # Old-style directory symlink
      rm "$dst"
      ok "Removed $dst (directory symlink)"
    elif [ -d "$dst" ] && [ -d "$src" ]; then
      # New-style per-file symlinks — remove only VEP-owned ones
      local removed=0
      for src_file in "$src"/*.md; do
        [ -f "$src_file" ] || continue
        local dst_file="$dst/$(basename "$src_file")"
        if [ -L "$dst_file" ]; then
          rm "$dst_file"
          removed=$((removed + 1))
        fi
      done
      [ "$removed" -gt 0 ] && ok "Removed $removed VEP symlinks from $component/"
    fi
  done

  local skills_src="$INSTALL_DIR/skills"
  local skills_dst="$TARGET_DIR/skills"
  if [ -L "$skills_dst" ]; then
    rm "$skills_dst"
    ok "Removed $skills_dst (directory symlink)"
  elif [ -d "$skills_dst" ] && [ -d "$skills_src" ]; then
    local removed=0
    for src_skill in "$skills_src"/*/; do
      [ -d "$src_skill" ] || continue
      local dst_skill="$skills_dst/$(basename "$src_skill")"
      if [ -L "$dst_skill" ]; then
        rm "$dst_skill"
        removed=$((removed + 1))
      fi
    done
    [ "$removed" -gt 0 ] && ok "Removed $removed VEP skill symlinks from skills/"
  fi

  echo -e "  ${DIM}  planning/ kept (project-specific data)${RESET}"

  echo ""
  echo -e "${BOLD}  VEP symlinks removed.${RESET}"
  echo -e "  ${DIM}To remove the global VEP installation: rm -rf $INSTALL_DIR${RESET}"
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
  if [ "$TARGET_DIR" = ".cursor" ]; then
    echo -e "  ${DIM}Cursor guide: CURSOR_SETUP.md (in the vep-rails-agents repo)${RESET}"
  fi
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
