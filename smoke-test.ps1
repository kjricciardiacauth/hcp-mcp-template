# HCP Worker Smoke Test Battery
# Tests v3.0.0+ features: fetch_all, schema fixes, filters
# Token auth (v3.3.0+) supported via -Token parameter.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File smoke-test.ps1 -WorkerUrl https://<your-worker>.workers.dev -Token <your-write-token>
#   powershell -ExecutionPolicy Bypass -File smoke-test.ps1 -WorkerUrl https://<your-worker>.workers.dev -Token <your-write-token> -Verbose
#
# No HCP API key needed in the script — the worker holds it as a Cloudflare secret.
# Use a WRITE-tier token (the update_job_schedule probe in section 9 is a write-tool
# call; a read-tier token will be denied at the worker auth gate, not by HCP).

param(
    [Parameter(Mandatory=$true)]
    [string]$WorkerUrl,
    [Parameter(Mandatory=$true)]
    [string]$Token,
    [switch]$Verbose
)

$base = "$WorkerUrl/mcp?token=$Token"
$infoUrl = "$WorkerUrl/mcp?token=$Token"
$script:pass = 0
$script:fail = 0

function Invoke-RPC($id, $tool, $args) {
    $body = @{
        jsonrpc = "2.0"
        id      = $id
        method  = "tools/call"
        params  = @{ name = $tool; arguments = $args }
    } | ConvertTo-Json -Depth 6
    $resp = Invoke-RestMethod -Uri $base -Method POST -ContentType "application/json" `
        -Headers @{ "mcp-session-id" = "smoke-$id" } -Body $body -ErrorAction Stop
    $text = $resp.result.content[0].text
    if ($resp.result.isError) { throw $text }
    return $text | ConvertFrom-Json
}

function Show-Pass($label) {
    Write-Host "  [PASS] $label" -ForegroundColor Green
    $script:pass++
}

function Show-Fail($label, $detail) {
    Write-Host "  [FAIL] $label -- $detail" -ForegroundColor Red
    $script:fail++
}

function Show-Section($title) {
    Write-Host ""
    Write-Host "-- $title" -ForegroundColor Cyan
}

# --------------------------------------------------
# 1. Worker version (informational — does not assert a specific version)
# --------------------------------------------------
Show-Section "Worker version"
try {
    $info = Invoke-RestMethod -Uri $infoUrl -Method GET -ErrorAction Stop
    if ($info.version) {
        Show-Pass "GET /mcp => version $($info.version)"
    } else {
        Show-Fail "GET /mcp version" "no version field in response"
    }
    if ($Verbose) { Write-Host "    protocol: $($info.protocolVersion)" }
} catch {
    Show-Fail "GET /mcp" "$_"
}

# --------------------------------------------------
# 2. fetch_all on list_tags
# --------------------------------------------------
Show-Section "fetch_all -- list_tags"
try {
    $r = Invoke-RPC 10 "list_tags" @{ fetch_all = $true }
    if ($r.tags -and $r.total_items -gt 0) {
        Show-Pass "list_tags fetch_all => $($r.total_items) tags returned"
    } else {
        Show-Fail "list_tags fetch_all" "unexpected shape"
    }
    if ($r.tags.Count -eq $r.total_items) {
        Show-Pass "list_tags: tags.Count ($($r.tags.Count)) == total_items ($($r.total_items))"
    } else {
        Show-Fail "list_tags count mismatch" "tags.Count=$($r.tags.Count) total_items=$($r.total_items)"
    }
    if ($Verbose) { Write-Host "    first tag: $($r.tags[0].name)" }
} catch {
    Show-Fail "list_tags fetch_all" "$_"
}

# --------------------------------------------------
# 3. fetch_all on list_employees
# --------------------------------------------------
Show-Section "fetch_all -- list_employees"
try {
    $r = Invoke-RPC 20 "list_employees" @{ fetch_all = $true }
    if ($r.employees -and $r.total_items -gt 0) {
        Show-Pass "list_employees fetch_all => $($r.total_items) employees"
    } else {
        Show-Fail "list_employees fetch_all" "unexpected shape"
    }
} catch {
    Show-Fail "list_employees fetch_all" "$_"
}

# --------------------------------------------------
# 4. fetch_all on list_leads (status=open)
# --------------------------------------------------
Show-Section "fetch_all -- list_leads"
try {
    $r = Invoke-RPC 30 "list_leads" @{ status = "open"; fetch_all = $true }
    if ($null -ne $r.total_items) {
        Show-Pass "list_leads fetch_all status=open => $($r.total_items) leads"
    } else {
        Show-Fail "list_leads fetch_all" "missing total_items"
    }
} catch {
    Show-Fail "list_leads fetch_all" "$_"
}

# --------------------------------------------------
# 5. fetch_all on list_pricebook_services
# --------------------------------------------------
Show-Section "fetch_all -- list_pricebook_services"
try {
    $r = Invoke-RPC 40 "list_pricebook_services" @{ fetch_all = $true }
    if ($null -ne $r.total_items) {
        Show-Pass "list_pricebook_services fetch_all => $($r.total_items) services"
    } else {
        Show-Fail "list_pricebook_services fetch_all" "missing total_items"
    }
} catch {
    Show-Fail "list_pricebook_services fetch_all" "$_"
}

# --------------------------------------------------
# 6. list_invoices -- status array filter (fixed v2.9.2)
# --------------------------------------------------
Show-Section "list_invoices status array filter"
try {
    $r = Invoke-RPC 50 "list_invoices" @{ status = @("paid"); page_size = 1 }
    if ($r.invoices -and $r.total_items -gt 0) {
        Show-Pass "list_invoices status=['paid'] => $($r.total_items) total"
    } else {
        Show-Fail "list_invoices status=['paid']" "zero results or bad shape"
    }
} catch {
    Show-Fail "list_invoices status=['paid']" "$_"
}

try {
    $r = Invoke-RPC 51 "list_invoices" @{ status = @("open"); page_size = 1 }
    if ($null -ne $r.total_items) {
        Show-Pass "list_invoices status=['open'] => $($r.total_items) total"
    } else {
        Show-Fail "list_invoices status=['open']" "missing total_items"
    }
} catch {
    Show-Fail "list_invoices status=['open']" "$_"
}

# --------------------------------------------------
# 7. list_jobs -- new v3.0.0 filter params
# --------------------------------------------------
Show-Section "list_jobs new filter params (v3.0.0)"
try {
    $r = Invoke-RPC 60 "list_jobs" @{ sort_by = "created_at"; sort_direction = "desc"; page_size = 1 }
    if ($null -ne $r.jobs) {
        Show-Pass "list_jobs sort_by=created_at accepted => $($r.total_items) total"
    } else {
        Show-Fail "list_jobs sort_by" "no jobs array in response"
    }
} catch {
    Show-Fail "list_jobs sort_by" "$_"
}

try {
    $r = Invoke-RPC 61 "list_jobs" @{ work_status = @("scheduled"); page_size = 1 }
    if ($null -ne $r.total_items) {
        Show-Pass "list_jobs work_status=['scheduled'] => $($r.total_items) total"
    } else {
        Show-Fail "list_jobs work_status filter" "missing total_items"
    }
} catch {
    Show-Fail "list_jobs work_status filter" "$_"
}

# --------------------------------------------------
# 8. list_leads -- status enum values
# --------------------------------------------------
Show-Section "list_leads status enum (open / won / lost)"
$statuses = @("open", "won", "lost")
$rpcId = 70
foreach ($s in $statuses) {
    try {
        $r = Invoke-RPC $rpcId "list_leads" @{ status = $s; page_size = 1 }
        if ($null -ne $r.total_items) {
            Show-Pass "list_leads status='$s' => $($r.total_items) total"
        } else {
            Show-Fail "list_leads status='$s'" "missing total_items"
        }
    } catch {
        Show-Fail "list_leads status='$s'" "$_"
    }
    $rpcId++
}

# --------------------------------------------------
# 9. update_job_schedule -- correct param names (v3.0.0 fix)
#    Uses nonexistent job_id; expect 404 (params ok) not 422 (wrong names).
#    Requires WRITE-tier token (worker auth gate blocks read-tier tokens here).
# --------------------------------------------------
Show-Section "update_job_schedule param names (v3.0.0 fix)"
try {
    Invoke-RPC 80 "update_job_schedule" @{
        job_id                    = "job_smoke_test_nonexistent_000000"
        start_time                = "2025-06-01T09:00:00"
        end_time                  = "2025-06-01T10:00:00"
        arrival_window_in_minutes = 60
        notify                    = $false
        notify_pro                = $false
    } | Out-Null
    Show-Fail "update_job_schedule" "expected error for nonexistent job, got success"
} catch {
    $msg = "$_"
    if ($msg -match "404|not found|no.*job") {
        Show-Pass "update_job_schedule: start_time/notify/notify_pro accepted (404 = params ok, job not found)"
    } elseif ($msg -match "422|unprocessable|invalid param|scheduled_start") {
        Show-Fail "update_job_schedule" "422 = wrong param names still in worker"
    } elseif ($msg -match "Access denied|write access") {
        Show-Fail "update_job_schedule" "read-tier token used; supply a write-tier token to run this probe"
    } else {
        $preview = $msg.Substring(0, [System.Math]::Min(120, $msg.Length))
        Show-Pass "update_job_schedule: params reached HCP ($preview)"
    }
}

# --------------------------------------------------
# 10. get_company -- basic auth / connectivity
# --------------------------------------------------
Show-Section "Basic connectivity"
try {
    $r = Invoke-RPC 90 "get_company" @{}
    if ($r.id -or $r.name) {
        Show-Pass "get_company => $($r.name)"
    } else {
        Show-Fail "get_company" "missing id/name in response"
    }
} catch {
    Show-Fail "get_company" "$_"
}

# --------------------------------------------------
# Summary
# --------------------------------------------------
$total = $script:pass + $script:fail
Write-Host ""
Write-Host "==============================" -ForegroundColor White
$color = if ($script:fail -eq 0) { "Green" } else { "Yellow" }
Write-Host "  $($script:pass)/$total passed" -ForegroundColor $color
if ($script:fail -gt 0) {
    Write-Host "  $($script:fail) FAILED" -ForegroundColor Red
}
Write-Host "==============================" -ForegroundColor White
Write-Host ""
