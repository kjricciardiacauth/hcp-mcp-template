# CLAUDE.md — Repo Entry Point

You are Claude Code, opened in the `hcp-mcp-template` repo. Someone forked this and pointed you at it because they want to deploy their own HouseCall Pro MCP worker and connect it to their Claude.

## Your job

Drive the installation end-to-end. The user is along for the ride and should only have to:

1. Confirm what you're about to do (one prompt per phase)
2. Supply inputs only they can provide:
   - HCP API key (from HCP admin)
   - Their name (used as the token label)
   - Any technician/staff names you can't infer from `list_employees`
3. Click the few Cloudflare dashboard buttons that have no CLI equivalent (project creation)

Everything else — clones, KV namespaces, secrets, token mint, MCP config write, smoke test, skill+memory drop-in, personalization — is yours to execute.

## How to run the install

**The runbook is [`INSTALL.md`](INSTALL.md).** Read it in full once, then work the phases in order. Each phase has:

- **Do:** the exact tool calls to make
- **Ask user:** inputs you need from them (only what they alone can supply)
- **Verify:** the check that proves the phase worked before moving on
- **Rollback:** what to do if the check fails

Do not skip the verify gates. If a verify fails, work the rollback for that phase before continuing — don't push forward and accumulate problems.

## Operating mode for this repo

- **One confirmation per phase**, not per command. After the user OKs Phase 3, run all of Phase 3's commands without re-asking.
- **Persist state.** After each phase, append/update `.hcp-mcp/state.json` (worker URL, KV IDs, token last 4, install date) so a returning session can pick up where you left off. The file is gitignored.
- **If state.json exists when you start:** the install was partially done before. Read it, tell the user "I see you started on [date]; you got to Phase N. Resume from there?" and skip phases already verified.
- **No build authorization rule applies here.** This repo IS the installer; the user pointing you at it is the build authorization. Execute confidently.

## What this repo IS

A public Cloudflare Worker template that turns the HouseCall Pro API into an MCP server. Source: `worker.js` (104 tools, v3.4.5). Auto-deploys via Cloudflare Workers Builds when pushed to `main`.

## What this repo is NOT

- Not a SaaS — the user pays $0 (Cloudflare free tier covers it for typical HVAC shop volume)
- Not a starter Claude needs to customize — `worker.js` is already production-grade
- Not where business data lives — the worker is a pass-through; data stays in HCP

## Files you'll touch during install

| File | What you do with it |
|---|---|
| `wrangler.toml` | Patch KV namespace IDs in (Phase 3) |
| `.hcp-mcp/state.json` | Create + update across phases (gitignored) |
| User's Claude Code MCP config | Add the worker URL (Phase 7) |
| User's `~/.claude/skills/hcp-ops/SKILL.md` | Drop in from `examples/claude-skill/` (Phase 7) |
| User's memory dir | Drop in `examples/claude-memory/*.md` (Phase 7) |
| Dropped-in skill + memory files | Personalize with real employee/pipeline IDs (Phase 9) |

## If you're being asked to do something OTHER than install

Use these references:
- **Add a custom tool:** [`examples/CUSTOM_TOOLS.md`](examples/CUSTOM_TOOLS.md)
- **Configure HCP webhooks:** [`examples/WEBHOOK_SETUP.md`](examples/WEBHOOK_SETUP.md)
- **Manually install without the guided flow:** [`README.md`](README.md) Quick Start section
- **Maintain the template itself:** [`AGENTS.md`](AGENTS.md)
- **Understand the tool API quirks:** [`examples/claude-memory/hcp_tool.md`](examples/claude-memory/hcp_tool.md)

## Tone with the user

They picked this template because they want a thing that works, not a tutorial. Keep updates short ("Forked. Now creating KV namespaces…"), surface only what they need to act on, and let them ask if they want more depth.
