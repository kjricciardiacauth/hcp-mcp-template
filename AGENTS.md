# Agent Orientation — hcp-mcp-template

## What this repo is

A public, reusable Cloudflare Worker template that exposes the HouseCall Pro API as an MCP server. Anyone can fork this and deploy their own HCP MCP worker with zero infrastructure — runs on Cloudflare's free tier.

## Key locations

- `worker.js` — The deployable Cloudflare Worker source (all 104 HCP tools)
- `wrangler.toml` — Worker name, KV namespace bindings, entry point
- `README.md` — Full setup and quick start guide (public-facing)
- `CLAUDE.md` — Entry point loaded when Claude Code opens the repo; frames the install flow
- `INSTALL.md` — Phase-by-phase runbook for Claude (or a human) driving the install
- `setup.ps1` / `setup.sh` — Cross-platform wrangler wrapper (KV, secrets, token, smoke probe)
- `templates/` — MCP config snippet + install-skill scripts referenced by INSTALL.md
- `examples/` — Usage examples

## Conventions

- Branch: `main` (direct-to-main)
- Commits: HEREDOC with `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>`
- Identity: `kjricciardiacauth` / `kyle@acauthorityfl.com`
- Mirror push: every push to `origin` goes to both kjricciardiacauth + stoopkid713

## Do not

- Add any A/C Authority-specific information, business data, employee names, or internal URLs — this is a PUBLIC repo
- Commit `.env` files, API keys, HCP tokens, or Cloudflare account IDs
- Add business-specific KV namespace IDs or worker subdomain names
- Reference internal tooling (kyle-claude-setup, acauthority-platform, etc.)

## Pointers

- This is the public template; the private production version lives in `acauthority-platform/workers/hcp/`
- Mirror remote pattern: `kyle-claude-setup/memory/mirror_remote_pattern.md` (private — do not reference in this repo's docs)
