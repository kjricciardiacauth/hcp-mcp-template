# HCP — Deep Tool Reference

**Scope:** tool-by-tool deep detail for `list_jobs`, `list_leads`, `list_invoices`, undocumented params, and pipeline ID tables (example structure — replace IDs with your own). Read on-demand when the summary in `hcp_tool.md` isn't enough.

> Drop-in companion to `hcp_tool.md` (summary) and `examples/claude-skill/SKILL.md` (operational quick-card). Copy alongside `hcp_tool.md` in your memory directory.

---

## list_jobs

**Purpose:** Scheduled/completed jobs. Used for field status, technician availability, sales-rep calendars, completions, urgent-job detection.

**Call pattern:**
```python
list_jobs(
    scheduled_start_min="2026-05-12T04:00:00Z",  # midnight in your local TZ, converted to UTC
    scheduled_start_max="2026-05-13T03:59:59Z",  # 11:59 PM in your local TZ
    page_size=10,
    page=1
)
```

**Filters (v3.0.0):**
- `location_ids: array` — multi-location
- `sort_by: enum` — `"created_at" | "updated_at" | "invoice_number" | "id" | "description" | "work_status"`
- `employee_ids: array` — works as array
- `work_status: array` — works as array

**Expected response shape (fields that matter):**
```json
{
  "page": 1,
  "total_pages": 2,
  "total_items": 87,
  "jobs": [{
    "invoice_number": "13570",
    "work_status": "complete unrated",
    "total_amount": 806839,
    "outstanding_balance": 806839,
    "customer": {
      "first_name": "Jane", "last_name": "Doe", "lead_source": "Google"
    },
    "schedule": {
      "scheduled_start": "2026-05-12T13:30:00Z",
      "scheduled_end": "2026-05-12T18:00:00Z"
    },
    "assigned_employees": [{"id": "pro_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "first_name": "Technician", "last_name": "One"}],
    "job_fields": {"job_type": {"name": "Install"}},
    "notes": [{"content": "System is inspection ready. Financed per notes."}],
    "work_timestamps": {
      "on_my_way_at": "2026-05-12T13:42:59Z",
      "started_at": "2026-05-12T14:11:25Z",
      "completed_at": "2026-05-12T17:58:46Z"
    },
    "tags": ["Install"],
    "canceled_at": null, "deleted_at": null,
    "created_at": "2026-05-11T13:39:44Z"
  }]
}
```

**Fields that matter:**
- `invoice_number` — job reference number
- `work_status` — current state (values below)
- `total_amount` — CENTS, divide by 100
- `outstanding_balance` — unpaid portion, also cents
- `customer.first_name`, `last_name`, `lead_source`
- `schedule.scheduled_start` — UTC, convert to your TZ
- `assigned_employees[].id` — match against your employee ID map
- `job_fields.job_type.name` — your account's job types (Install, Service, Sales, Maintenance, etc.)
- `notes[0].content` — intake note (most useful); `notes[-1].content` — most recent
- `tags` — your account's tag set
- `work_timestamps.completed_at` — when marked complete
- `canceled_at` non-null = cancelled
- `deleted_at` non-null = soft deleted; always exclude

**work_status values:**
- `scheduled` — booked, not started
- `in progress` — tech on site
- `needs review` — complete, pending invoice review
- `complete unrated` — done, no customer review
- `complete rated` — done with review
- `rated` — legacy variant, treat as `complete rated`
- `user canceled` / `pro canceled`

**Noise to ignore:**
- `assigned_employees[].permissions` — large nested object (stripped server-side in v3.1.0)
- `recurrence_rule`, `original_estimate_id`, top-level `lead_source` (unreliable — use `customer.lead_source`)

**Quirks:**
1. `total_amount` is CENTS — always divide by 100
2. `employee_ids` / `work_status` filters use arrays
3. `expand` parameter — still broken; ignore
4. `job_type` has no API filter — filter client-side by `job_fields.job_type.name`
5. Cancelled jobs get `scheduled_start` nulled — won't appear in date queries. Pull by customer_id for cancelled history.
6. `deleted_at != null` = always exclude
7. Date filters are UTC
8. page_size ceiling raised to 10+ since v3.1.0 stripped permissions

**Client-side filter pattern (example):**
```python
SALES_REP_ID    = "pro_REPLACE_ME_TECH4"   # populate from list_employees
INSTALLER_1_ID  = "pro_REPLACE_ME_TECH1"
INSTALLER_2_ID  = "pro_REPLACE_ME_TECH2"
SERVICE_TECH_ID = "pro_REPLACE_ME_TECH3"

sales_calls = [
    j for j in jobs
    if any(e['id'] == SALES_REP_ID for e in j.get('assigned_employees', []))
    and j['job_fields']['job_type']['name'] == 'Sales'
    and not j.get('deleted_at')
    and j['work_status'] not in ['user canceled']
]
```

**Relevance to outputs (example workflows):**
- **TODAY's schedule:** filter by today's date range, group by employee, show work_status
- **SALES CALENDAR:** sales-rep employee ID + Sales type + week range; check total_pages
- **INSTALLER SLOTS:** installer IDs + Install type + next 10 days; capacity = N/day per crew
- **COMPLETIONS:** work_status in [complete unrated, complete rated, rated] + completed_at today
- **URGENT FLAGS:** service-tech ID + today + Service type; scan notes for urgency keywords
- **WINS THIS WEEK:** Sales type + work_status complete + value from `total_amount / 100`

---

## list_leads

**Purpose:** Inbound leads through the 3-touch automation that many shops layer on top of HCP. Used for "call-now" / "call-today" prioritization.

**Call pattern:**
```python
list_leads(
    status="open",   # ALWAYS filter — without this, 300+ historical results
    page_size=50
)
# With status=open: typically ~5 results (1 page)
```

**Expected response shape:**
```json
{
  "total_pages": 1,
  "total_items": 5,
  "leads": [{
    "id": "lea_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "invoice_number": "332",
    "status": "open",
    "pipeline_status": "Third Contact",
    "customer": {
      "first_name": "Jane", "last_name": "Doe",
      "mobile_number": "5555550100", "email": null,
      "lead_source": "Thumbtack"
    },
    "address": {"city": "Your City", "state": "ST"},
    "created_at": "2026-05-12T14:04:02Z"
  }]
}
```

**Typical lead automation cycle (common in HVAC):**
```
Contact 1 (auto) -> Contact 2 (auto) -> Contact 3 (auto)
-> pipeline_status = "Third Contact" + status = "open"
-> human follow-up call
-> Mark lost if no conversion
status = "lost" = full cycle complete - NEVER re-list
```

**CALL NOW vs CALL TODAY split:**
```python
from datetime import date
today_str = str(date.today())

third_contact = [
    l for l in leads
    if l['pipeline_status'] == 'Third Contact'
    and l['customer'].get('lead_source') in ['Thumbtack', 'Angi Leads']  # or your sources
    and l['status'] == 'open'
]
call_now   = [l for l in third_contact if l['created_at'][:10] == today_str]
call_today = [l for l in third_contact if l['created_at'][:10] < today_str]
```

**Quirks:**
1. `status=open` reduces from 300+ to ~5 — always use this filter
2. `pipeline_status` cannot be filtered at API level — client-side only
3. Top-level `lead_source` is null — use `customer.lead_source`
4. `status=lost` = done — never include in call lists
5. If you have a separate manual-contact channel (Slack/chat), cross-reference before flagging "needs call" to avoid double-touching the customer

---

## list_invoices

**Purpose:** AR queries and money-in tracking. Lighter than list_jobs.

**Use for:** outstanding AR, money collected, financial sessions.
**Do NOT use for:** job status/scheduling.

**Probe first:**
```python
list_invoices(created_at_min="2026-05-06T04:00:00Z", page_size=1)
# Check total_items before committing
```

**AR pull (outstanding money owed):**
```python
list_invoices(created_at_min=week_ago_utc, page_size=30)
ar = [inv for inv in invoices
      if inv['status'] == 'open' and inv.get('due_amount', 0) > 0]
# Extract: invoice_number, customer name, due_amount (DOLLARS), created_at
```

**Money in today:**
```python
list_invoices(paid_at_min=today_start_utc, page_size=30)
# All results confirmed paid - no client-side filter needed
```

**Rich filters (v2.9.x+):**
- `status: array` — `"open" | "pending_payment" | "paid" | "voided" | "uncollectible" | "canceled"`
- `payment_method: array` — `"consumer_financing" | "credit_card" | "ach" | "external" | "mobile_check_deposit"`
- `sort_by` — `"amount" | "created_at" | "due_amount" | "due_at" | "invoice_number" | "paid_at" | "sent_at" | "status" | "updated_at"`
- `due_at_min/max`, `amount_due_min/max`

**Invoice status values:** `paid`, `open`, `pending_payment`, `voided`, `canceled`, `uncollectible`
- `voided` can have `due_amount > 0` — always use `status == 'open'` for AR
- `pending_payment` = financing in flight — note separately

**Quirks:**
1. `due_amount` is in DOLLARS (not cents) — different from list_jobs
2. `status` filter is an array — pass as `["paid"]` or `["open"]`
3. `created_at` != payment date — use `paid_at_min` for money-in
4. Safe page_size: 30 for a 7-day window

**Endpoint naming:**
- `get_invoice_by_uuid` — correct tool name (UUID path)
- `list_job_invoices` — correct tool name
- NO `get_invoice` tool — removed v2.8.1

---

## Undocumented API params confirmed (empirical, v3.2.0)

Not in HCP's public spec but confirmed working via live testing. All in worker schema.

| Endpoint | Param | Notes |
|---|---|---|
| `list_jobs` | `scheduled_start_min` / `scheduled_start_max` | Native API date filter |
| `list_jobs` | `sort_by=created_at` | Newest first |
| `list_jobs` | `work_status[]` | Array format; combines with date filters |
| `list_invoices` | `paid_at_min` / `paid_at_max` | Native date filter for revenue pull |
| `list_invoices` | `created_at_min` / `created_at_max` | Native date filter |
| `list_invoices` | `sort_by=created_at` (and others) | Full enum in schema |
| `list_events` | `sort_by=start_time` | Use with `sort_direction=desc` for upcoming |
| `list_events` | `sort_by=name` | Alphabetical |
| `list_customers` | `sort_by=created_at` | Newest first |

**Rejected / silently ignored:**
- `list_jobs`: `sort_by=scheduled_start`, `sort_by=start_time` → 400
- `list_events`: `sort_by=updated_at`, `employee_ids[]` → silently ignored
- `list_invoices`: `invoice_date_min/max`, `service_date_min/max` → silently ignored
- `list_jobs`: `date_min/max` → silently ignored

---

## Pipeline IDs — populate from your own account

Pipeline status IDs (`kcs_*`) are **account-specific**. Run `list_pipeline_statuses` with each `resource_type` and paste the results below. The tables show the **structure** you'll see; the IDs in your account will differ.

### Lead pipeline (typical: 8 statuses)

```
list_pipeline_statuses(resource_type="lead")
```

Expected status_type values: `lead_new_lead`, `lead_unassigned`, `lead_assigned`, `lead_plain`, `lead_won`, `lead_lost`. Names vary by account (common: New Lead, Unassigned, Assigned, First/Second/Third Contact, Won, Lost).

| ID | Name | status_type |
|---|---|---|
| `kcs_<your-id>` | New Lead | lead_new_lead |
| `kcs_<your-id>` | Unassigned | lead_unassigned |
| `kcs_<your-id>` | Assigned | lead_assigned |
| `kcs_<your-id>` | First Contact | lead_plain |
| `kcs_<your-id>` | Second Contact | lead_plain |
| `kcs_<your-id>` | Third Contact | lead_plain |
| `kcs_<your-id>` | Won | lead_won |
| `kcs_<your-id>` | Lost | lead_lost |

### Job pipeline (typically 10–15 statuses, may span 2 pages — fetch both)

```
list_pipeline_statuses(resource_type="job")
```

Expected status_type values: `job_unscheduled`, `job_scheduled`, `job_in_progress`, `job_completed`, `job_custom_status`, `job_plain`. Common names: Unscheduled, First/Second/Third Attempt, Scheduled, In Progress, Needs Review, Follow-up Needed, Completed, Need to Invoice.

### Estimate pipeline (typically 10–13 statuses, may span 2 pages — fetch both)

```
list_pipeline_statuses(resource_type="estimate")
```

Expected status_type values: `estimate_plain`, `estimate_requested`, `estimate_scheduled`, `estimate_in_progress`, `estimate_completed`, `estimate_created_on_job`, `estimate_sent`. Common names: Waitlist, Requested, Scheduled, In Progress, Completed, Created on Job, Sent, First/Second/Third Follow-Up.

**Reminder:** `update_pipeline_status` is **forward only** — target must have equal or higher order value than current status.
