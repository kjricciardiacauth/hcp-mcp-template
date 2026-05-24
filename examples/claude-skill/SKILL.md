---
name: hcp-ops
description: HouseCall Pro (HCP) operations and MCP quirks. Use when the user asks about HCP, HouseCall Pro, jobs, list_jobs, list_invoices, list_customers, list_estimates, dispatch, schedule, employee IDs, technicians, work orders, money in cents, HCP auth token, HCP worker URL, or wants to call any HCP MCP tool. Also use when probing HCP list/search endpoints (probe-before-pull discipline).
---

# HouseCall Pro Operational Reference

> **Drop-in skill for Claude Code.** Copy this file to `~/.claude/skills/hcp-ops/SKILL.md`
> (or your platform's equivalent). Then fill in the **Worker** section below with your
> own deployment values. Everything else is the worker's actual behavior — leave as-is.

## Worker

Fill in once you've deployed your fork:

- **URL:** `<your-subdomain>.workers.dev/mcp?token=<token>`
- **Tool count:** 104 tools (v3.4.5)
- **Auth:** All requests require `?token=<token>` (query param) or `Authorization: Bearer <token>`
- **Token storage:** Cloudflare KV namespace `MCP_TOKENS` (id: `<your-kv-id>`)
- **Token format:** `{"name":"Full Name","tier":"read"|"write"}`

| Tier | Access |
|------|--------|
| `read` | All list/get tools only |
| `write` | Full 104 tools |

## Probe-Before-Pull Discipline

**Always probe before a large list call.**

1. Call with `page_size=1`, tightest date range → check `total_items`
2. Known safe ceilings: `list_jobs` page_size=10+ (safe since v3.1.0); `list_invoices` page_size=30 for 7-day window
3. Use `fetch_all: true` only for bulk exports (forces page_size=100, loops up to 20 pages)

## Money Is in CENTS

**All HCP money fields are in CENTS. Divide by 100 to get dollars.**

- `list_jobs`: `total_amount`, `outstanding_balance` → CENTS
- `list_invoices`: `amount`, `subtotal` → CENTS
- Line items, pricebook: `unit_price`, `unit_cost`, `price`, `cost` → CENTS
- Estimate option `total_amount` → CENTS
- **Exception:** `list_invoices` `due_amount` field → DOLLARS (confirmed anomaly)

## Universal Tier-A Field Strip (v3.4.1+)

Five always-safe fields are stripped recursively from every HCP response:

1. `permissions` — HCP role objects (~40% of list_jobs payload)
2. `company_name` — always your single HCP company name
3. `company_id` — always the same UUID
4. `avatar_url` — UI presentation only
5. `color_hex` — UI presentation only

**Opt-out:** Pass `raw: true` on any tool that exposes it (most read tools as of v3.4.4) to get the truly raw HCP response including permissions.

**Kill switch:** Cloudflare dashboard → your worker → Variables → `PROJECT_ENABLED=false` disables the projector transforms (pagination hint, per-tool projector). `stripFields` runs independently; bypass per-call with `raw=true`.

## Pagination Hint

List responses on registered tools include a `_pagination` plaintext field:
`"Showing N of M total. Page X of Y. Pass page=Z for next page, or use fetch_all=true for all records."`

Read this prose — LLMs ignore structured pagination fields.

## Corrected Param Names

### `update_job_schedule`
- `start_time` (required) — was `scheduled_start`
- `end_time` — was `scheduled_end`
- `arrival_window_in_minutes` — was `arrival_window_minutes`
- `notify: boolean` — SMS/email to customer at scheduling time (NOT at completion)
- `notify_pro: boolean` — confirmation to assigned employee at scheduling time
- `dispatched_employees: array` — employees to assign

### `create_job`
- `address_id` is required (was missing from prior docs)
- Schedule sub-object: `scheduled_start` / `scheduled_end` / `arrival_window` (different convention than `update_job_schedule`)

### `create_job_appointment`
- `scheduled_start` / `scheduled_end` / `arrival_window_minutes` (yet another convention)

### `lock_jobs`
- Takes `starting_at` + `ending_at` (ISO 8601 range) — NOT `job_ids`
- Locks all eligible jobs in the range. For one job use `lock_job`.

### `dispatch_job` (v3.4.5 fix)
- Pass `employee_ids: ["pro_..."]`; worker now remaps to HCP's `dispatched_employees:[{employee_id}]` body shape internally

### `create_estimate` (v3.4.5 fix)
- If you don't pass an `options` array, worker auto-injects `[{name:"Option 1"}]` (HCP refuses empty estimates)

### `convert_lead` (v3.4.5 fix)
- POSTs to `/leads/{id}/convert` (was incorrectly PUT in v2.8.0–v3.4.4); pass `convert_to` and worker remaps to body key `type`

## Response Shape Map

Three distinct shapes — do not assume one fits all:

| Group | Array key | Pagination |
|-------|-----------|------------|
| Standard list tools | `jobs`, `customers`, `leads`, etc. | `total_items` / `total_pages` |
| Pricebook tools | `items` | `total_items` / `total_pages` |
| Job sub-resources | `data`, `appointments`, `invoices`, `job_input_materials` | None — bare arrays |

Pricebook tools (use `items` key): `list_pricebook_services`, `list_pricebook_materials`, `list_material_categories`, `list_price_forms`, `get_price_form`.

Job sub-resources (bare arrays, no pagination): `list_job_line_items` (`data`), `list_job_appointments` (`appointments`), `list_job_invoices` (`invoices`), `list_job_input_materials` (`job_input_materials`).

## Known Broken / Avoid

1. **`expand` param on `list_jobs`** — broken ("Expand must be an array of strings"); ignore
2. **`get_application`** — removed v3.1.0 (dead 404, requires Application API Key)
3. **`preview_invoice`** — blocked v3.1.0 (returns 254KB raw HTML); use `get_invoice_by_uuid`
4. **`list_checklists`** — requires `job_uuids` array; errors without it
5. **`list_pricebook_materials`** — requires `material_category_uuid`; call `list_material_categories` first
6. **`list_events`** — sorts by `created_at` not schedule date by default; use `sort_by=start_time&sort_direction=desc` + date filters

## Key Gotchas

- Date filters are UTC. Convert from your local TZ before passing. (Eastern example: 8AM EDT = 12:00Z, midnight EDT = 04:00Z next day)
- `job_type` has NO API filter — filter client-side by `job_fields.job_type.name`
- Cancelled jobs get `scheduled_start` nulled — use customer_id pull for cancelled history
- `deleted_at != null` = soft deleted — always exclude from results
- Top-level `lead_source` on jobs is unreliable — use `customer.lead_source`
- `status=open` on `list_leads` reduces 300+ results to ~5 — always use this filter
- `work_status` real values include `"complete unrated"` (default for completed jobs) and `"user canceled"` (customer-initiated cancellation), not just `"completed"`/`"canceled"`

## Employee IDs (fill in your own)

Get from `list_employees`, then store here for quick reference:

| Name | Role | HCP ID |
|------|------|--------|
| Technician One | Installer | `pro_REPLACE_ME_TECH1` |
| Technician Two | Installer | `pro_REPLACE_ME_TECH2` |
| Technician Three | Service Tech | `pro_REPLACE_ME_TECH3` |
| Technician Four | Sales | `pro_REPLACE_ME_TECH4` |
| Technician Five | Owner | `pro_REPLACE_ME_TECH5` |

## Estimates — Three-Step Chain

1. `create_estimate` → `estimate_id` (worker auto-creates a default "Option 1" if no options array supplied)
2. `create_estimate_option` → `option_id` (if you want more than the default option)
3. `bulk_update_estimate_option_line_items` → add line items

Cannot add line items directly to an estimate (must go through an option).

⚠️ **`bulk_update_*` tools (line items, materials):** Sending a SUBSET deletes the omitted items — these are REPLACE-not-PATCH operations. Always send the full intended list.

## Pipeline — Forward Only

`update_pipeline_status` moves forward only — target must have equal or higher order value.
`list_pipeline_statuses` requires `resource_type: "lead" | "job" | "estimate"` (required param).
