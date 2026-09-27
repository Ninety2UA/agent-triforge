# ADR: CLI deprecation watch — six-CLI update cycle 2026-09-11 → 2026-09-27

**Date:** 2026-09-27
**Status:** Proposed. This was a manual cycle; the adoption sprint follows after user review. D-037 and D-038 carry decisions the user has already taken.
**Tested against:** probe record `ops/research/2026-09-probe-record.md` (2026-09-27 21:19 UTC). Versions in that record:
- Claude Code 2.1.283
- Antigravity `agy` 1.2.12
- Codex 0.155.1
- OpenCode 1.18.30
- Kimi Code 0.42.0 (AUTH-FAIL)
- Cursor `2026.09.10-fd3934a`

The lead also re-probed on this host with Codex 0.155.1 and agy 1.2.2 (LEAD-01…15 in the report, §4 Q4).

## Context

Gap-analysis report `ops/research/2026-09-27-cli-updates.md` covers the third `/cli-watch` cycle and six research questions that feed the plan to let the user choose Claude Code **or** Codex as lead orchestrator.

The fresh record has 88 probes: 68 PASS · 12 FAIL · 1 AUTH-FAIL · 1 PENDING-U15 · 4 PENDING-AUTH · 2 INFO. Diffed against the 2026-09-12 version at `HEAD`, seven rows flip:
- AGY-08 FAIL→PASS
- CUR-12 PASS→FAIL
- KIMI-05 QUOTA-FAIL→AUTH-FAIL
- KIMI-06/08/09 and SELF-06e SKIPPED-GATED→PENDING-AUTH

CC-03 stays PASS but moves from 2/3 to 3/3. One harness row, CC-06, is contradicted by a lead re-run and is recorded as a false green (D-039).

> **User decisions recorded (2026-09-27).**
> 1. Triforge ships **only AGENTS.md** (no CLAUDE.md).
> 2. The Claude Code floor rises to **2.1.277**, the first build that reads AGENTS.md.
>
> D-037 and D-038 carry these. They supersede the CLAUDE.md-centric parts of prior decisions explicitly below.
>
> **User instruction recorded.** OpenAI's effort guidance for `gpt-6-astra` is recorded as a finding. The `xhigh` pin is **not** changed (D-044).

## Decisions

### D-037. Claude Code floor → 2.1.277 (user-directed); `opus` rung → Opus 5.5 — **ADOPT**

**Evidence:**
- 2.1.277 added AGENTS.md support ([CHANGELOG](https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md)).
- 2.1.280 made **Claude Opus 5.5** (`claude-opus-5-5`, 1M context, default effort `medium`) what the `opus` alias resolves to on the Anthropic API ([model-config](https://code.claude.com/docs/en/model-config)).
- `fable` still resolves to Fable 5.1 (CC-02 PASS).
- Probe CC-01 PASS on 2.1.283.

**Changes:**
- Floor ≥ 2.1.277 in the Compatibility table, `/setup`, and `README.md`.
- The ladder names the `opus` rung "Opus 5.5 (≥ 2.1.280; Opus 5 on 2.1.277–2.1.279)" in all four byte-identical ladder copies, with a new ladder md5.
- `effort` frontmatter docs list Opus 5.5 among the `max`-capable models.
- Shipped agents already pin `effort:` explicitly, so the `medium` default does not reach them.

**Supersedes:** the Claude row of D-034 and the `opus`-rung wording of D-020. The Fable top rung stands.

**Affects:** `.claude/CLAUDE.md` (→ AGENTS.md, D-038), `templates/CLAUDE.md`, `agents/team-lead.md`, `skills/wave-orchestration/SKILL.md`, `README.md`, `commands/setup.md`, `scripts/validate-versions.sh`.

### D-038. Ship AGENTS.md only; no CLAUDE.md — **ADOPT (user-directed)**

**Primary-source constraints the adoption must honor:**
1. **Claude** reads AGENTS.md **only when no `CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md` exists in the working directory or above it** ([memory](https://code.claude.com/docs/en/memory)).
   - The mode switch lives only in user/managed settings; "Claude Code ignores it in project and local settings files".
   - This repo's own `.claude/CLAUDE.md` must go, and a user project's surviving CLAUDE.md silently suppresses Triforge's AGENTS.md.
   - Session-start may **warn**. It must never delete or rename a user's file, and never write their user settings (R18).
2. **Codex** reads AGENTS.md into a **32 KiB combined budget** across the root→cwd chain and truncates mid-file with no model-visible signal (`project_doc_max_bytes`; `core/src/agents_md.rs`).
   - The replacement for this repo's 57,066-byte `.claude/CLAUDE.md` must be ≤ 32 KiB. Move reference sections (plugin tree, frontmatter catalog, six-harness matrix, release checklist) into `docs/` and link them.
   - `templates/CLAUDE.md` (16,508 B) fits.
3. **Discovery side effect.** Claude auto-loads a subdirectory `AGENTS.md` when it Reads a file there. `ops/AGENTS.md` (the protocol file) will now load on the first read under `ops/`. Keep it short.
4. **Harness alignment:**
   - OpenCode V2 dropped its CLAUDE.md fallback and reads only AGENTS.md.
   - Cursor reads root AGENTS.md and CLAUDE.md as rules.
   - Kimi and agy read AGENTS.md.

   AGENTS.md-only is the one file every harness shares.
5. **Release gate.** Retarget the ladder byte-identity set in `validate-versions.sh` from `.claude/CLAUDE.md` + `templates/CLAUDE.md` to their AGENTS.md successors.
6. **Open verification.** No primary source states that `claude -p` loads AGENTS.md; `-p` "loads the same context as an interactive session". Add a CC row: a fixture with only AGENTS.md, marker visible under `-p`.

**Affects:** `.claude/CLAUDE.md`, `templates/CLAUDE.md`, `hooks/handlers/session-start.sh` (bootstrap + warn), `commands/setup.md`, `scripts/validate-versions.sh`, `README.md`, `docs/`.

### D-039. Release gate red: quote `${CLAUDE_PLUGIN_ROOT}`; fix the CC-06 false green — **ADOPT**

**The failure:**
- Since 2.1.281, `claude plugin validate` warns on unquoted `${CLAUDE_PLUGIN_ROOT}` in shell-form hooks, and `--strict` fails on warnings.
- Lead re-run 2026-09-27 on 2.1.283: `validate --strict .claude-plugin/plugin.json` → ✘ "Found 4 warnings", one per command in `hooks/hooks.json:9,20,24,35`.
- `validate --strict .claude-plugin/marketplace.json` → ✔.

**The false green:** CC-06 PASS because `scripts/probe-capabilities.sh:1528` validates `"$REPO_ROOT"`, which resolves to the marketplace manifest only.

**Changes:**
- Quote the placeholder (`bash "${CLAUDE_PLUGIN_ROOT}/hooks/handlers/…"`) or use exec form.
- Make CC-06 validate both manifests, as release checklist item 1 already requires. This is a protected-path edit, so the lead or the user reviews it. It was not made this cycle, by instruction.

### D-040. Claude Code primitive churn — **DOCUMENT**

- `omitClaudeMd` frontmatter (2.1.271): add it to the frontmatter field list. It is not adopted: under D-038 it is undocumented whether it also omits AGENTS.md.
- The following have no Triforge usage (grep of `agents/`, `commands/`, `skills/`, `scripts/` found none), so no action:
  - TaskOutput tool removed (2.1.277);
  - Monitor `persistent` removed (2.1.271);
  - agent-type `PermissionRequest` hooks error (2.1.280);
  - reserved-name marketplaces refused (2.1.280; `agent-triforge` passes, CC-06 marketplace ✔).
- `--agents` now accepts a JSON file path (2.1.281). Noted for the lead-choice plan.

### D-041. `/goal` promoted from best-effort to a required gate — **ADOPT (supersedes D-030)**

- The D-030 open watch pre-set the trigger: "CC-03 passes 3/3 on a future build → promote to a hard gate". **CC-03: 3/3 runs gated on 2.1.283** (was 2/3 on 2.1.269). This follows the 2.1.269 and 2.1.274 `/goal` reliability fixes.
- **Change:**
  - `scripts/coordinate.sh` and `/ship`/`/coordinate` present the `/goal` line as required, not advisory.
  - `ops/.sprint-complete` stays the authoritative, headless-observable completion detector.
- **Revert** to best-effort if CC-03 falls below 3/3 in a later record.

### D-042. Antigravity routing default → `auto` — **ADOPT (KTD10 condition met)**

- KTD10: "the default flips to `auto` only after AGY-12 (native round-trip) and AGY-16 (native-mode negative) have passed for a full cycle." Both PASS in the 2026-09-12 record and again in the 2026-09-27 record (AGY-03 lists all four Triforge agents).
- A second reason: agy 1.2.7 removed `find_by_name`/`grep_search`/`list_dir` from the **default** toolset. Injection mode runs the default agent, while the native agent files (`antigravity-agents/agents/*.md:8`) list those tools explicitly.
- **Change:** `TRIFORGE_AGY_MODE` default `injection` → `auto` in `scripts/lib/antigravity.sh`; docs.
- The `<out>.mode` sidecar and the `ops/` header keep the change attributable.
- **Revert** on any AGY-12/16 regression.

### D-043. agy headless contract changes; AGY-08 PASS again — **ADOPT (signal) + DOCUMENT (hooks)**

**Changes in the window:**
- 1.2.6: model/agent failures exit **3** and print `AGY_ERROR: {status, code, retryable, id}` on stderr. The default `-p` timeout is unlimited.
- 1.2.9: headless runs kill daemon children at exit.
- 1.2.10: partial-stream-then-error exits 3 (was 0), and the JSON error output includes the partial response.

**Where Triforge stands:** it already fails these closed. `antigravity.sh:147-151` routes non-zero exits to `_classify_invoke_failure`, and `--print-timeout` is always passed (`:122`).

**Changes:**
- Parse `AGY_ERROR` retryability in the non-zero branch rather than regex-classifying stderr.
- Optionally keep the partial response as degraded output.

**Hooks:** **AGY-08 PASS** on 1.2.12, with all five events firing. This is consistent with 1.2.4's fix for "`hooks.json` silently dropped under token-budget truncation". Update the Security-model "open watch" text. Triforge still ships and relies on no agy hooks, and D-018's deny/sandbox FAILs stand (AGY-09, AGY-10 FAIL).

### D-044. Codex pin stays `gpt-6-astra` at `xhigh`; effort guidance recorded — **DOCUMENT**

**The pin:**
- `gpt-6-sol`/`gpt-6-luna` arrived (0.156.1 hotfix, 0.157.0). The bundled catalog still ranks Astra first, and the docs call it "our most capable model". No migration targets Astra.
- Per the user's rule (latest flagship), the pin stays.

**OpenAI guidance, recorded as a finding:**
- "**Light** for Astra … Astra's Light setting is `low`" ([models](https://learn.chatgpt.com/docs/models.md)).
- Reviewers at `high` ([subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)).
- `xhigh` "only when your evals show a clear benefit", with code review named among the use cases ([reasoning](https://developers.openai.com/api/docs/guides/reasoning.md)).

**Pin unchanged by user instruction.** CDX-03/05/06/07/08 PASS on 0.155.1. The host is two minors behind (0.157.1); re-probe after upgrade.

### D-045. Codex AGENTS.md trust wording corrected — **ADOPT (doc fix; partially corrects D-026's text)**

**What the source says:** the 0.150.0 gate ("Untrusted projects no longer supply project-level `AGENTS.md`", PR #39837) tests `is_untrusted()`, i.e. **explicit** `trust_level = "untrusted"`. When trust is unset, project AGENTS.md still loads. `.codex/config.toml`, hooks, and `.rules` are different: they skip when trust is unset.

**What Triforge's docs say:** `.claude/CLAUDE.md` (Security model: "and project `AGENTS.md` since 0.150 … unset means untrusted") and its Compatibility known-fails merge the two.

**Change:** split the sentence in those docs and in `templates/.codex/README.md`. CDX-10 PASS (trust entry present, root AGENTS.md marker visible) is consistent. D-026's remaining content stands.

### D-046. Codex native custom agents do not reverse D-026 — **DOCUMENT (D-026 stands)**

**The native schema:** one agent per file in `.codex/agents/<name>.toml` with `name`, `description`, `developer_instructions`, plus config keys ([subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents); `agent-roles/src/agent_role_config.rs`, `deny_unknown_fields`).

**Why it doesn't fit Triforge's dispatch:**
- These agents are **spawn targets only**. `codex exec` has no agent selector (0.155.1–0.157.1).
- Children re-apply the parent's live sandbox/approval overrides.
- The project directory is trust-gated.
- Triforge's `tools` array collides with Codex's `tools` table.

The replay model in `scripts/lib/codex.sh` remains correct. Native agents become relevant only if a **Codex lead** should spawn Triforge roles as subagents, which is scoped to the lead-choice plan.

### D-047. Codex-as-lead execution profile — **DOCUMENT (input to the lead-choice plan)**

**Lead re-probes** (Codex 0.155.1, macOS Seatbelt, `codex sandbox -c sandbox_mode="workspace-write"`):
- `.git` is read-only: `git worktree add` and `commit` both fail (LEAD-02/03).
- `$HOME` writes are denied (LEAD-04).
- Network is off by default; `network_access=true` enables it (LEAD-06/07).
- Nested Seatbelt fails (LEAD-08).
- Workers:
  - `claude -p` works (LEAD-12);
  - `agy` works degraded, with state-write denials (LEAD-13);
  - **`codex exec` workers cannot start at all** (LEAD-14/15: in-process app-server init denied).

**Documentation supporting this:** "Subagents inherit your current sandbox policy". Non-interactive approvals fail, and `codex exec` forces `approval_policy = never`.

**Recommended profile for a Codex lead:** `-s danger-full-access -c approval_policy="never" -c background_terminal_max_timeout=900000`. Long worker jobs are polled via unified-exec `write_stdin`. Use `-s danger-full-access`, not `--yolo`, since `--yolo` also skips the git-repo check. Safety rests on leases, cross-review, and the env allowlist.

**Hardened alternatives (probe targets, not adopted):**
- `workspace-write` + network + user-tier execpolicy `allow` rules for an out-of-workspace dispatch wrapper;
- a permission profile with `".git" = "write"`.

### D-048. One plugin tree for Claude Code and Codex — **DOCUMENT (input to the lead-choice plan)**

**What each host reads:**
- Claude Code reads only `.claude-plugin/plugin.json`.
- Codex resolves manifests in the order `.codex-plugin/` → **`.claude-plugin/plugin.json`** → `.cursor-plugin/`, and reads `.claude-plugin/marketplace.json` (`exec-server-protocol/src/lib.rs`, `core-plugins/src/marketplace.rs`).

**Recommendation:**
- Keep the single `.claude-plugin/` manifest. Add `.codex-plugin/plugin.json` only for Codex-specific fields.
- **Never** add a root agent-plugins `plugin.json`: it becomes Codex's canonical manifest, and Claude Code ignores it.

**What carries over to Codex:**
- Shareable: `skills/`, and `hooks/hooks.json` (Codex sets `CLAUDE_PLUGIN_ROOT`; plugin hooks are trust-gated).
- Lossy: `commands/` become skills, and anything over 4,000 bytes is silently dropped. 9 of 17 Triforge commands exceed that.
- Claude-only: `agents/`, `settings.json`.
- Marketplace entries should add `policy.*` for Codex.

A live `codex plugin marketplace add` round-trip is an open watch.

### D-049. OpenCode V2 shipped: fail-closed guard now, port later — **ADOPT (guard) / DEFER (port)**

**What V2 changes:** V2 (npm `@opencode/cli`, 2026-09-11, same `opencode` binary; the V2 installer replaces V1):
- removes `run --command` and `--variant` (`-m p/m#variant`);
- defaults to a **shared per-user background service** that does not inherit the caller's `env -i` environment (use `--standalone`);
- rejects asks and exits 1 without `--auto`;
- **does not read `OPENCODE_PERMISSION`**, so Triforge's deny set (`scripts/lib/opencode.sh`, `lease.sh:313-315`) would be silently dropped.

This is the D-033 open watch's "OpenCode V2 ships" trigger.

**Guard (adopt now):** `invoke_opencode` and the lease `opencode)` arm (`lease.sh:605-619`) refuse deterministically when the `opencode --version` major is ≥ 2, naming the V1 pin (`npm i -g opencode-ai@1`). `/setup` detects V2.

**Port (defer):** `--standalone`, `#variant`, `OPENCODE_CONFIG_CONTENT` with an ordered `permissions` array (`shell` not `bash`), and `.opencode/agents/`. It is its own sprint.

**Related:** D-033 stands. OC-06 still FAILs on 1.18.30, although a source reading says deny holds under `--auto`. The adapter stays off `--auto`. The npm package `opencode2` is a **third-party decoy**; never install it.

### D-050. Cursor Grok 4.7: fix the composer before moving the pin — **ADOPT (fix) / DEFER (pin)**

**Evidence:**
- Grok 4.7 shipped 2026-09-21.
- The host catalog lists `grok-4.7-{low,medium,high,xhigh}[-fast]` **without** the `cursor-` prefix that 4.6 ids carry (probe record Appendix B).
- **CUR-12 FAIL:** "Cannot use this model: cursor-grok-4.7-xhigh". Both `roster_write_role` (`scripts/lib/roster.sh:664-667`) and `_cursor_model_for_effort` always emit `cursor-<family>-<effort>`.
- CUR-05 PASS on bare `grok-4.7`.

**Change:** the composers take the prefix from the catalog form (or keep it as written).

**Pin:** stays `cursor-grok-4.6-xhigh`, which is valid, until CUR-12 PASSes on `grok-4.7-xhigh`. The installer still links `cursor-agent` (D-025 resolver unchanged).

### D-051. Kimi 2.x: keep prompt confinement; live lane still unproven — **DOCUMENT**

- Kimi 0.43.0 → 2.1.1 made no change to Triforge's invoke shape (`-p`, `--output-format stream-json`, `--agent-file`, `-m kimi-code/k3`).
- PR #3879 (2.0.1) dropped the system-prompt line forbidding access outside cwd. 2.1.0's trust hardening was reverted in 2.1.1.
- `kimi-agents/builder.md:34-39` already states the worktree confinement explicitly; keep it.
- Don't recommend 2.1.0.
- **KIMI-05 AUTH-FAIL:** the subscription returns 403 "does not have access". It is no longer a quota block. KIMI-06/08/09 are PENDING-AUTH.
- Floor unchanged until the live lane passes.

### D-052. Watch-cycle tooling tier — **DOCUMENT**

Registry: `[cli.firecrawl]`, `[cli.chrome-devtools]`, `[cli.gh]`, `tier = "tooling"`, `cli_count = 9`. Changelog plus routing check only, per the registry rule.

| Tool | Installed | Routing check (2026-09-27) |
|---|---|---|
| firecrawl | 1.24.6 | `scrape --only-main-content` and `search` work |
| chrome-devtools-mcp | 1.10.1 | `new_page` → `list_pages` → `evaluate_script --pageId` works; omitting `--pageId` errors, as the skill already anticipates |
| gh | 2.97.0 (latest 2.101.0) | `gh api`, `gh release list/view`, `gh workflow run` work |

No gap analysis and no probe rows.

### D-053. Repo-mining adoptions — **DEFER to the sibling `/repo-watch` report**

`ops/research/2026-09-27-repo-mining.md` carries the adopt/defer recommendations, including goals (a) "short shared AGENTS.md" and (c) "Claude Code or Codex as lead". D-038, D-046, D-047, and D-048 are the CLI-side facts that report's candidates should be reconciled against.

## Prior-decision status (2026-09-11 cycle → now)

| Decision | Status |
|---|---|
| D-020 Fable 5.1 top rung; Opus 5 `opus` rung — ADOPT | **Fable stands** (CC-02 PASS); **`opus` rung superseded by D-037** (Opus 5.5) |
| D-021 `gpt-6-astra` at `xhigh` — ADOPT | **Stands** (D-044; guidance recorded, pin unchanged) |
| D-022 agy pin `Gemini 3.8 Flash (High)` — ADOPT | **Stands**: no newer Gemini (AGY-02) |
| D-023 OpenCode `glm-5.3` — ADOPT | **Stands**; `glm-5.3-prime` is an evaluate candidate |
| D-024 Kimi `kimi-code/k3`, `--agent-file` — ADOPT | **Stands** (KIMI-03 PASS); live rows PENDING-AUTH (D-051) |
| D-025 Cursor Grok 4.6 suffix; `cursor-agent` first — ADOPT | **Stands**; composer fix for 4.7 in D-050 |
| D-026 Codex trust gate, `triforge-agents.toml` — ADOPT | **Stands** (D-046; CDX-11 PASS); AGENTS.md trust **wording corrected** by D-045 |
| D-027 agy Markdown-agent pack — ADOPT | **Stands** (AGY-12/13/16 PASS) |
| D-028 probe harness corrections — ADOPT | **Stands**; new harness gap CC-06 (D-039) |
| D-029 `.agents/skills/` refresh + matrix — ADOPT | **Stands** (AGY-14, OC-07, CC-07b) |
| D-030 `/goal` best-effort — DOCUMENT | **Superseded by D-041** (CC-03 3/3, pre-set trigger) |
| D-031 Claude operational corrections — ADOPT | **Stands** |
| D-032 agy `read_url` asks; exit 0 ≠ complete — ADOPT | **Stands** (AGY-15 PASS, `denied_actions: read_url`); extended by D-043 |
| D-033 OpenCode deny vs `--auto` — DEFER | **Stands (DEFER)**: OC-06 FAIL again; V2 trigger handled in D-049 |
| D-034 floors — DOCUMENT | **Claude row superseded by D-037** (≥ 2.1.277); others stand |
| D-035 registry corrections — ADOPT | **Stands**; new soft flags in the report §8 |
| D-036 repo-mining — DEFER | **Carried (D-053)** |

## Verification record

| Probe | Outcome | Date | Method |
|---|---|---|---|
| CC-01 version | PASS: 2.1.283 | 2026-09-27 | direct |
| CC-02 Fable alias | PASS (READY) | 2026-09-27 | live |
| CC-03 `/goal` gating (3-run) | **PASS 3/3** (was 2/3) → D-041 | 2026-09-27 | live |
| CC-06 `validate --strict` | PASS (record), but **marketplace-only** → false green (D-039) | 2026-09-27 | validate |
| LEAD `validate --strict .claude-plugin/plugin.json` | **FAIL**: 4 unquoted-`${CLAUDE_PLUGIN_ROOT}` warnings (2.1.283) | 2026-09-27 | lead re-run |
| LEAD `validate --strict .claude-plugin/marketplace.json` | PASS | 2026-09-27 | lead re-run |
| CC-07 / CC-07b skills | PASS / INFO (`.agents/skills` not a Claude path) | 2026-09-27 | live |
| CC-08 `claude -p` under lease `env -i` | PASS | 2026-09-27 | live |
| AGY-01 version | PASS: 1.2.12 | 2026-09-27 | direct |
| AGY-02 model pick | PASS: `Gemini 3.8 Flash (High)`; newest Pro `3.1 Pro (High)` | 2026-09-27 | direct |
| AGY-08 headless hooks | **PASS** (was FAIL on 1.2.1): all 5 events fired | 2026-09-27 | live |
| AGY-09 / AGY-10 deny / sandbox | FAIL / FAIL (unchanged; adapter never passes skip-permissions) | 2026-09-27 | live |
| AGY-12 / AGY-16 native round-trip / negative | PASS / PASS (2nd consecutive record) → D-042 | 2026-09-27 | live |
| AGY-15 JSON envelope | PASS (`denied_actions: read_url`) | 2026-09-27 | live |
| CDX-01 version | PASS: 0.155.1 | 2026-09-27 | direct |
| CDX-03/05/06/07/08 Astra READY, schema, max, ultra, read-only | PASS ×5 | 2026-09-27 | live |
| CDX-04 hooks under exec | PASS | 2026-09-27 | live |
| CDX-10 AGENTS.md visible with trust entry | PASS | 2026-09-27 | live |
| CDX-11 no malformed-role warning | PASS | 2026-09-27 | live |
| LEAD-02/03 `git worktree add` / `commit` under workspace-write | FAIL / FAIL (`.git` read-only) | 2026-09-27 | lead re-probe (`codex sandbox`) |
| LEAD-04/05 `$HOME` write / read | FAIL / PASS | 2026-09-27 | lead re-probe |
| LEAD-06/07 network default / `network_access=true` | FAIL / PASS | 2026-09-27 | lead re-probe |
| LEAD-08/09 nested sandbox read-only / danger-full-access | FAIL (`sandbox_apply`) / PASS | 2026-09-27 | lead re-probe |
| LEAD-11 `git worktree add` under danger-full-access | PASS | 2026-09-27 | lead re-probe |
| LEAD-12/13 `claude -p` / `agy` READY under workspace-write + net | PASS / PASS-degraded (23 state-write denials) | 2026-09-27 | lead re-probe (live) |
| LEAD-14/15 `codex exec` worker under workspace-write + net | FAIL / FAIL (app-server init denied) | 2026-09-27 | lead re-probe (live) |
| OC-01 version | PASS: 1.18.30 (V1) | 2026-09-27 | direct |
| OC-04 / OC-05 GLM pin / `--variant` | PASS / PASS (V1 only; `--variant` removed in V2) | 2026-09-27 | live |
| OC-06 deny under `--auto` | FAIL (unchanged) | 2026-09-27 | live |
| KIMI-05 READY | **AUTH-FAIL** (was QUOTA-FAIL): 403 subscription access | 2026-09-27 | live |
| KIMI-06/08/09 | PENDING-AUTH | 2026-09-27 | gated |
| CUR-03 model list | PASS: family `grok-4.7`; ids `grok-4.7-*` un-prefixed | 2026-09-27 | direct |
| CUR-05 bare `grok-4.7` | PASS (READY) | 2026-09-27 | live |
| CUR-10 bracket form rejected | PASS (negative holds) | 2026-09-27 | live |
| CUR-12 composed `cursor-grok-4.7-xhigh` | **FAIL** (was PASS on 4.6) → D-050 | 2026-09-27 | live |
| SELF-01…09 script invariants | PASS (SELF-04 INFO; SELF-06e PENDING-AUTH) | 2026-09-27 | harness |
| RTN-01 scheduled Routine env | PENDING-U15 | 2026-09-27 | deferred |

## Open watches

| Risk | Source | Trigger to revisit |
|---|---|---|
| `claude -p` loads AGENTS.md (undocumented) | upstream + harness | New CC row: AGENTS.md-only fixture marker visible under `-p` (D-038) |
| A user's CLAUDE.md suppresses Triforge's AGENTS.md | host | Session-start warning fires in the field; upstream adds a project-tier mode switch |
| Codex AGENTS.md > 32 KiB silently truncated | upstream | `wc -c AGENTS.md` ≥ 32768 in the release gate; upstream changes `project_doc_max_bytes` |
| CC-06 false green | harness | CC-06 rewritten to validate both manifests (D-039) |
| `/goal` gating regresses | upstream | CC-03 < 3/3 → revert D-041 |
| agy native routing regresses | harness | AGY-12 or AGY-16 FAIL → revert D-042 |
| agy exit/timeout semantics keep moving | upstream | Any release touching `AGY_ERROR`, rc 3, or `--print-timeout` |
| OpenCode V2 on a Triforge host | upstream + host | `opencode --version` ≥ 2 → guard fires (D-049); port sprint when V2 becomes the only supported line |
| Cursor Grok 4.7 pin | harness | CUR-12 PASS on `grok-4.7-xhigh` → move the pin (D-050) |
| Kimi lane unproven live | host | Subscription regains Kimi Code access; KIMI-05/06/08/09 PASS |
| Codex-lead sandbox (candidate harness rows CDX-LEAD-*: `.git`-write profile, execpolicy allow wrapper, `write_stdin` 900 s poll, background survival past exec end) | harness | Lead-choice plan adopts a profile → add the rows before shipping it (D-047) |
| One-tree plugin install on Codex | harness | `codex plugin marketplace add` + `codex plugin add agent-triforge@agent-triforge` round-trip lists skills and hooks (D-048) |
| Hosts behind upstream (Codex 0.157.1, Cursor 09.26, Kimi 2.1.1, gh 2.101.0) | host | Upgrade → re-run the harness |
| `multi_agent_v2` default / #31097 | upstream | `codex features list` shows `multi_agent_v2 … true`, or #31097 closes |
| `--bare` default for `claude -p` | upstream | Release note flips the default |
| Mythos 5.1 GA | upstream | Model overview lists `claude-mythos-5-1` as GA |

Review on every minor version bump of any registry CLI. Full cycle monthly via `/schedule`. Keep the probe harness in the foreground in headless runs (see `.claude/commands/cli-watch.md`).

## References

- Gap-analysis report (this cycle): `ops/research/2026-09-27-cli-updates.md` (§4 answers the six lead-orchestrator research questions; §5 covers tooling)
- Fresh probe record: `ops/research/2026-09-probe-record.md` (2026-09-27); prior version at `HEAD` (2026-09-12)
- Sibling repo-mining report: `ops/research/2026-09-27-repo-mining.md`
- Prior cycle: `ops/research/2026-09-11-cli-updates.md`, `ops/decisions/2026-09-11-cli-deprecation-watch.md`; `ops/decisions/2026-07-18-codex-hooks-under-exec.md`
- Method: `.claude/commands/cli-watch.md`, `.claude/skills/watch-cycle/SKILL.md`; registry `ops/watch-registry.toml`
- Primary sources: full URL set in the report's §9 Sources appendix
