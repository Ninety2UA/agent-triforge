# Gemini CLI → Antigravity CLI fact sheet — verified July 17, 2026

Researched by antigravity-researcher. Primary sources: GitHub REST/GraphQL via gh (raw), Google developer blog, canonical deprecation page, context7 official-docs index, Firecrawl-scraped migration guide. SEO-spam cluster identified and discarded (one confirmed-false claim: config did NOT move to ~/.antigravity/).

## Premise verdict: TRUE, with nuance
Gemini CLI's HOSTED SERVICE for consumer/individual tiers (free, Google AI Pro, Ultra) stopped serving 2026-06-18; Antigravity CLI is the explicitly designated successor. BUT the OSS google-gemini/gemini-cli repo is NOT archived — still shipping (v0.51.0, 2026-07-16) — and **enterprise users with Gemini Code Assist licenses and API-key authentication remain completely unaffected** (verbatim from maintainer announcement, GitHub Discussion #28017, 2026-06-18). Confirmed by Google's canonical deprecation page (developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals): replacement = "the Antigravity family of products."
→ Triage implication: whether Triforge's invoke_gemini is broken TODAY depends on auth mode (API-key users unaffected). Strategic direction (migrate to agy) unchanged.
Quirk: gemini-cli README still markets itself with no deprecation mention — OSS docs lag the service cutoff.

## What Antigravity is
4 surfaces: Antigravity 2.0 desktop GUI (with "Manager Surface" multi-agent orchestration), **Antigravity CLI (binary `agy`)**, SDK, and "Antigravity plugins" (successor to Gemini CLI extensions). VERIFIED (developers.googleblog.com launch post; TechCrunch I/O 2026 coverage).
- GitHub org google-antigravity (created 2025-11-04); antigravity-cli repo created 2026-05-13, latest **1.1.3** (2026-07-16), license: null (closed-source distribution, unlike Apache-2.0 gemini-cli). VERIFIED raw API.
- Install: curl -fsSL https://antigravity.google/cli/install.sh | bash. VERIFIED (raw README).

## CLI feature surface (VERIFIED via context7 + direct scrape unless tagged)
- Headless: `agy -p "prompt" --cwd $(pwd)` — direct parallel to `gemini -p`.
- Plugins: ~/.gemini/antigravity-cli/plugins/<name>/ containing plugin.json (required), mcp_config.json, hooks.json, skills/, agents/, rules/. /agents panel in TUI.
- Skills: workspace `.agents/skills/` (md + name/description frontmatter → compiled to slash commands). Old Gemini CLI workspace path was `.gemini/skills/` (global ~/.gemini/skills/ → ~/.gemini/antigravity-cli/skills/). Triforge's session-start copy to .agents/skills/ is Antigravity-aligned going forward (verify the May "Gemini v0.36.0 workspace tier" claim was the same mechanism).
- Hooks: hooks.json in plugin or primary settings.json; /hooks lists. Event-name parity with Gemini CLI (SessionStart, AfterTool…) UNVERIFIED.
- Agent teams / "/teamwork" / "/goal" in the CLI: **UNVERIFIED / NOT FOUND** — found /fork (branch conversation) and /agents panel (monitor/approve background subagents), plus desktop Manager Surface. Not confirmed-absent; unfound after real search.
- Permissions: fine-grained action(target) resource strings in allow/deny/ask lists in settings.json, /permissions presets. **Replaces policies.toml denylist model → Triforge policies.toml needs a syntax rewrite on migration.**
- Config: ~/.gemini/antigravity-cli/settings.json; ~/.gemini/config/mcp_config.json (global MCP) / .agents/mcp_config.json (workspace MCP). Still under ~/.gemini/, NOT ~/.antigravity/.

## Models
- Gemini CLI OSS still advertises Gemini 3 models.
- **Antigravity CLI defaults to Gemini 3.5 Flash** (medium thinking), selectable via /model. Corroborated by raw GitHub issue #27858 (2026-06-12): Antigravity removed Gemini CLI's automatic Pro/Flash routing — users must pin a single model. VERIFIED.
  → Conflicts with user's standing never-Flash preference: every agy invocation/agent def must pin latest Pro explicitly.
- **Gemini 3.5 Pro GA unclear**: Google blog (2026-05-20) said rollout "next month"; forum thread suggests slipped; no primary GA confirmation found. Check ai.google.dev/gemini-api/docs/models before depending. (Until then, latest Pro = gemini-3.1-pro line.)
- thinking_level replacing thinking_budget (default high→medium): UNVERIFIED, secondary only.

## Migration (official guide antigravity.google/docs/gcli-migration, read directly)
- First agy launch with legacy config → interactive onboarding: auto-converts extensions/config, migrates tokens to OS keyring.
- **`agy plugin import gemini`** — converts extensions to plugins with per-item report (skills/agents/commands/mcpServers).
- Unchanged: GEMINI.md / AGENTS.md workspace rules + ~/.gemini/GEMINI.md global context.
- Breaking path changes: global skills ~/.gemini/skills/ → ~/.gemini/antigravity-cli/skills/; workspace skills .gemini/skills/ → .agents/skills/ (manual rename); MCP inline settings.json → mcp_config.json files; MCP url/httpUrl key → serverUrl.
- Real-user regressions (#27858): auto Pro/Flash routing gone; Shift+Tab auto-edit toggle replaced by Artifact Review settings menu.
- Minimum versions: not stated (UNVERIFIED).
- Automation impact: shells to `gemini` on affected tiers broke 2026-06-18 with NO grace period; enterprise/API-key unaffected.

## Open follow-ups (load-bearing, verify during planning)
1. Does agy have any agent-teams//goal equivalent (or is Manager Surface desktop-only)?
2. Hook event-name parity gemini↔agy; do hooks fire under `agy -p`?
3. Gemini 3.5 Pro GA status at implementation time.
4. Which auth mode Triforge users actually use (determines whether legacy gemini path still works as fallback).
