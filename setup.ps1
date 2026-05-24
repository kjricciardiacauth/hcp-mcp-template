# setup.ps1 — HCP MCP Worker bootstrap (Windows PowerShell)
#
# Automates Phases 3-6 of INSTALL.md (KV namespaces, secrets, first token, smoke probe)
# once the user has wrangler logged in and a Cloudflare project created (Phase 2).
#
# Usage:
#   .\setup.ps1 -ProjectName my-hcp -WorkerUrl https://my-hcp.<account>.workers.dev
#
# Prereqs:
#   - wrangler installed (`npm install -g wrangler`) and authed (`wrangler login`)
#   - Cloudflare Worker project already created in the dashboard (Phase 2 of INSTALL.md)
#   - You've cloned your fork and are running this from the repo root
#
# Reads/writes .hcp-mcp/state.json. Idempotent — re-runs skip completed phases.

param(
    [Parameter(Mandatory=$true)] [string]$ProjectName,
    [Parameter(Mandatory=$true)] [string]$WorkerUrl,
    [string]$TokenLabel = "$env:USERNAME"
)

$ErrorActionPreference = "Stop"

# ---- helpers ----------------------------------------------------------------
$stateDir  = ".hcp-mcp"
$statePath = "$stateDir\state.json"

function Read-State {
    if (Test-Path $statePath) {
        return Get-Content $statePath -Raw | ConvertFrom-Json
    }
    return @{ started_at = (Get-Date).ToString("o") }
}

function Write-State($state) {
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory $stateDir | Out-Null }
    $state | ConvertTo-Json -Depth 8 | Set-Content $statePath -Encoding UTF8
}

function Section($title) {
    Write-Host ""
    Write-Host "=== $title" -ForegroundColor Cyan
}

function Pass($msg) { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  [!]  $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "  [X]  $msg" -ForegroundColor Red; exit 1 }

# ---- preflight --------------------------------------------------------------
Section "Preflight"

try { wrangler whoami | Out-Null } catch { Fail "wrangler not authed — run 'wrangler login' first" }
Pass "wrangler authed"

if (-not $WorkerUrl.StartsWith("https://")) { Fail "WorkerUrl must start with https://" }
Pass "WorkerUrl shape OK"

$state = Read-State
$state | Add-Member -NotePropertyName preflight_ok -NotePropertyValue $true -Force
$state | Add-Member -NotePropertyName project_name -NotePropertyValue $ProjectName -Force
$state | Add-Member -NotePropertyName worker_subdomain -NotePropertyValue ($WorkerUrl -replace '^https?://','') -Force
Write-State $state

# ---- Phase 3: KV namespaces -------------------------------------------------
Section "Phase 3 — KV namespaces"

if ($state.phase_3_done) {
    Pass "Already done (skipping). State: ACTIVITY_KV=$($state.activity_kv_id), MCP_TOKENS=$($state.mcp_tokens_kv_id)"
} else {
    Write-Host "  Creating ACTIVITY_KV…"
    $aOut = wrangler kv namespace create ACTIVITY_KV --remote 2>&1 | Out-String
    if ($aOut -notmatch 'id\s*=\s*"([0-9a-f]{32})"') { Fail "Could not parse ACTIVITY_KV id from wrangler output. Raw: $aOut" }
    $activityId = $Matches[1]
    Pass "ACTIVITY_KV created: $activityId"

    Write-Host "  Creating MCP_TOKENS…"
    $mOut = wrangler kv namespace create MCP_TOKENS --remote 2>&1 | Out-String
    if ($mOut -notmatch 'id\s*=\s*"([0-9a-f]{32})"') { Fail "Could not parse MCP_TOKENS id. Raw: $mOut" }
    $tokensId = $Matches[1]
    Pass "MCP_TOKENS created: $tokensId"

    # Patch wrangler.toml — replace existing id lines under each binding
    $wt = Get-Content wrangler.toml -Raw
    $wt = $wt -replace '(?ms)(\[\[kv_namespaces\]\]\s*\r?\n\s*binding\s*=\s*"ACTIVITY_KV"\s*\r?\n\s*id\s*=\s*")[^"]*(")', "`${1}$activityId`${2}"
    $wt = $wt -replace '(?ms)(\[\[kv_namespaces\]\]\s*\r?\n\s*binding\s*=\s*"MCP_TOKENS"\s*\r?\n\s*id\s*=\s*")[^"]*(")', "`${1}$tokensId`${2}"
    Set-Content wrangler.toml $wt -Encoding UTF8 -NoNewline
    Pass "wrangler.toml patched"

    git add wrangler.toml | Out-Null
    git commit -m "Add KV namespace IDs (setup.ps1)" | Out-Null
    git push origin main | Out-Null
    Pass "Committed + pushed (Cloudflare will redeploy)"

    $state | Add-Member -NotePropertyName phase_3_done -NotePropertyValue $true -Force
    $state | Add-Member -NotePropertyName activity_kv_id -NotePropertyValue $activityId -Force
    $state | Add-Member -NotePropertyName mcp_tokens_kv_id -NotePropertyValue $tokensId -Force
    Write-State $state
}

# ---- Phase 4: HCP_API_KEY ---------------------------------------------------
Section "Phase 4 — HCP API key"

if ($state.phase_4_done) {
    Pass "Already done (skipping)"
} else {
    $existing = wrangler secret list --name $ProjectName 2>&1 | Out-String
    if ($existing -match 'HCP_API_KEY') {
        Pass "HCP_API_KEY already set (leaving alone)"
    } else {
        Write-Host ""
        Write-Host "  Get your HCP API key from: HCP admin -> My Apps -> API Keys -> Create New (full scopes)" -ForegroundColor Yellow
        $secure = Read-Host -AsSecureString "  Paste HCP API key (input hidden)"
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) | Out-Null
        if (-not $plain) { Fail "Empty key — aborting" }
        $plain | wrangler secret put HCP_API_KEY --name $ProjectName | Out-Null
        Pass "HCP_API_KEY set"
        Remove-Variable plain, secure
    }
    $state | Add-Member -NotePropertyName phase_4_done -NotePropertyValue $true -Force
    Write-State $state
}

# ---- Phase 5: wait for clean deploy + health check --------------------------
Section "Phase 5 — Verify deploy"

if ($state.phase_5_done) {
    Pass "Already done (skipping)"
} else {
    Write-Host "  Polling health endpoint (up to 2 min)…"
    $ok = $false
    for ($i = 0; $i -lt 8; $i++) {
        Start-Sleep 15
        try {
            $resp = Invoke-RestMethod -Uri "$WorkerUrl/" -Method GET -ErrorAction Stop
            if ($resp -match 'HouseCall Pro MCP Worker') { $ok = $true; break }
        } catch {}
        Write-Host "    still waiting (attempt $($i+1)/8)…"
    }
    if (-not $ok) {
        Warn "Deploy not healthy after 2 min. Check dashboard build log: https://dash.cloudflare.com/?to=/:account/workers/services/view/$ProjectName"
        Fail "Aborting — fix the deploy and re-run."
    }
    Pass "Worker live: $resp"
    $state | Add-Member -NotePropertyName phase_5_done -NotePropertyValue $true -Force
    $state | Add-Member -NotePropertyName deploy_verified_at -NotePropertyValue (Get-Date).ToString("o") -Force
    Write-State $state
}

# ---- Phase 6: mint first write-tier token -----------------------------------
Section "Phase 6 — First access token"

if ($state.phase_6_done) {
    Pass "Already done (skipping). Last 4 of existing token: $($state.token_last_4)"
    $token = $null  # not in state; user will need to refer to KV dashboard if they lost it
} else {
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $token = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""

    $value = '{"name":"' + $TokenLabel + '","tier":"write"}'
    $value | wrangler kv key put $token --namespace-id $state.mcp_tokens_kv_id --remote | Out-Null
    Pass "Token minted, label=$TokenLabel, last 4=$($token.Substring($token.Length - 4))"

    $state | Add-Member -NotePropertyName phase_6_done -NotePropertyValue $true -Force
    $state | Add-Member -NotePropertyName token_last_4 -NotePropertyValue $token.Substring($token.Length - 4) -Force
    $state | Add-Member -NotePropertyName token_label -NotePropertyValue $TokenLabel -Force
    Write-State $state
}

# ---- Smoke probe ------------------------------------------------------------
Section "Smoke probe — tools/list"

if ($token) {
    try {
        $body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        $resp = Invoke-RestMethod -Uri "$WorkerUrl/mcp?token=$token" -Method POST -ContentType "application/json" -Body $body -ErrorAction Stop
        $count = $resp.result.tools.Count
        if ($count -ge 100) { Pass "tools/list returned $count tools" }
        else { Warn "tools/list returned only $count tools (expected 104). Worker may be on an older version." }
    } catch { Fail "tools/list call failed: $_" }
} else {
    Warn "No token in memory (Phase 6 was already done in a prior run). Skipping live probe — run smoke-test.ps1 manually with your token."
}

# ---- Done -------------------------------------------------------------------
Section "Done"

Write-Host ""
Write-Host "  Your worker: $WorkerUrl/mcp?token=<your-token>" -ForegroundColor Green
if ($token) {
    Write-Host "  This run's token (copy now — won't be shown again):" -ForegroundColor Yellow
    Write-Host "    $token" -ForegroundColor White
    Write-Host ""
    Write-Host "  To revoke later:  wrangler kv key delete `"$token`" --namespace-id $($state.mcp_tokens_kv_id) --remote" -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "  Next steps (Phases 7-10 from INSTALL.md):" -ForegroundColor Cyan
Write-Host "    7. Wire the URL into your Claude Code MCP config (see templates/claude-code-mcp.json)"
Write-Host "    8. Install skill + memory: powershell -ExecutionPolicy Bypass -File templates\install-skill.ps1"
Write-Host "    9. Personalize: ask Claude to fill placeholders from list_employees + list_pipeline_statuses"
Write-Host "    10. Smoke test: .\smoke-test.ps1 -WorkerUrl $WorkerUrl -Token <your-token>"
Write-Host ""
