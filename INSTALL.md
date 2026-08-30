# INSTALL.md — Guided runbook for Claude

**Audience:** Claude Code, driving the install on behalf of a user who pointed you at this repo.

**Time:** ~15 minutes if the user has GitHub, Cloudflare, and HCP accounts. Add ~10 minutes per account they need to create.

**Output:** A live HCP MCP worker, a token in their KV, the worker URL wired into their Claude Code MCP config, the operational skill + memory files installed in their Claude, and the placeholders in those files personalized with their actual technician + pipeline IDs.

---

## Pre-flight (do this once, before Phase 1)

Run these checks in parallel and surface only what's missing:

```bash
# Auth + tooling
gh auth status                         # GitHub CLI logged in?
wrangler whoami                        # Cloudflare authed?
which gh; which wrangler; which curl   # All present?
```

```powershell
# Windows equivalents
gh auth status
wrangler whoami
Get-Command gh, wrangler, curl
```

**If `gh` not installed:** `winget install GitHub.cli` (Windows) or `brew install gh` (mac) or follow https://cli.github.com.
**If `wrangler` not installed:** `npm install -g wrangler` (requires Node 18+).
**If `gh auth status` fails:** `gh auth login` → walk user through device-code flow.
**If `wrangler whoami` fails:** `wrangler login` → opens browser for OAuth.

Do not proceed to Phase 1 until all four checks pass. State persistence: write `{"preflight_ok": true, "started_at": "<ISO timestamp>"}` to `.hcp-mcp/state.json`.

---

## Phase 1 — Fork + clone

**Do:**
```bash
gh repo fork kjricciardiacauth/hcp-mcp-template --clone --remote
cd hcp-mcp-template
```

If the user already cloned manually (i.e. you're being run inside the cloned dir), skip the clone. Verify with `git remote -v` — they should have an `origin` pointing at *their* fork, not `kjricciardiacauth`.

**Ask user:** Nothing.

**Verify:**
```bash
git remote -v | grep -v kjricciardiacauth | grep origin
```
Must return a line with the user's GitHub username, not `kjricciardiacauth`.

**Rollback:** None — fork is harmless. If wrong remote, `git remote set-url origin <user-fork-url>`.

**Persist state:** `{"phase_1_done": true, "fork_url": "<their fork URL>"}`.

---

## Phase 2 — Cloudflare project (manual UI step; no CLI equivalent for first-time create)

**Do:** Read the user the following script verbatim, then wait.

> "Cloudflare's Workers Builds (git-connect) deploy mode requires creating the project in the dashboard once. After this, every push to `main` auto-deploys. Here's what to click:
>
> 1. Open https://dash.cloudflare.com → **Workers & Pages** → **Create** → **Workers** → **Connect to Git**
> 2. Authorize Cloudflare to read your GitHub if asked
> 3. Pick your fork (`<username>/hcp-mcp-template`)
> 4. **Project name:** anything you want — this becomes your worker's subdomain (e.g. `my-hcp` → `my-hcp.<account>.workers.dev`)
> 5. **Branch:** `main`
> 6. **Root directory:** `.` (leave blank)
> 7. **Build command:** leave empty
> 8. **Deploy command:** `npx wrangler deploy`
> 9. Click **Save and Deploy**
>
> The first build will fail — that's expected (no secrets yet). Tell me your project name when done."

**Ask user:** The project name they picked (becomes the subdomain).

**Verify:**
```bash
wrangler deployments list --name <project-name>
```
Should return at least one (failed) deployment. If "project not found", they haven't completed the dashboard step.

**Rollback:** Delete the project in dashboard, retry.

**Persist state:** `{"phase_2_done": true, "project_name": "<their name>", "worker_subdomain": "<project>.<account>.workers.dev"}`. Ask the user to read their full `.workers.dev` URL from the dashboard if you can't infer it.

---

## Phase 3 — KV namespaces (wrangler CLI)

**Do:**
```bash
# Create both KV namespaces; capture the IDs from output
wrangler kv namespace create ACTIVITY_KV --remote
wrangler kv namespace create MCP_TOKENS --remote
```

Each command prints a JSON-ish block ending in `id = "<long-hex>"`. Capture both IDs.

Then patch `wrangler.toml` (use Edit tool, not sed). Find the existing `[[kv_namespaces]]` blocks and replace the `id = "..."` lines with the new IDs. Two distinct blocks: one for `ACTIVITY_KV`, one for `MCP_TOKENS`.

```bash
git add wrangler.toml
git commit -m "Add KV namespace IDs"
git push origin main
```

**Ask user:** Nothing.

**Verify:**
```bash
wrangler kv namespace list | grep -E "ACTIVITY_KV|MCP_TOKENS"
```
Both should appear. Also confirm `git push` worked (Workers Builds should kick off another deploy automatically — still expected to fail until Phase 4).

**Rollback:** `wrangler kv namespace delete --namespace-id <id>` for either KV; revert the commit with `git revert HEAD && git push`.

**Persist state:** `{"phase_3_done": true, "activity_kv_id": "...", "mcp_tokens_kv_id": "..."}`.

---

## Phase 4 — Secrets (HCP API key + optional)

**Ask user (required):** "Paste your HouseCall Pro API key. Get it from HCP admin → My Apps → API Keys → Create New (full scopes). I will not log or store this — it goes straight to Cloudflare as an encrypted secret."

**Do:**
```bash
# User pastes; you pipe it in
echo "<their-key>" | wrangler secret put HCP_API_KEY --name <project-name>
```

If the user also wants webhook ingest now (optional — can skip):
- **Ask:** "Want HCP webhook events stored in KV + viewable at `/activity`? (You'll generate an HMAC secret string)"
- If yes: `echo "<their-hmac>" | wrangler secret put HCP_WEBHOOK_SECRET --name <project-name>` and tell them to wire the webhook in HCP admin per `examples/WEBHOOK_SETUP.md`

If they want Zapier forwarding (optional):
- **Ask:** "Have a Zapier catch hook URL you want webhooks forwarded to?"
- If yes: `echo "<url>" | wrangler secret put ZAPIER_URL --name <project-name>`

**Verify:**
```bash
wrangler secret list --name <project-name>
```
Must show `HCP_API_KEY` at minimum.

**Rollback:** `wrangler secret delete HCP_API_KEY --name <project-name>` and have user re-paste.

**Persist state:** `{"phase_4_done": true, "has_webhook_secret": true|false, "has_zapier": true|false}`. **Never persist the secrets themselves.**

---

## Phase 5 — Wait for clean deploy

After Phase 4, Cloudflare auto-redeploys (because the secrets are now set and the prior failed build had the latest code). Wait for it.

**Do:**
```bash
# Poll deployments; stop when most recent is "success"
wrangler deployments list --name <project-name> | head -5
```

Re-check every 15 seconds for up to 2 minutes. If still failing after 2 min, fetch the build log via dashboard URL and surface to user.

**Verify:**
```bash
curl https://<worker-subdomain>/
# Expect: "HouseCall Pro MCP Worker v3.4.6 — 93 tools | /mcp | /webhook | /activity | /dashboard"
```

**Rollback:** Dashboard → Workers → your worker → Deployments → Rollback (one click).

**Persist state:** `{"phase_5_done": true, "deploy_verified_at": "<ISO>"}`.

---

## Phase 6 — Mint first token

**Ask user:** "What name should I label your first access token with? (e.g. 'Sarah laptop' or just your name — only you'll see it in the KV dashboard.)"

**Do:**
```bash
# Generate a random token
TOKEN=$(openssl rand -hex 32)  # or use PowerShell: -join ((48..57) + (97..122) | Get-Random -Count 64 | % {[char]$_})

# Write to KV with their friendly name and write-tier (default for the first token)
echo '{"name":"<their answer>","tier":"write"}' | wrangler kv key put "$TOKEN" --namespace-id <mcp_tokens_kv_id> --remote
```

Note: the value is a JSON object; the key is the token string itself.

**Verify:**
```bash
curl "https://<worker-subdomain>/mcp?token=$TOKEN" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | head -c 200
```
Expect a JSON-RPC response listing tools. If "auth failed" or HTML, the token didn't write — check KV key matches exactly.

**Rollback:** `wrangler kv key delete "$TOKEN" --namespace-id <id> --remote`; mint a new one.

**Persist state:** `{"phase_6_done": true, "token_last_4": "<last 4 chars>", "token_label": "<user-supplied>"}`. **Never persist the full token.** Keep it in memory for Phase 7.

---

## Phase 7 — Wire MCP into Claude Code

**Ask user:** "Which Claude are you using? (a) Claude Code CLI, (b) Claude Desktop app, (c) claude.ai web with MCP, (d) other"

Branch on answer:

### 7a. Claude Code CLI

The MCP server config goes in `~/.claude/mcp.json` (mac/Linux) or `%USERPROFILE%\.claude\mcp.json` (Windows). Read the existing file if present, or create:

```json
{
  "mcpServers": {
    "hcp": {
      "url": "https://<worker-subdomain>/mcp?token=<TOKEN>",
      "transport": "http"
    }
  }
}
```

If `mcpServers` already exists, append the `"hcp"` entry without disturbing other servers.

Use the snippet at `templates/claude-code-mcp.json` as a starting point — substitute `{{WORKER_URL}}` and `{{TOKEN}}`.

### 7b. Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json` (mac) or `%APPDATA%\Claude\claude_desktop_config.json` (Windows). Same JSON shape as 7a.

### 7c. claude.ai web

Tell the user: "claude.ai's MCP UI is at https://claude.ai/settings/connectors. Add a custom connector with name `hcp` and URL `https://<worker-subdomain>/mcp?token=<TOKEN>`. I can't write to this from the CLI."

### 7d. Other

Surface the URL + token format and let them wire it themselves.

**Verify (7a/7b):**
- For Claude Code: `claude --help mcp` or restart Claude Code and run `/mcp` to confirm the `hcp` server shows as connected.
- For Claude Desktop: restart the app; check the MCP indicator.

**Rollback:** Remove the `hcp` entry from the JSON; restart Claude.

**Persist state:** `{"phase_7_done": true, "client_kind": "code|desktop|web|other"}`.

---

## Phase 8 — Drop in skill + memory files

**Do:**

Use `templates/install-skill.ps1` (Windows) or `templates/install-skill.sh` (mac/Linux) — they handle path discovery and copy with confirmation. From the repo root:

```bash
# mac/Linux
bash templates/install-skill.sh

# Windows
powershell -ExecutionPolicy Bypass -File templates\install-skill.ps1
```

The script:
1. Discovers the user's Claude skills dir (`~/.claude/skills/`) and memory dir (per their Claude Code setup)
2. Copies `examples/claude-skill/SKILL.md` → `~/.claude/skills/hcp-ops/SKILL.md`
3. Copies `examples/claude-memory/hcp_tool.md` and `hcp_full.md` → their memory dir
4. Asks for confirmation before overwriting existing files
5. Prints next-step pointer: "Run Phase 9 personalization to fill in your real employee + pipeline IDs."

**Verify:**
```bash
ls ~/.claude/skills/hcp-ops/SKILL.md
ls <memory-dir>/hcp_tool.md <memory-dir>/hcp_full.md
```

**Rollback:** Delete the dropped files.

**Persist state:** `{"phase_8_done": true, "skill_path": "<full path>", "memory_dir": "<full path>"}`.

---

## Phase 9 — Personalization (the part that makes it feel native)

Once the MCP server is live and connected, you have access to its tools yourself. Use them to fill in the placeholders left in the dropped-in skill + memory files.

**Do:**

1. Call `mcp__hcp__list_employees({fetch_all: true})` (or whatever the connector prefix is in this Claude session)
2. Get a list of `pro_*` IDs with names + roles
3. **Ask user:** "Here are your HCP employees: [list]. Which 5 (max) should I put in the skill quick-reference table? (Most-used techs + you.)"
4. Edit `<skill_path>` and `<memory_dir>/hcp_tool.md`:
   - Replace `pro_REPLACE_ME_TECH1` through `_TECH5` with the real IDs
   - Replace `Technician One` … `Technician Five` with real names
   - Replace placeholder roles with real roles

5. Call `mcp__hcp__list_pipeline_statuses({resource_type: "lead"})`, then `"job"`, then `"estimate"`. Some may span 2 pages — fetch both.
6. Edit `<memory_dir>/hcp_full.md` Pipeline IDs section — replace `kcs_<your-id>` placeholders with the real IDs, names, and `status_type` values for each pipeline.

7. **Ask user:** "What's your local timezone? (Default: I'll keep the EDT examples but you can tell me otherwise — e.g. PST, CST, MST, or a UTC offset.)" Update the UTC conversion section in `hcp_tool.md` accordingly.

8. **Ask user:** "What's your company's HCP name? (Just for the field-strip explanation comment in `hcp_tool.md` — purely cosmetic.)"

**Verify:**

```bash
grep -c "REPLACE_ME\|<your-id>\|Technician One\|Technician Two" <skill_path> <memory_dir>/hcp_*.md
```
All counts should be 0.

**Rollback:** None — the original templates are still in this repo at `examples/`. Re-run Phase 8 to restore.

**Persist state:** `{"phase_9_done": true, "personalized_at": "<ISO>"}`.

---

## Phase 10 — Smoke test

**Do:**
```bash
# Windows
powershell -ExecutionPolicy Bypass -File smoke-test.ps1 -WorkerUrl https://<worker-subdomain> -Token <TOKEN>

# mac/Linux
# (smoke-test.ps1 runs under PowerShell Core — pwsh — on mac/Linux. Install with brew install --cask powershell.)
pwsh smoke-test.ps1 -WorkerUrl https://<worker-subdomain> -Token <TOKEN>
```

Reads version, tests `fetch_all` on 4 list tools, tests array filters on `list_invoices` + `list_jobs`, tests the v3.0.0 param fix on `update_job_schedule`, tests `get_company`.

Expected output: `N/N passed` (N = 13 currently).

**Ask user:** Nothing.

**Verify:** Exit code 0, no failed lines.

**Rollback:** If failures appear, surface the FAIL lines to the user with a guess at the cause (auth, KV mismatch, secret missing) and propose targeted re-runs.

**Persist state:** `{"phase_10_done": true, "smoke_passed": N, "smoke_total": N, "completed_at": "<ISO>"}`.

---

## Phase 11 — Hand-off

Tell the user (concisely):

> "Done. Your HCP MCP worker is live at https://<subdomain>/, your Claude has it connected, and your skill + memory know your techs and pipelines. Try asking me:
>
> - 'What jobs do we have today?'
> - 'How much AR is open right now?'
> - 'Show me the new leads.'
>
> Token + worker URL are in `.hcp-mcp/state.json` (gitignored). To mint another token for a teammate: re-run Phase 6 with a different label. To update the worker code: `git pull` from `kjricciardiacauth/hcp-mcp-template` and `git push` to your fork — Cloudflare auto-redeploys."

**Persist state:** `{"installed": true, "phases": [...], "completed_at": "<ISO>"}`.

---

## Resuming a partial install

If `.hcp-mcp/state.json` exists when this runbook starts:

1. Read it
2. Find highest `phase_N_done: true`
3. Tell user: "I see you started on [`started_at`]; you got to Phase N. Resume from Phase N+1?"
4. If yes: skip to that phase
5. If no: ask whether to reset (delete state.json) or pick a different phase

---

## state.json schema (cumulative)

```jsonc
{
  "started_at": "2026-05-24T12:00:00Z",
  "preflight_ok": true,

  "phase_1_done": true,  "fork_url": "https://github.com/<user>/hcp-mcp-template",
  "phase_2_done": true,  "project_name": "my-hcp", "worker_subdomain": "my-hcp.<account>.workers.dev",
  "phase_3_done": true,  "activity_kv_id": "...", "mcp_tokens_kv_id": "...",
  "phase_4_done": true,  "has_webhook_secret": false, "has_zapier": false,
  "phase_5_done": true,  "deploy_verified_at": "2026-05-24T12:08:00Z",
  "phase_6_done": true,  "token_last_4": "ab12", "token_label": "Sarah laptop",
  "phase_7_done": true,  "client_kind": "code",
  "phase_8_done": true,  "skill_path": "/Users/sarah/.claude/skills/hcp-ops/SKILL.md", "memory_dir": "/Users/sarah/.claude/projects/.../memory",
  "phase_9_done": true,  "personalized_at": "2026-05-24T12:14:00Z",
  "phase_10_done": true, "smoke_passed": 13, "smoke_total": 13,
  "installed": true,     "completed_at": "2026-05-24T12:15:00Z"
}
```

Never write tokens, API keys, or webhook secrets into this file.

---

## If you don't have Claude Code

This file assumes Claude is driving. If you're a human reading it directly, the same phases apply — just run the commands yourself. Manual fallback for non-CLI Cloudflare steps is the dashboard walkthrough in [README.md](README.md) Quick Start.
