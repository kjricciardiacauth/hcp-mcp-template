# HouseCall Pro MCP Worker

A **plug-and-play Cloudflare Worker** that exposes the HouseCall Pro API as an MCP (Model Context Protocol) server. Point Claude or any MCP client to this worker and get instant access to all HCP tools—fully production-ready.

**Auto-deploys on push** via Cloudflare Workers Builds (git-connect). No manual paste-to-dashboard steps.

## Features

- **104 tools** — complete HCP API coverage (customers, jobs, estimates, invoices, leads, pricebook, dispatch, and more)
- **Token-based auth** — read/write access tiers, tokens stored in Cloudflare KV
- **`fetch_all` pagination** — auto-paginate any of 10 list tools, up to ~2000 records
- **Webhook receiver** — validates HMAC-SHA256, stores events in KV (48h TTL), optional Zapier forwarding
- **Dispatch dashboard** — live `/dashboard` view of today's jobs and tech status
- **Activity feed** — `/activity` endpoint with edge-caching (50s TTL)
- **MCP-compliant** — works with Claude Code, claude.ai, and any MCP client
- **Zero infrastructure** — runs on Cloudflare's free tier

## Setup in one shot (with Claude Code)

The repo is designed to install itself. Fork, clone, point Claude at it:

```bash
gh repo fork kjricciardiacauth/hcp-mcp-template --clone --remote
cd hcp-mcp-template
claude "install this"
```

Claude reads [`CLAUDE.md`](CLAUDE.md) (the entry point) and follows [`INSTALL.md`](INSTALL.md) — a phase-by-phase runbook covering everything from KV namespace creation through MCP wiring, skill+memory install, and personalization with your real technician and pipeline IDs. The only things you have to supply are:

- Your HCP API key (Claude tells you where to find it)
- Your name (becomes the label on your first access token)
- Approval at each phase boundary

Time: ~15 minutes. State persists in `.hcp-mcp/state.json` (gitignored), so partial installs can resume in a fresh session.

**Don't have Claude Code?** Walk the phases in [`INSTALL.md`](INSTALL.md) yourself — the commands are the same. Or follow the dashboard-driven Quick Start below.

---

## Quick Start

### 1. Fork and clone

```bash
git clone https://github.com/YOUR_USERNAME/hcp-mcp-template.git
cd hcp-mcp-template
```

### 2. Create two KV namespaces in Cloudflare

In Cloudflare dashboard → **KV** → **Create namespace**:

| Namespace name | Purpose | `wrangler.toml` binding |
|---|---|---|
| `hcp-activity` (or any name) | Stores webhook events (48h TTL) | `ACTIVITY_KV` |
| `hcp-tokens` (or any name) | Stores MCP access tokens | `MCP_TOKENS` |

After creating each, copy its **ID** and paste into `wrangler.toml`:

```toml
[[kv_namespaces]]
binding = "ACTIVITY_KV"
id = "paste-your-activity-kv-id-here"

[[kv_namespaces]]
binding = "MCP_TOKENS"
id = "paste-your-tokens-kv-id-here"
```

> **Why wrangler.toml?** Cloudflare Workers Builds treats this file as the source of truth for bindings. Anything only set in the dashboard gets wiped on the next deploy.

### 3. Connect to Cloudflare (git-connect)

In Cloudflare dashboard:

1. **Workers & Pages** → **Create** → **Deploy with Git**
2. Select your forked repo
   - Branch: `main`
   - Root directory: `.`
   - Build command: (leave empty)
   - Deploy command: `npx wrangler deploy`
3. Deploy

### 4. Add secrets

In Cloudflare **Workers** → your worker → **Settings** → **Variables and Secrets**:

| Secret name | Required | Purpose |
|---|---|---|
| `HCP_API_KEY` | **Yes** | Your HouseCall Pro API token |
| `HCP_WEBHOOK_SECRET` | No | HMAC signing secret for HCP webhooks |
| `ZAPIER_URL` | No | Zapier catch hook URL — forwards all HCP webhooks to Zapier |

Save & deploy.

### 5. Add your first access token

In Cloudflare dashboard → **KV** → your `hcp-tokens` namespace → **Add entry**:

- **Key:** any random string (this becomes your token, e.g. `my-secret-token-123`)
- **Value:** `{"name":"Your Name","tier":"write"}`

### 6. Connect MCP

Add your worker URL to Claude (or any MCP client), with your token appended:

```
https://your-worker.workers.dev/mcp?token=my-secret-token-123
```

### 7. Verify

```bash
curl https://your-worker.workers.dev/
# → "HouseCall Pro MCP Worker v3.4.5 — 104 tools | /mcp | /webhook | /activity | /dashboard"
```

---

## Token Auth

All `/mcp` requests require a token. Pass it as a query param or header:

```
https://your-worker.workers.dev/mcp?token=YOUR_TOKEN
Authorization: Bearer YOUR_TOKEN
```

Tokens are stored in the `MCP_TOKENS` KV namespace as JSON:

```json
{"name": "Your Name", "tier": "write"}
```

| Tier | What it can do |
|---|---|
| `read` | `tools/list` and `tools/call` on read-only tools (list/get) only |
| `write` | Full access — all 104 tools including create, update, delete |

**To add a user:** KV dashboard → `hcp-tokens` → Add entry → key = token string, value = JSON above.  
**To revoke:** Delete the key from the KV dashboard.

---

## `fetch_all` — Auto-pagination

Ten list tools support `fetch_all: true`. When set, the worker fetches all pages automatically (up to 20 pages × 100 records = ~2000 records) with a 100ms delay between pages to avoid rate limits.

```json
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "id": 1,
  "params": {
    "name": "list_jobs",
    "arguments": { "fetch_all": true }
  }
}
```

Tools that support `fetch_all`:

| Tool | Response key |
|---|---|
| `list_customers` | `customers` |
| `list_jobs` | `jobs` |
| `list_estimates` | `estimates` |
| `list_invoices` | `invoices` |
| `list_leads` | `leads` |
| `list_employees` | `employees` |
| `list_events` | `events` |
| `list_tags` | `tags` |
| `list_pricebook_materials` | `materials` |
| `list_pricebook_services` | `services` |

---

## Routes

| Endpoint | Method | Purpose |
|---|---|---|
| `/` | GET | Health check + version |
| `/mcp` | GET | Server info (MCP metadata) |
| `/mcp` | POST | MCP JSON-RPC (`tools/list`, `tools/call`) — requires token |
| `/webhook` | POST | Receive HCP webhooks (HMAC validated, stored in ACTIVITY_KV) |
| `/activity` | GET | Recent webhook events (edge-cached 50s) |
| `/dashboard` | GET | Live dispatch dashboard HTML |

---

## Tools (104 total)

Organized by resource:

**Customers:** list, get, create, update, address management  
**Employees:** list  
**Jobs:** list, get, create, schedule, dispatch, lock, appointments, notes, tags, links, attachments, line items, input materials, invoices  
**Estimates:** list, get, create, update, options (approve/decline/notes/line items/attachments/schedule)  
**Invoices:** list, get by UUID, list job invoices  
**Leads:** list, get, create, convert, line items, lead sources  
**Tags:** list, create, update  
**Job Types:** list, create, update  
**Pricebook:** services, materials (create/update/delete), material categories, price forms  
**Scheduling:** events, booking windows, routes, service zones, schedule availability  
**Pipeline:** list statuses, update status (jobs/estimates/leads)  
**Company:** get info, update franchise info, checklists, webhooks (create/delete)

> Note: 8 undocumented/non-functional endpoints were removed in v2.8.0 compared to the original template. The 104 tools here are all confirmed working against the live HCP API.

---

## Add Custom Tools

See [examples/CUSTOM_TOOLS.md](examples/CUSTOM_TOOLS.md).

**TL;DR:**
1. Add a tool definition to the `TOOLS` array in `worker.js`
2. Add a handler in the `callTool()` switch statement
3. Push to main — auto-deployed

---

## Webhook Setup

See [examples/WEBHOOK_SETUP.md](examples/WEBHOOK_SETUP.md) for HCP configuration.

In HCP admin → Webhooks:
- URL: `https://your-worker.workers.dev/webhook`
- Enable HMAC signing; set the secret to match `HCP_WEBHOOK_SECRET` in Cloudflare

Events are stored in `ACTIVITY_KV` (48h TTL) and viewable at `/activity`. If `ZAPIER_URL` is set, every webhook is also forwarded there.

---

## Deployments

**Push to main → live in ~30–60 seconds**

```bash
git push origin main
```

Cloudflare watches your repo. Changes to `worker.js` or `wrangler.toml` trigger an automatic redeploy.

**Rollback:** Cloudflare dashboard → Workers → your worker → Deployments → click "Rollback"

---

## Environment Variables

| Name | Required | Purpose |
|---|---|---|
| `HCP_API_KEY` | **Yes** | HouseCall Pro API token |
| `HCP_WEBHOOK_SECRET` | No | HMAC validation for incoming HCP webhooks |
| `ZAPIER_URL` | No | Forward all webhooks to a Zapier catch hook |

All are **Secrets** in Cloudflare dashboard — never put them in `wrangler.toml`.

---

## Known Quirks

- `list_jobs` amounts (`total_amount`, `outstanding_balance`) are in **cents** — divide by 100
- `list_invoices` `due_amount` is in **dollars** (different from list_jobs)
- All timestamps are UTC — convert to your local timezone as needed
- `expand` parameter on `list_jobs` is broken in HCP's API — ignore it
- Cancelled jobs get their `scheduled_start` nulled — they won't appear in date-range queries
- `list_pricebook_materials` requires `material_category_uuid` — call `list_material_categories` first
- `list_events` sorts by `created_at` by default, not schedule date — use `sort_by=start_time&sort_direction=desc` with `fetch_all` for date-scoped queries

---

## Version History

| Version | Changes |
|---|---|
| v3.4.5 | Three real worker bugs caught by end-to-end test: `dispatch_job` body shape, `create_estimate` auto-injects default option, `convert_lead` POST not PUT. Description fixes on `update_job_appointment` + 3 `bulk_update_*` tools + `create_estimate` + `create_lead` (now requires `customer_id`) |
| v3.4.4 | Read-tool polish on 15 more tools (employees, events, appointments, line items, invoices, materials, services, tags, job types, lead sources, pipeline statuses, checklists, etc.). `raw=true` opt-out wired. `normalizePricebookPage` now bypassed by `raw=true` (bug fix). |
| v3.4.3 | Write-tool description rewrites (~33 tools) with what/when/returns/caveats. Documented the three schedule param conventions across `create_job` / `update_job_schedule` / `create_job_appointment`. No schema field changes. |
| v3.4.2 | Description rewrites + `raw=true` on 8 more read tools (invoices, customers, estimates, leads). Extended `work_status` enum with production values. |
| v3.4.1 | Universal Tier-A field strip — 5 always-safe fields (`permissions`, `company_name`, `company_id`, `avatar_url`, `color_hex`) stripped recursively from every HCP response. Rolled back over-aggressive per-tool projection from v3.4.0. `raw=true` per-call opt-out, `_pagination` plaintext hint on registered list tools, `PROJECT_ENABLED` kill switch. |
| v3.4.0 | MCP optimization pilot on `list_jobs` + `get_job` — field projection, expanded MCP annotations (all 4 hints), rewritten descriptions, `work_status` enum additions. |
| v3.3.1 | Inline PNG icon in MCP serverInfo |
| v3.3.0 | Token-based auth with read/write tiers (MCP_TOKENS KV) |
| v3.2.0 | Expose undocumented HCP API params (sort_by for events/customers/invoices) |
| v3.1.0 | Strip employee permissions from responses (~40% size reduction), normalize pricebook pagination shape, add `start_time_min/max` to `list_events` |
| v3.0.0 | `fetch_all` auto-pagination (10 tools), schema fixes (correct param names for `update_job_schedule`, `lock_jobs`, `create_job`) |
| v2.9.x | `list_invoices` full filter schema, cents descriptions on money fields, MCP quality pass (enums, ISO 8601 descriptions, correct error shapes) |
| v2.8.x | Remove 8 undocumented/broken tools, fix `convert_lead` method |
| v2.6.0 | MCP annotations (`readOnlyHint`, `destructiveHint`) for all tools |
| v1.0.0 | Initial template release |

---

## Using with Claude Code (skill + memory drop-ins)

If you use Claude Code (or any agent that supports skills + memory files), this template ships with three drop-in operational references that make the worker much more usable from the agent. They cover the API's footguns (cents vs. dollars, three different schedule-param conventions, broken endpoints to avoid, fetch_all caps, the universal field strip), so the agent doesn't rediscover them every session.

| File | Purpose | Where to copy |
|---|---|---|
| [`examples/claude-skill/SKILL.md`](examples/claude-skill/SKILL.md) | Operational quick-card auto-loaded when HCP topics come up | `~/.claude/skills/hcp-ops/SKILL.md` |
| [`examples/claude-memory/hcp_tool.md`](examples/claude-memory/hcp_tool.md) | Tool reference: auth, projection, money fields, corrected param names, known broken endpoints | Your memory directory (e.g. `~/.claude/projects/<encoded>/memory/`) |
| [`examples/claude-memory/hcp_full.md`](examples/claude-memory/hcp_full.md) | Deep reference: `list_jobs` / `list_leads` / `list_invoices` field-by-field, response shapes, pipeline ID table structure | Same memory directory |

**Quick install (Claude Code on macOS/Linux):**
```bash
mkdir -p ~/.claude/skills/hcp-ops
cp examples/claude-skill/SKILL.md ~/.claude/skills/hcp-ops/
# memory directory location varies — see your Claude Code docs
cp examples/claude-memory/hcp_*.md /path/to/your/memory/dir/
```

After copying, edit the placeholders in each file — worker URL, KV namespace ID, employee IDs (pull from `list_employees`), and pipeline IDs (pull from `list_pipeline_statuses` for each `resource_type`).

---

## License

MIT. Fork, customize, deploy.
