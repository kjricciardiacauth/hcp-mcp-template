#!/usr/bin/env bash
# setup.sh — HCP MCP Worker bootstrap (macOS / Linux)
#
# Automates Phases 3-6 of INSTALL.md (KV namespaces, secrets, first token, smoke probe)
# once the user has wrangler logged in and a Cloudflare project created (Phase 2).
#
# Usage:
#   ./setup.sh --project my-hcp --url https://my-hcp.<account>.workers.dev [--label "your name"]
#
# Prereqs:
#   - wrangler installed (npm install -g wrangler) and authed (wrangler login)
#   - Cloudflare Worker project already created in the dashboard (Phase 2 of INSTALL.md)
#   - jq, curl, openssl in PATH
#   - You've cloned your fork and are running this from the repo root
#
# Reads/writes .hcp-mcp/state.json. Idempotent — re-runs skip completed phases.

set -euo pipefail

# ---- arg parsing ------------------------------------------------------------
PROJECT_NAME=""
WORKER_URL=""
TOKEN_LABEL="${USER:-user}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project) PROJECT_NAME="$2"; shift 2 ;;
        --url) WORKER_URL="$2"; shift 2 ;;
        --label) TOKEN_LABEL="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

if [[ -z "$PROJECT_NAME" || -z "$WORKER_URL" ]]; then
    echo "Usage: $0 --project <name> --url <https://...> [--label <name>]"
    exit 1
fi

# ---- helpers ----------------------------------------------------------------
STATE_DIR=".hcp-mcp"
STATE_PATH="$STATE_DIR/state.json"

ensure_state() {
    mkdir -p "$STATE_DIR"
    if [[ ! -f "$STATE_PATH" ]]; then
        echo "{\"started_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "$STATE_PATH"
    fi
}

state_get() { jq -r ".${1} // empty" "$STATE_PATH"; }

state_set() {
    local key="$1" val="$2"
    local tmp; tmp=$(mktemp)
    jq --arg k "$key" --arg v "$val" '.[$k] = $v' "$STATE_PATH" > "$tmp" && mv "$tmp" "$STATE_PATH"
}

state_set_bool() {
    local key="$1" val="$2"
    local tmp; tmp=$(mktemp)
    jq --arg k "$key" --argjson v "$val" '.[$k] = $v' "$STATE_PATH" > "$tmp" && mv "$tmp" "$STATE_PATH"
}

section() { printf '\n\033[36m=== %s\033[0m\n' "$1"; }
pass()    { printf '  \033[32m[OK]\033[0m %s\n' "$1"; }
warn()    { printf '  \033[33m[!]\033[0m  %s\n' "$1"; }
fail()    { printf '  \033[31m[X]\033[0m  %s\n' "$1"; exit 1; }

# ---- preflight --------------------------------------------------------------
section "Preflight"

command -v wrangler >/dev/null || fail "wrangler not in PATH (npm install -g wrangler)"
command -v jq       >/dev/null || fail "jq not in PATH (brew install jq / apt install jq)"
command -v curl     >/dev/null || fail "curl not in PATH"
command -v openssl  >/dev/null || fail "openssl not in PATH"
wrangler whoami >/dev/null 2>&1 || fail "wrangler not authed — run 'wrangler login'"
pass "wrangler authed; tooling present"

[[ "$WORKER_URL" == https://* ]] || fail "--url must start with https://"
pass "WorkerUrl shape OK"

ensure_state
state_set_bool preflight_ok true
state_set project_name "$PROJECT_NAME"
state_set worker_subdomain "${WORKER_URL#https://}"

# ---- Phase 3: KV namespaces -------------------------------------------------
section "Phase 3 — KV namespaces"

if [[ "$(state_get phase_3_done)" == "true" ]]; then
    pass "Already done (skipping). ACTIVITY_KV=$(state_get activity_kv_id) MCP_TOKENS=$(state_get mcp_tokens_kv_id)"
else
    echo "  Creating ACTIVITY_KV…"
    a_out=$(wrangler kv namespace create ACTIVITY_KV --remote 2>&1)
    activity_id=$(echo "$a_out" | grep -oE 'id\s*=\s*"[0-9a-f]{32}"' | head -1 | grep -oE '[0-9a-f]{32}')
    [[ -n "$activity_id" ]] || fail "Could not parse ACTIVITY_KV id. Raw: $a_out"
    pass "ACTIVITY_KV created: $activity_id"

    echo "  Creating MCP_TOKENS…"
    m_out=$(wrangler kv namespace create MCP_TOKENS --remote 2>&1)
    tokens_id=$(echo "$m_out" | grep -oE 'id\s*=\s*"[0-9a-f]{32}"' | head -1 | grep -oE '[0-9a-f]{32}')
    [[ -n "$tokens_id" ]] || fail "Could not parse MCP_TOKENS id. Raw: $m_out"
    pass "MCP_TOKENS created: $tokens_id"

    # Patch wrangler.toml using Python (more reliable than sed across mac/Linux for multi-line)
    python3 - "$activity_id" "$tokens_id" <<'PY'
import re, sys
a, t = sys.argv[1], sys.argv[2]
with open("wrangler.toml") as f:
    wt = f.read()
wt = re.sub(
    r'(\[\[kv_namespaces\]\]\s*\n\s*binding\s*=\s*"ACTIVITY_KV"\s*\n\s*id\s*=\s*")[^"]*(")',
    rf'\g<1>{a}\g<2>', wt, flags=re.M
)
wt = re.sub(
    r'(\[\[kv_namespaces\]\]\s*\n\s*binding\s*=\s*"MCP_TOKENS"\s*\n\s*id\s*=\s*")[^"]*(")',
    rf'\g<1>{t}\g<2>', wt, flags=re.M
)
with open("wrangler.toml", "w") as f:
    f.write(wt)
PY
    pass "wrangler.toml patched"

    git add wrangler.toml
    git commit -m "Add KV namespace IDs (setup.sh)" >/dev/null
    git push origin main >/dev/null
    pass "Committed + pushed (Cloudflare will redeploy)"

    state_set_bool phase_3_done true
    state_set activity_kv_id "$activity_id"
    state_set mcp_tokens_kv_id "$tokens_id"
fi

# ---- Phase 4: HCP_API_KEY ---------------------------------------------------
section "Phase 4 — HCP API key"

if [[ "$(state_get phase_4_done)" == "true" ]]; then
    pass "Already done (skipping)"
else
    if wrangler secret list --name "$PROJECT_NAME" 2>&1 | grep -q HCP_API_KEY; then
        pass "HCP_API_KEY already set (leaving alone)"
    else
        echo ""
        echo "  Get your HCP API key from: HCP admin -> My Apps -> API Keys -> Create New (full scopes)"
        read -rsp "  Paste HCP API key (input hidden): " HCP_KEY
        echo ""
        [[ -n "$HCP_KEY" ]] || fail "Empty key — aborting"
        echo "$HCP_KEY" | wrangler secret put HCP_API_KEY --name "$PROJECT_NAME" >/dev/null
        unset HCP_KEY
        pass "HCP_API_KEY set"
    fi
    state_set_bool phase_4_done true
fi

# ---- Phase 5: wait for clean deploy + health check --------------------------
section "Phase 5 — Verify deploy"

if [[ "$(state_get phase_5_done)" == "true" ]]; then
    pass "Already done (skipping)"
else
    echo "  Polling health endpoint (up to 2 min)…"
    ok=false
    health=""
    for i in {1..8}; do
        sleep 15
        if health=$(curl -fsS "$WORKER_URL/" 2>/dev/null) && [[ "$health" == *"HouseCall Pro MCP Worker"* ]]; then
            ok=true; break
        fi
        echo "    still waiting (attempt $i/8)…"
    done
    [[ "$ok" == "true" ]] || fail "Deploy not healthy after 2 min. Check the dashboard build log."
    pass "Worker live: $health"
    state_set_bool phase_5_done true
    state_set deploy_verified_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi

# ---- Phase 6: mint first write-tier token -----------------------------------
section "Phase 6 — First access token"

TOKEN=""
if [[ "$(state_get phase_6_done)" == "true" ]]; then
    pass "Already done (skipping). Last 4 of existing token: $(state_get token_last_4)"
else
    TOKEN=$(openssl rand -hex 32)
    KV_ID=$(state_get mcp_tokens_kv_id)
    echo "{\"name\":\"$TOKEN_LABEL\",\"tier\":\"write\"}" | wrangler kv key put "$TOKEN" --namespace-id "$KV_ID" --remote >/dev/null
    last4="${TOKEN: -4}"
    pass "Token minted, label=$TOKEN_LABEL, last 4=$last4"

    state_set_bool phase_6_done true
    state_set token_last_4 "$last4"
    state_set token_label "$TOKEN_LABEL"
fi

# ---- Smoke probe ------------------------------------------------------------
section "Smoke probe — tools/list"

if [[ -n "$TOKEN" ]]; then
    resp=$(curl -fsS -X POST "$WORKER_URL/mcp?token=$TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' 2>&1) \
        || fail "tools/list call failed: $resp"
    count=$(echo "$resp" | jq '.result.tools | length' 2>/dev/null || echo 0)
    if [[ "$count" -ge 100 ]]; then
        pass "tools/list returned $count tools"
    else
        warn "tools/list returned only $count tools (expected 104). Worker may be on an older version."
    fi
else
    warn "No token in memory (Phase 6 was already done). Skipping live probe — re-run setup.sh after wiping state.json, or run smoke-test.ps1 (under pwsh) with your token."
fi

# ---- Done -------------------------------------------------------------------
section "Done"

echo ""
echo "  Your worker: $WORKER_URL/mcp?token=<your-token>"
if [[ -n "$TOKEN" ]]; then
    KV_ID=$(state_get mcp_tokens_kv_id)
    echo ""
    printf '  \033[33mThis run'\''s token (copy now — won'\''t be shown again):\033[0m\n'
    printf '    %s\n' "$TOKEN"
    echo ""
    printf '  \033[90mTo revoke later: wrangler kv key delete "%s" --namespace-id %s --remote\033[0m\n' "$TOKEN" "$KV_ID"
fi
echo ""
printf '  \033[36mNext steps (Phases 7-10 from INSTALL.md):\033[0m\n'
echo "    7. Wire the URL into your Claude Code MCP config (see templates/claude-code-mcp.json)"
echo "    8. Install skill + memory: bash templates/install-skill.sh"
echo "    9. Personalize: ask Claude to fill placeholders from list_employees + list_pipeline_statuses"
echo "    10. Smoke test: pwsh smoke-test.ps1 -WorkerUrl $WORKER_URL -Token <your-token>"
echo ""
