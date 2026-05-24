#!/usr/bin/env bash
# install-skill.sh — Copy the HCP skill + memory drop-ins to your Claude Code config dirs.
#
# Run from the repo root:
#   bash templates/install-skill.sh
#
# Optional flags:
#   --memory-dir <path>  Override memory dir
#   --force              Overwrite existing files without prompting

set -euo pipefail

MEMORY_DIR=""
FORCE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --memory-dir) MEMORY_DIR="$2"; shift 2 ;;
        --force) FORCE=true; shift ;;
        -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

section() { printf '\n\033[36m=== %s\033[0m\n' "$1"; }
pass()    { printf '  \033[32m[OK]\033[0m %s\n' "$1"; }
warn()    { printf '  \033[33m[!]\033[0m  %s\n' "$1"; }
fail()    { printf '  \033[31m[X]\033[0m  %s\n' "$1"; exit 1; }

# Confirm we're in the repo root
for f in examples/claude-skill/SKILL.md examples/claude-memory/hcp_tool.md examples/claude-memory/hcp_full.md; do
    [[ -f "$f" ]] || fail "Not in repo root: missing $f. cd into hcp-mcp-template first."
done

copy_with_confirm() {
    local src="$1" dst="$2"
    if [[ -f "$dst" && "$FORCE" != "true" ]]; then
        read -r -p "  $dst already exists. Overwrite? [y/N] " resp
        if [[ "$resp" != "y" && "$resp" != "Y" ]]; then warn "Skipped $dst"; return; fi
    fi
    mkdir -p "$(dirname "$dst")"
    cp -f "$src" "$dst"
    pass "Wrote $dst"
}

# ---- Skill install ---------------------------------------------------------
section "Skill"

SKILL_DST="$HOME/.claude/skills/hcp-ops/SKILL.md"
copy_with_confirm examples/claude-skill/SKILL.md "$SKILL_DST"

# ---- Memory install --------------------------------------------------------
section "Memory"

if [[ -z "$MEMORY_DIR" ]]; then
    # Try common locations
    for c in "$HOME/.claude/projects"/*/memory "$HOME/.claude/memory"; do
        if [[ -d "$c" ]]; then MEMORY_DIR="$c"; break; fi
    done
    if [[ -z "$MEMORY_DIR" ]]; then
        echo "  Could not auto-detect memory dir."
        echo "  Common locations:"
        echo "    \$HOME/.claude/projects/<encoded>/memory"
        echo "    \$HOME/.claude/memory"
        read -r -p "  Enter the absolute path to your memory dir (or 'skip'): " MEMORY_DIR
        if [[ "$MEMORY_DIR" == "skip" ]]; then warn "Skipped memory install"; MEMORY_DIR=""; fi
    fi
fi

if [[ -n "$MEMORY_DIR" ]]; then
    for name in hcp_tool.md hcp_full.md; do
        copy_with_confirm "examples/claude-memory/$name" "$MEMORY_DIR/$name"
    done
fi

# ---- Done ------------------------------------------------------------------
section "Done"

echo ""
printf '  \033[32mSkill + memory installed. Next: personalize the placeholders.\033[0m\n'
echo ""
echo "  Ask Claude (after the MCP connection is wired):"
echo "    'Run Phase 9 of INSTALL.md to personalize my HCP skill and memory.'"
echo ""
echo "  That kicks off:"
echo "    - list_employees -> fills pro_REPLACE_ME_TECH1..5 placeholders"
echo "    - list_pipeline_statuses (lead, job, estimate) -> fills kcs_<your-id> placeholders"
echo "    - asks your timezone + company name for cosmetic substitutions"
echo ""
