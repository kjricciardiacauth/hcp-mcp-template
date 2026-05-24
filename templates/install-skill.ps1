# install-skill.ps1 — Copy the HCP skill + memory drop-ins to your Claude Code config dirs.
#
# Run from the repo root:
#   powershell -ExecutionPolicy Bypass -File templates\install-skill.ps1
#
# Optional flags:
#   -MemoryDir <path>   Override memory dir (default: prompt to discover)
#   -Force              Overwrite existing files without prompting

param(
    [string]$MemoryDir = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Section($t) { Write-Host ""; Write-Host "=== $t" -ForegroundColor Cyan }
function Pass($m) { Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!]  $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "  [X]  $m" -ForegroundColor Red; exit 1 }

# Confirm we're in the repo root
$repoFiles = @("examples\claude-skill\SKILL.md", "examples\claude-memory\hcp_tool.md", "examples\claude-memory\hcp_full.md")
foreach ($f in $repoFiles) {
    if (-not (Test-Path $f)) { Fail "Not in repo root: missing $f. cd into hcp-mcp-template first." }
}

# ---- Skill install ---------------------------------------------------------
Section "Skill"

$skillDir = "$env:USERPROFILE\.claude\skills\hcp-ops"
$skillDst = "$skillDir\SKILL.md"

if (-not (Test-Path $skillDir)) { New-Item -ItemType Directory -Path $skillDir -Force | Out-Null }

if ((Test-Path $skillDst) -and -not $Force) {
    $resp = Read-Host "  $skillDst already exists. Overwrite? [y/N]"
    if ($resp -ne 'y' -and $resp -ne 'Y') { Warn "Skipped skill install"; $skipSkill = $true }
}
if (-not $skipSkill) {
    Copy-Item "examples\claude-skill\SKILL.md" $skillDst -Force
    Pass "Wrote $skillDst"
}

# ---- Memory install --------------------------------------------------------
Section "Memory"

if (-not $MemoryDir) {
    # Try the common Claude Code junction path on Windows
    $candidates = @(
        "$env:USERPROFILE\.claude\projects\C--Users-$env:USERNAME\memory",
        "$env:USERPROFILE\.claude\memory"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $MemoryDir = $c; break }
    }
    if (-not $MemoryDir) {
        Write-Host "  Could not auto-detect memory dir." -ForegroundColor Yellow
        Write-Host "  Common locations:"
        Write-Host "    $env:USERPROFILE\.claude\projects\<encoded>\memory"
        Write-Host "    $env:USERPROFILE\.claude\memory"
        $MemoryDir = Read-Host "  Enter the absolute path to your memory dir (or 'skip')"
        if ($MemoryDir -eq 'skip') { Warn "Skipped memory install"; $skipMem = $true }
    }
}

if (-not $skipMem) {
    if (-not (Test-Path $MemoryDir)) { New-Item -ItemType Directory $MemoryDir -Force | Out-Null }

    foreach ($name in @("hcp_tool.md", "hcp_full.md")) {
        $src = "examples\claude-memory\$name"
        $dst = "$MemoryDir\$name"
        if ((Test-Path $dst) -and -not $Force) {
            $resp = Read-Host "  $dst already exists. Overwrite? [y/N]"
            if ($resp -ne 'y' -and $resp -ne 'Y') { Warn "Skipped $name"; continue }
        }
        Copy-Item $src $dst -Force
        Pass "Wrote $dst"
    }
}

# ---- Done ------------------------------------------------------------------
Section "Done"

Write-Host ""
Write-Host "  Skill + memory installed. Next: personalize the placeholders." -ForegroundColor Green
Write-Host ""
Write-Host "  Ask Claude (after the MCP connection is wired):"
Write-Host "    'Run Phase 9 of INSTALL.md to personalize my HCP skill and memory.'"
Write-Host ""
Write-Host "  That kicks off:"
Write-Host "    - list_employees -> fills pro_REPLACE_ME_TECH1..5 placeholders"
Write-Host "    - list_pipeline_statuses (lead, job, estimate) -> fills kcs_<your-id> placeholders"
Write-Host "    - asks your timezone + company name for cosmetic substitutions"
Write-Host ""
