---
name: HCP tool reference
description: HouseCall Pro MCP - auth, IDs, money/ID conventions, fetch_all summary, corrected param names, known broken. Deep tool sections in hcp_full.md.
type: reference
---

> **Drop-in memory file for Claude Code.** Copy to your memory directory
> (e.g. `~/.claude/projects/<encoded-userprofile>/memory/`) and reference it
> from your top-level memory index. Pair with `hcp_full.md` (deep reference)
> and `examples/claude-skill/SKILL.md` (operational quick-card).
>
> **NOTE:** Operational summary loaded on-demand via `~/.claude/skills/hcp-ops/SKILL.md`.

# HouseCall Pro MCP Tool Reference

Worker: `<your-subdomain>.workers.dev/mcp` — **104 tools** (v3.4.5).

---

## Auth (v3.3.0+)

All `/mcp` requests require a token. Add `?token=<token>` to the URL, or pass `Authorization: Bearer <token>`.

- **Token storage:** Cloudflare KV namespace `MCP_TOKENS` (id `<your-kv-id>`)
- **KV format:** key = token string, value = `{"name":"Full Name","tier":"read"|"write"}`
- **Tiers:** `read` = readOnlyHint tools only (list/get); `write` = all 104 tools
- **Teammate URL:** `https://<your-subdomain>.workers.dev/mcp?token=<their-token>`
- **Add/revoke:** Cloudflare dashboard → Workers & Pages → KV → MCP_TOKENS

**Icons field gotcha (2026-05-14):** outbound proxy + inline ICO both broke connections. Inline PNG with correct MCP spec 2025-11-25 (`mimeType: "image/png"`, `sizes: ["any"]`) works (v3.3.1) but Claude Code likely hardcodes icons — globe icon is expected.

---

## Projection (v3.4.1+ — Option B rollback of Section 2's aggressive projection)

**Strip behavior (ALL HCP tools, universally):** 5 always-safe fields are stripped recursively at any nesting depth from every tool's response:

1. `permissions` (HCP role objects, v3.1.0 strip — ~40% of response size on jobs)
2. `company_name` — always your single HCP company name at every path
3. `company_id` — always the same UUID at every path
4. `avatar_url` — employee avatar URL (UI presentation only)
5. `color_hex` — employee color label (UI presentation only)

All other HCP fields pass through unchanged. Customer's actual business name (`customer.company`, e.g., "Acme Refrigeration Inc") is NEVER stripped — it was never on any strip list.

**Token impact:** ~10–18% reduction per record on `list_jobs` (~80 tokens per record with 1 employee, ~140 tokens with 2 employees). Smaller win than the original aggressive projection (which was rolled back) but ZERO risk of breaking workflows that need fields like `customer.email`, `customer.kind`, `employee.role`.

**Per-tool projection:** None active. `PROJECTORS = {}` is intentionally empty in v3.4.1+. Re-add per-tool projector entries only if a tool has additional always-safe fields beyond the universal STRIP_FIELDS list.

**Opt-out:** Pass `raw: true` to bypass ALL transforms (the 5-field strip, any per-tool projector, AND the `_pagination` hint). Returns the truly raw HCP response including permissions. As of v3.4.4, `raw` is wired on `list_jobs`, `get_job`, `list_invoices`, `get_invoice_by_uuid`, `list_customers`, `get_customer`, `list_estimates`, `get_estimate`, `list_leads`, `get_lead`, `list_employees`, `list_events`, `get_event`, `list_job_appointments`, `list_job_line_items`, `list_job_invoices`, `list_job_input_materials`, `list_pricebook_services`, `list_pricebook_materials`, `list_material_categories`, `list_tags`, `list_job_types`, `list_lead_sources`, `list_pipeline_statuses`, `list_checklists`.

**Kill switch:** Cloudflare dashboard → your worker → Variables → flip `PROJECT_ENABLED=false` to disable the `project()` transforms (pagination hint, per-tool projector). Note: `stripFields` runs INDEPENDENTLY of this switch — the only way to bypass it is `raw=true` per-call. To disable strip entirely worker-wide, edit the STRIP_FIELDS constant or use a code revert.

**Pagination hint (v3.4.0+):** List responses on registered tools get a `_pagination` plaintext field: `"Showing N of M total. Page X of Y. Pass page=Z for next page, or use fetch_all=true for all records."` Read this prose — LLMs ignore structured pagination fields.

**Annotations:** READ/WRITE/DESTROY annotation constants set all 4 MCP hints (readOnlyHint, destructiveHint, idempotentHint, openWorldHint) — drives correct UX in Claude Code / claude.ai confirmation prompts.

---

## v3.4.5 worker bug fixes

Three real bugs caught by end-to-end test, all now patched in the worker:

- **`dispatch_job`** — now remaps `employee_ids` to HCP's `dispatched_employees:[{employee_id}]` body shape (was passing through and 400-ing)
- **`create_estimate`** — auto-injects `[{name:"Option 1"}]` if no options array supplied (HCP refuses empty estimates)
- **`convert_lead`** — now POSTs to `/leads/{id}/convert` (v2.8.0 mistakenly switched to PUT; the route is POST per HCP docs) and remaps `convert_to` to body key `type`

Description fixes in v3.4.5:
- Removed false "partial patch" claim from `update_job_appointment`
- Replaced wrong "sending [] wipes" example on the three `bulk_update_*` tools (HCP rejects [] arrays — the actual risk is sending a SUBSET that deletes the omitted items)
- Rewrote `create_estimate` and `create_lead` descriptions
- `create_lead` schema now requires `customer_id` (HCP enforces)

---

## Key IDs (fill in your own)

### Employee IDs

Pull from `list_employees`, then drop into both this table and `examples/claude-skill/SKILL.md`:

| Name | Role | HCP ID |
|------|------|--------|
| Technician One | Installer | pro_REPLACE_ME_TECH1 |
| Technician Two | Installer | pro_REPLACE_ME_TECH2 |
| Technician Three | Service Tech | pro_REPLACE_ME_TECH3 |
| Technician Four | Sales | pro_REPLACE_ME_TECH4 |
| Technician Five | Owner | pro_REPLACE_ME_TECH5 |

---

## Money fields

- `list_jobs` amounts (`total_amount`, `outstanding_balance`) — **CENTS** (divide by 100)
- `list_invoices` / `get_invoice_by_uuid` / `list_job_invoices` (`amount`, `subtotal`) — **CENTS**
- `due_amount` on invoices — **DOLLARS** (not cents) — confirmed via smoke test
- Line items, pricebook materials (`unit_price`, `unit_cost`, `price`, `cost`) — **CENTS**
- Estimate option `total_amount` — **CENTS**

---

## ID conventions

- Customer IDs start with `cus_`
- Job, estimate, lead, invoice IDs are UUID strings
- Never pass numbers as IDs — always strings
- `material_category_uuid` REQUIRED for listing AND creating materials

---

## Response shape map

Three distinct shapes — do not assume one pattern fits all:

| Group | Array key | Pagination | Notes |
|---|---|---|---|
| Standard list tools (`list_jobs`, `list_customers`, `list_leads`) | `jobs`/`customers`/`leads` | `total_items` / `total_pages` | Normal |
| Pricebook tools | `items` | `total_items` / `total_pages` | Normalized v3.1.0 |
| Job sub-resources (`list_job_line_items`, `list_job_appointments`, `list_job_invoices`, `list_job_input_materials`) | `data`/`appointments`/`invoices`/`job_input_materials` | **none — bare arrays** | No pagination at all |

---

## fetch_all pagination (v3.0.0)

10 list tools accept `fetch_all: true`. Forces `page_size: 100`, loops up to 20 pages, 100ms delay. Cap: ~2,000 records.

Accepted tools: `list_customers`, `list_jobs`, `list_estimates`, `list_invoices`, `list_leads`, `list_employees`, `list_events`, `list_tags`, `list_pricebook_materials`, `list_pricebook_services`.

---

## Corrected param names (v3.0.0 fixes + v3.4.x clarifications)

Three different schedule-param conventions across the create/update tools — easy to mix up:

### `update_job_schedule`
- `scheduled_start` → `start_time` (REQUIRED)
- `scheduled_end` → `end_time`
- `arrival_window_minutes` → `arrival_window_in_minutes`
- `notify: bool` = SMS/email customer at scheduling time (NOT completion)
- `notify_pro: bool` = email assigned employee at scheduling time
- `dispatched_employees: array`

### `create_job`
- `address_id` is REQUIRED
- Schedule sub-object: `scheduled_start` / `scheduled_end` / `arrival_window`

### `create_job_appointment`
- `scheduled_start` / `scheduled_end` / `arrival_window_minutes`

### `lock_jobs`
- `starting_at` + `ending_at` (ISO 8601, both required) — locks all eligible jobs in range
- For single job: use `lock_job`

---

## UTC / local TZ conversion

All HCP timestamps are UTC. Convert from your local TZ before passing date filters.

```python
from datetime import datetime, timezone, timedelta
# Eastern example (EDT = UTC-4):
EDT = timezone(timedelta(hours=-4))
def to_utc(dt): return dt.astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
```

Eastern reference: 8 AM EDT = 12:00Z, noon = 16:00Z, 5 PM = 21:00Z, midnight = 04:00Z next day.

---

## Pagination Pattern

```python
def get_all_jobs(start_utc, end_utc):
    all_jobs, page = [], 1
    while True:
        data = list_jobs(scheduled_start_min=start_utc, scheduled_start_max=end_utc,
                         page_size=10, page=page)
        all_jobs += data['jobs']
        if page >= data['total_pages']: break
        page += 1
    return all_jobs
```

For bulk exports: `fetch_all: true` (forces page_size=100, auto-loops up to 20 pages).

---

## Estimates — three-step structure

Estimates → Options → Line Items. Cannot add line items directly to an estimate.

1. `create_estimate` → get `estimate_id` (worker auto-creates `[{name:"Option 1"}]` if no options array supplied — v3.4.5)
2. `create_estimate_option` → get `option_id` (only if you want more than the default option)
3. `bulk_update_estimate_option_line_items` → add line items

⚠️ `bulk_update_*` tools are REPLACE-not-PATCH: sending a subset deletes the omitted items. Always send the full intended list.

---

## Pipeline — forward only

`list_pipeline_statuses` requires `resource_type: "lead" | "job" | "estimate"`. `update_pipeline_status` moves forward only (target equal or higher order). Returns 2 pages — fetch both.

**Full pipeline ID tables (lead/job/estimate):** see `hcp_full.md` (after you populate it from your own `list_pipeline_statuses` output).

---

## Pricebook services — read-only in worker

Only `list_pricebook_services` exposed. Create/update/delete via HCP dashboard.

---

## Known broken / unavailable / avoid

- `expand` parameter on `list_jobs` — still broken
- `get_application` — removed v3.1.0 (dead 404)
- `preview_invoice` — blocked v3.1.0 (254KB HTML blob); use `get_invoice_by_uuid`
- `list_checklists` — requires `job_uuids` array
- `list_pricebook_materials` — requires `material_category_uuid`
- `list_events` — HCP sorts by `created_at` not schedule date; use `sort_by=start_time&sort_direction=desc` + `fetch_all:true` + `start_time_min/max`
- HCP fires NO webhooks for note operations (job.note.created etc don't exist)
- Payment processing not available via API

---

## Deep tool-by-tool reference

For `list_jobs` / `list_leads` / `list_invoices` deep sections (call patterns, response shape JSON, fields that matter, work_status values, noise to ignore, quirks, client-side filter patterns, relevance-to-outputs guidance, undocumented API params, full pipeline ID tables):

**Read:** `hcp_full.md` (same directory).
