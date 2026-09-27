# Grok Build / Devin CLI / Pi (+ oh-my-pi) / Hermes Agent fact sheet — verified September 27, 2026

Researched by the lead plus four read-only research workers (one per CLI; no writes, no credential reads, no installs), from primary sources only: vendor docs, GitHub repos and releases, npm/PyPI registry metadata, and the docs shipped with the installed `grok` binary. Each claim is tagged VERIFIED (primary source, cited) or UNVERIFIED. INFERENCE marks the lead's own reasoning from verified facts. Candidate tier: **optional** (like OpenCode, Kimi and Cursor). The lead stays Claude Code or Codex.

**Live evidence.**
- `grok` 1.0.34: `--version`, `--help` on the CLI and its subcommands, and **one READY probe** (below).
- `devin` 3000.11.3: `--version`, `--help` on the CLI and its subcommands, and `devin auth status`. The status came back **not logged in**, so no Devin READY probe was run (§2).
- Pi, oh-my-pi and Hermes Agent: docs only, never run.

**Upfront flags.**
- **Expected concurrent activity.** The user installed Devin CLI during this session (Homebrew cask `devin-cli` 3000.11.3 at `/opt/homebrew/bin/devin`, 2026-09-27 23:36). `ops/decisions/2026-09-27-cli-deprecation-watch.md` and `ops/research/2026-09-27-cli-updates.md` come from the lead's parallel `/cli-watch` session. Neither came from this research.
- **Pi has moved.** badlogic/pi-mono → **earendil-works/pi**. npm `@mariozechner/pi-coding-agent` is deprecated.
- **Hermes Agent** means **Nous Research's** project. Several unrelated products share the name (see §4).
- **Look-alike packages exist for all four.** Listed under "Flagged sources" at the end.

### Probe run by this research

```
env -i HOME PATH TMPDIR TERM LANG USER NO_COLOR=1 GROK_DISABLE_AUTOUPDATER=1 GROK_CLAUDE_{HOOKS,MCPS,SKILLS,RULES,AGENTS}_ENABLED=0 \
  timeout 150 grok -p "Respond with only: READY" -m grok-4.7 --effort high --output-format json \
  --max-turns 2 --no-subagents --permission-mode dontAsk --cwd <mktemp -d>   </dev/null
```

Result: **rc=0 in 4 s**. The JSON envelope was `{"text":"READY","stopReason":"end_turn","sessionId":…,"requestId":…,"thought":…,"usage":{"input_tokens":32674,…},"num_turns":1,"total_cost_usd":0.06636,"modelUsage":{"grok-4.7":{…}}}` and stderr was empty. Two side effects:
- `~/.grok/auth.json` was rewritten at probe time (23:45:06), so the cached OAuth login refreshed itself with no one present.
- A session was persisted under `~/.grok/sessions/<url-encoded cwd>/`.

The login was the user's existing cached `grok login`; `XAI_API_KEY` was unset.

### Gating verdicts at a glance

| CLI | Q1 Headless + pinned model | Q2 Trustworthy completion signal | Q3 Lease-worktree confinement | Q4 Unattended login | Recommendation |
|---|---|---|---|---|---|
| Grok Build (`grok`) | **PASS** (live) | **PARTIAL** | **PARTIAL** | **PASS** (live) | **Enroll as optional worker** (probe cycle first) |
| Devin CLI (`devin`) | **PARTIAL** (flags live) | **FAIL** (flags live) | **PARTIAL** | **PARTIAL** (not logged in on this host) | **Skill/plugin manifest only** |
| Pi (`pi`) / oh-my-pi (`omp`) | **PASS** / **PASS** | **PARTIAL** / **PARTIAL** (omp RPC stronger) | **FAIL** / **FAIL** | **PASS** / **PASS** | **Skill manifest only** (Pi); **skip** omp |
| Hermes Agent (`hermes`) | **PASS** | **PARTIAL** | **PARTIAL** | **PARTIAL** (credential-adoption hazard) | **Skip for now** |

Reference point for Q2 is agy's JSON envelope, read by `_agy_parse_envelope` in `scripts/lib/antigravity.sh`. It exposes `status`, `response` and `denied_actions`, and an empty response plus denials counts as a deterministic failure, because exit codes lie. Reference point for Q3 is `_adapter_env` in `scripts/lib/lease.sh`: the adapter runs under `env -i` with a per-adapter allowlist, and a `GIT_CONFIG_*` no-push backstop (pre-push hook plus `pushInsteadOf` → `no-push://`) rides the process environment.

---

## 1. Grok Build CLI (xAI) — `grok`

- **(a) Identity, version, license.**
  - The official product is "Grok Build", binary `grok`, source at **github.com/xai-org/grok-build**: Apache-2.0, Rust, mirrored from xAI's internal monorepo, no outside contributions, no GitHub releases or tags. VERIFIED (`gh api repos/xai-org/grok-build`, README). The shipped `~/.grok/README.md` also says Apache-2.0. VERIFIED (local, installed docs).
  - Install options: `curl -fsSL https://x.ai/cli/install.sh | bash` (pin with `bash -s X.Y.Z`), `irm https://x.ai/cli/install.ps1 | iex`, or `npm i -g @xai-official/grok`. VERIFIED (https://docs.x.ai/build/overview, https://docs.x.ai/build/enterprise).
  - The changelog's newest entry is **1.0.40** (2026-09-20, "Grok 4.7 has arrived!"). npm `latest` is **1.0.41** (2026-09-22) and `alpha` is 1.0.42 (2026-09-26). There are 228 versions since 2025-10-22, published by `xai-security <security@x.ai>`. Release channels are stable, alpha and enterprise; releases come about daily. VERIFIED (https://x.ai/build/changelog; registry.npmjs.org/@xai-official%2Fgrok).
  - The installed version is **1.0.34** (`grok 1.0.34 (3736acbc8658) [stable]`). VERIFIED (live `--version`).
- **(b) The `agent` binary clash.** The installer symlinks both `~/.grok/bin/grok` and `~/.grok/bin/agent` to the same binary. VERIFIED (live: `ls -la ~/.grok/bin`, `agent --version` → `grok 1.0.34 …`; the worker's read of install.sh). `_cursor_bin` (`scripts/lib/cursor.sh:88`) requires `YYYY.MM.DD-<hex>`, so it rejects this `agent`. That is consistent with probe row CUR-11 PASS in `ops/research/2026-09-probe-record.md`. VERIFIED.
  - The installer does no checksum or signature verification; it runs `--version` on the download only. VERIFIED (worker read of https://x.ai/cli/install.sh, not executed).
- **(c) Q1, headless with a pinned model: PASS.**
  - One-shot: `grok -p/--single "<prompt>"`, or `--prompt-file <PATH>` / `--prompt-json <JSON>`. Model: `-m/--model <ID>`. Effort: `--reasoning-effort`/`--effort <none|minimal|low|medium|high|xhigh|max>`, but a model accepts only the levels its own menu lists. Also `--max-turns N`, `--cwd`, `--tools`, `--disallowed-tools` (including `Agent`), `--no-subagents`, `--no-plan`, `--verbatim`, and `--rules`. VERIFIED (live `grok --help` 1.0.34; https://docs.x.ai/build/cli/headless-scripting; https://docs.x.ai/build/cli/reference).
  - The API lists grok-4.7, 4.6, 4.5, 4.3, grok-4.20-0309-(non-)reasoning, grok-4.20-multi-agent-0309 and grok-build-0.1 (256k). VERIFIED (https://docs.x.ai/developers/models.md). grok-4.7 accepts low, medium, high (default) and xhigh. VERIFIED (https://docs.x.ai/developers/grok-4-7.md).
  - `-m grok-4.7 --effort high` answered READY on 1.0.34. VERIFIED (live probe above).
  - **The default model is contested.** The grok-4.7 page says 4.7 is the coding agent's default, the settings example shows `grok-build`, and the repo user guide says `grok-4.5`. UNVERIFIED which one ships, so always pin `-m`.
  - `grok models` lists the catalog. It was not run: outside the probe budget.
- **(d) Q2, completion signal: PARTIAL.**
  - `--output-format plain|json|streaming-json|streaming-messages-json`. The last is Anthropic Messages wire format, the same as Claude's stream-json. VERIFIED (live `--help`).
  - `json` returns one object: `text`, `stopReason` (`end_turn`, `max_tokens`, …), `sessionId`, `requestId`, and optionally `thought`, `num_turns`, `usage`, `modelUsage`, `total_cost_usd`, `cost_is_partial`, `usage_is_incomplete`. A failure prints `{"type":"error","message":…}` and exits non-zero. VERIFIED (live probe; repo guide https://raw.githubusercontent.com/xai-org/grok-build/main/crates/codegen/xai-grok-pager/docs/user-guide/14-*.md, synced 2026-09-23).
  - `streaming-json` event types: `text`, `thought`, `tool_call`, `tool_call_update` (with `status`), `usage`, `plan`, `end`, `error`, `max_turns_reached`, `auto_compact_*`. `end` is always last, and `end.stopReason` ∈ {end_turn, max_tokens, max_turn_requests, refusal, cancelled}. VERIFIED (repo guide 14).
  - Exit codes: 0 ok; 1 auth, network or runtime error; 130 SIGINT; 143 SIGTERM. VERIFIED (repo guide 14). The exit code for max-turns, refusal or a denial is UNVERIFIED (probe it).
  - **Denials are not collected.** The docs say Grok "omits the schema's always-empty `permission_denials`, because it does not collect permission denials". A blocked call goes back to the model as a tool failure. It shows only in `tool_call_update.status` (streaming) or in a `PermissionDenied` hook. VERIFIED (repo guide 14/22; https://docs.x.ai/build/features/hooks.md). **Unlike agy there is no `denied_actions` field.** An adapter would parse `streaming-json` for the terminal `end.stopReason` plus failed `tool_call_update`s, and rely on the KTD11 typed `Status:` report for the verdict. INFERENCE.
  - Timeouts: the bash tool has a 120 s default and is auto-backgrounded when it times out. Inference idle timeout is 600 s. There is no run-level timeout, so Triforge's `timeout` wrapper covers that. VERIFIED (https://docs.x.ai/build/settings/reference.md).
  - CE hit two traps in headless JSON: camelCase `structuredOutput` (not `structured_output`), and a schema-shaped placeholder returned as the "final" answer on grok 1.0.4. VERIFIED (CE repo, secondary: `docs/solutions/integration-issues/grok-camelcase-structuredoutput-and-nonfinal-peer-position.md`).
- **(e) Q3, confinement: PARTIAL.**
  - `--permission-mode default|acceptEdits|auto|dontAsk|bypassPermissions|plan`. `dontAsk` silently denies anything not explicitly allowed, and `--always-approve` (alias `--yolo`) is bypass. VERIFIED (live `--help`; repo guide 22).
  - Rules: `--allow`/`--deny 'Bash(git push*)'`, `Read(src/**)`, `Edit(…)`, `WebFetch(domain:x)`, `MCPTool(…)`. Deny beats ask beats allow, and a deny beats always-approve. Deny is checked against every segment of a chained command, and wrappers such as `timeout`/`env`/`nice` are stripped before matching. VERIFIED (repo guide 22; `~/.grok/README.md` "Permission Rules").
  - **Prefix matching means `git -C . push` and `git -c k=v push` would slip past `Bash(git push*)`.** INFERENCE from the documented matching rules. The SELF-09 git-level backstop in `_adapter_env` remains the real push refusal. grok's bash tool inherits the process environment, so the `GIT_CONFIG_*` pairs apply. INFERENCE; also `[session] load_envrc = true` loads `.envrc` into bash commands (VERIFIED, `~/.grok/README.md` "General Settings"), which a lease should turn off.
  - Sandbox: `--sandbox off|workspace|read-only|strict|<custom>` (env `GROK_SANDBOX`), off by default, using Seatbelt on macOS and Landlock/bwrap on Linux. Custom profiles in `~/.grok/sandbox.toml` / `.grok/sandbox.toml` support a `deny` list. Child-network blocking **does nothing on macOS**, and if the sandbox cannot be applied grok warns and continues unconfined. VERIFIED (https://docs.x.ai/build/features/sandbox.md; `~/.grok/README.md` "Sandbox").
  - `workspace`/`strict` allow writes only under CWD (plus `/tmp` and `~/.grok`). A linked worktree keeps its index and refs in the main repo's `.git/worktrees/<name>`, so git writes may fail under the sandbox. INFERENCE (probe it).
  - **By default grok reads Claude Code config:** `~/.claude/settings.json` permission rules and **hooks** (user-tier hooks load "Always"), `~/.claude.json`/`.mcp.json` MCP servers, `~/.claude/skills`, Claude plugins, and CLAUDE.md. Each scan can be turned off with `GROK_CLAUDE_{SKILLS,RULES,AGENTS,MCPS,HOOKS}_ENABLED=0` or `[compat.claude]`; Cursor has an equivalent. VERIFIED (repo guide 10 and 22; https://docs.x.ai/build/settings/reference.md; `~/.grok/README.md` "Claude Code Compatibility").
  - Because the lease forwards `HOME`, a grok builder would otherwise run the user's global Claude Code hooks. This probe set all five variables to 0.
  - Workspace trust (`~/.grok/trusted_folders.toml`, or `--trust`) gates project hooks, MCP and LSP servers, project `.grok/config.toml`, project AGENTS.md and project skills. **Headless runs do not load these sources without `--trust` or a prior grant**, and `GROK_FOLDER_TRUST=0` removes the gate. VERIFIED (repo guide 10/12/22). A fresh lease worktree therefore loads no project AGENTS.md unless trusted; Triforge injects context in the prompt anyway (KTD-3).
  - `-w/--worktree` makes grok's own worktree under `~/.grok/worktrees/`. Triforge must not use it. VERIFIED (live `--help`).
- **(f) Q4, unattended login: PASS.**
  - Options: `XAI_API_KEY` (from console.x.ai, for CI; does not refresh), `grok login` (browser OAuth via auth.x.ai), `grok login --device-auth` (device code for headless or remote machines), `auth_provider_command` / `GROK_AUTH_PROVIDER_COMMAND`, or enterprise OIDC. VERIFIED (live `grok login --help`; `~/.grok/README.md` "Authentication"; https://docs.x.ai/build/enterprise).
  - Credentials live in `~/.grok/auth.json` (0600, relocatable via `GROK_HOME`). Precedence is `model.api_key` > `model.env_key` > session token > `XAI_API_KEY`, so **a cached login beats the env key**. VERIFIED (repo guide 02; enterprise.md).
  - The cached OAuth login authenticated and refreshed itself under `env -i` with only HOME/USER forwarded. VERIFIED (live probe).
  - The auth.json session token is shared by every lease; parallel refreshes could race. UNVERIFIED (no rotation-race statement found). If needed, `XAI_API_KEY` is the adapter-allowlist variable.
- **(g) Other capabilities.**
  - **Context files:** reads `AGENTS.md`/`Agents.md`/`AGENT.md` plus the CLAUDE.md family, `.grok/rules/`, `.claude/rules/` and `.cursor/rules/`, from the repo root down to CWD, trust-gated. VERIFIED (https://docs.x.ai/build/features/project-rules.md).
  - **Skills:**
    - Scans `.grok/skills`, `~/.grok/skills`, `.claude/skills`, `~/.claude/skills`, `.cursor/skills`, `~/.cursor/skills` and **`.agents/skills/` at each tier**, trust-gated. The online docs mention only `~/.agents/skills`. VERIFIED (repo guide 08); online/repo mismatch flagged.
    - The installed 1.0.34 README (2026-08-01 copy) lists no `.agents/skills`. This is an open watch.
  - **Plugins:**
    - `grok plugin install|marketplace|validate|…`; manifests are `.grok-plugin/plugin.json` and `marketplace.json`, and **`.claude-plugin/` manifests are also accepted**. The official marketplace is github.com/xai-org/plugin-marketplace. VERIFIED (live `grok plugin --help`; repo guide 09).
    - CE ships `.grok-plugin/{plugin,marketplace}.json` (a `skills: "./skills/"` pointer) and installs with `grok plugin install EveryInc/compound-engineering-plugin`. VERIFIED (CE repo, secondary: `.grok-plugin/`, README "Grok Build CLI").
    - So Triforge's existing `.claude-plugin/` would probably install as-is. UNVERIFIED.
  - **Hooks:**
    - Hook files: `~/.grok/hooks/*.json`, plus `.grok/hooks/` (trust-gated), plus Claude/Cursor hook files, plus `[[hooks.<Event>]]` in config.toml. VERIFIED.
    - Events: SessionStart/End, UserPromptSubmit, PreToolUse (the only one that can block), PostToolUse(+Failure), PermissionDenied, Stop/StopFailure, SubagentStart/Stop, Pre/PostCompact. VERIFIED.
    - **Hooks fail open on timeout or crash.** VERIFIED (https://docs.x.ai/build/features/hooks.md).
    - Headless firing under `-p` is UNVERIFIED.
  - **Subagents:** general-purpose, explore and plan. Whether they are enabled by default is contradictory: the docs say on, while settings/reference lists `GROK_SUBAGENTS` default 0. VERIFIED that the conflict exists. Leases should pass `--no-subagents`, which the probe used.
  - **MCP:** `grok mcp …`. VERIFIED.
  - **Other surfaces:** an ACP JSON-RPC mode (`grok agent stdio`) and `grok cursor-worker`, which registers the machine as a Cursor private worker. VERIFIED (live `--help`).
- **(h) Data egress (R36).**
  - Default traffic goes to **xAI**: `cli-chat-proxy.grok.com` for an OAuth login, `api.x.ai` with an API key, and `code.grok.com` for session sync/share. VERIFIED (enterprise.md; `~/.grok/README.md` env table).
  - BYOK `[model.<id>] base_url=…` can route to any provider. VERIFIED.
  - **xAI is already in Triforge's egress set via Cursor → Grok**, so enrolling grok adds no new provider under the default model. INFERENCE.
  - Coding-data training and retention are controlled by `/privacy`, with per-team ZDR. The consumer default is UNVERIFIED.
- **(i) Pricing and limits.**
  - API grok-4.7: $2 in / $6 out per 1M tokens under 200k context. Tier-0 rate limit: 150 RPS / 50M TPM. VERIFIED (https://docs.x.ai/developers/pricing.md, https://docs.x.ai/developers/rate-limits.md).
  - The Build CLI is "free to try", and SuperGrok Plus ($100/mo) advertises higher Build usage. VERIFIED (https://x.ai/pricing). Per-plan Build quotas are UNVERIFIED (the pricing table did not render).
  - **Cost note:** a bare READY used 32.7k input tokens and cost **$0.066**, most of it the system prompt. VERIFIED (live probe `total_cost_usd`).
- **(j) Fragility.**
  - **Auto-update is on by default.** Turn it off with `--no-auto-update` (not in the 1.0.34 help), `GROK_DISABLE_AUTOUPDATER=1` or `[cli] auto_update=false`; it is also suppressed when stderr is not a TTY. VERIFIED (repo guide 14; `~/.grok/README.md`).
  - **Telemetry:** `[features] telemetry` / `GROK_TELEMETRY_ENABLED`, plus trace upload (`GROK_TELEMETRY_TRACE_UPLOAD`). "Enterprise default is off"; the consumer default is UNVERIFIED. The local README says public-source builds carry no telemetry sinks. VERIFIED.
  - **Release cadence is near-daily.**
  - **Flag drift:** CE's adapter passes `--no-memory`, which is absent from 1.0.34 `--help`. VERIFIED (CE `skills/ce-work/scripts/cross-model-work.sh:142` vs live help).
  - **Look-alikes:** see "Flagged sources".

## 2. Devin CLI (Cognition) — `devin`

**Live checks (2026-09-27, in a `mktemp -d` directory).**
- `devin --version` → `devin 3000.11.3 (9c803229faa4)`, rc 0.
- `devin --help` and `--help` on auth, models, models list, sandbox, acp, doctor, update and migrate: all read.
- `devin auth status` → "Not logged in. Credentials path: ~/.local/share/devin/credentials.toml. Run `devin auth login` to authenticate." with **rc 0**.
- No login env var is set (`WINDSURF_API_KEY`, `DEVIN_API_KEY` unset).
- Because Devin is not logged in, **no READY probe was run**. The brief allowed a probe only if logged in, and no login was attempted.
- So `-p` exit codes, the output shape, timing, and the login-shell environment re-import all remain docs-only.

- **(a) Identity, version, license.**
  - It is a **local agent by default**. `--cloud` instead drives Devin Cloud sessions over WebSocket. VERIFIED (https://docs.devin.ai/cli, https://docs.devin.ai/cli/reference/commands, man `devin(1)`). The top-level help says "A fast and minimal agent that lives both in your terminal and in the cloud", and `--cloud` is described as "Drive Devin cloud sessions instead of the local agent … Requires a Devin account". VERIFIED (live `devin --help`).
  - The installed binary is **3000.11.3** (`9c803229faa4`), matching the latest release. VERIFIED (live `devin --version`).
  - **Closed source:** `CognitionAI/devin-cli` holds only a README, an install script and tags, with no license. VERIFIED (gh api).
  - Install: `curl -fsSL https://cli.devin.ai/install.sh | bash` (from static.devin.ai, SHA-256 checked) or `brew install --cask devin-cli`. VERIFIED.
  - Latest version is **3000.11.3** (2026-09-22 changelog; 2026-09-23 tag). Cadence is 2–4 releases a week. **The version scheme jumped from `2026.x.y` to `3000.x.y` around 2026-07-04**, which breaks naive version-floor parsing. VERIFIED (https://docs.devin.ai/cli/changelog/stable).
- **(b) Q1, headless with a pinned model: PARTIAL.**
  - `devin -p/--print [<PROMPT>]` ("Print response and exit … Runs in non-interactive mode") or `--prompt-file <FILE>`. VERIFIED (live `devin --help`). Internally it runs the agent in a `devin acp` child: the live `devin acp --help` says `devin -p` "agent runs in that child". VERIFIED (live; man `devin-acp(1)`).
  - Model: `--model <MODEL>` (env `DEVIN_MODEL`), with examples "claude-sonnet-4", "claude-opus-4.6", "opus", "codex". VERIFIED (live `devin --help`).
  - Short names (`opus`, `sonnet`, `swe`, `codex`, `gemini`) *float* to the newest model in the family, and the default is `swe-1-6-fast`. VERIFIED (https://docs.devin.ai/cli/models; config-file reference).
  - `devin models list --format text|json` lists the models available to the account. It is a machine-readable catalog, but needs a login. VERIFIED (live `devin models list --help`); not run.
  - **No effort, max-turns or timeout flag** exists in the live top-level help. VERIFIED (live `devin --help`; /cli/models; changelog v3000.10.21). Effort is set with REPL Alt+T, ACP session config, or per-family memory, so a pinned effort under `-p` is not possible from the command line. INFERENCE from the live flag set.
  - `--refusal-fallback` / `DEVIN_REFUSAL_FALLBACK` switches models when a provider refuses under its usage policy, and the env var "is the way to enable this for `devin` and `devin -p`". A lease must leave it unset, or the served model can silently drift from the pinned one. VERIFIED (live `devin acp --help`); the drift risk is INFERENCE.
- **(c) Q2, completion signal: FAIL.**
  - **`-p` has no `--output-format`, JSON or stream-JSON mode.** The full live option list is `--prompt-file`, `--config`, `--permission-mode`, `--sandbox`, `--cloud`, `--model`, `-p`, `--export`, `-c`, `-r`, `--respect-workspace-trust`, `-h`, `-V`, with no output-format flag. VERIFIED (live `devin --help`; man `devin(1)`, /cli/reference/commands).
  - Structured JSON exists only in side commands: `devin models list --format json` and `devin doctor --json`. VERIFIED (live `--help`). Neither is a run result.
  - `-p` exit codes are UNVERIFIED (undocumented, and not probed because Devin is not logged in). So is how a tool denial surfaces under `-p`.
  - `devin auth status` exits **0 while reporting "Not logged in."**, so a liveness check cannot use its exit code and must parse the text. VERIFIED (live).
  - Alternatives exist but none is a result envelope: `--export` in the undocumented "ATIF" format, the `devin acp` JSON-RPC mode, or `Stop` hooks that receive `last_assistant_message`. VERIFIED (/cli/extensibility/hooks/lifecycle-hooks).
  - `-p` fails in an untrusted directory unless run with `--respect-workspace-trust false` or `skip_workspace_trust`. VERIFIED (live `devin --help`: "Non-interactive (print) mode cannot show the trust prompt and fails in an untrusted directory"). A fresh lease worktree would need `--respect-workspace-trust false`.
  - An adapter would need an ACP client (`devin acp` over stdio), or would have to trust plain text plus the typed `Status:` line alone. INFERENCE. `devin acp --agent-type review` provides a built-in read-only-plus-shell code-review agent, a possible reviewer-role surface over ACP. VERIFIED (live `devin acp --help`).
- **(d) Q3, confinement: PARTIAL.**
  - The live `--help` lists four permission modes (env `DEVIN_PERMISSION_MODE`, default `auto`):
    - "auto" auto-approves read-only tools;
    - "accept-edits" also auto-approves workspace edits;
    - "smart" additionally auto-runs actions a fast model judges safe;
    - "dangerous" auto-approves all tools.

    VERIFIED (live `devin --help`). The docs also list `normal`, the aliases `bypass`/`yolo`, and `autonomous` (requires `--sandbox`); those are absent from the help text. VERIFIED (docs); live acceptance of the aliases is UNVERIFIED. Rules take the form `Read()`, `Write()`, `Exec(prefix)`, `Fetch()` and `mcp__*`; deny wins (fixed in v3000.10.31). Config order: org > session > `.devin/config.local.json` > `.devin/config.json` > `~/.config/devin/config.json`. `--config <PATH>` swaps the user config, which suits a per-lease config. VERIFIED (https://docs.devin.ai/cli/reference/permissions; man `devin(1)`).
  - `permissions.deny: ["Exec(git push)"]` is valid syntax. Whether user-level denies hold in bypass mode, and whether `bash -c 'git push'` evades them, are UNVERIFIED.
  - `--sandbox` (env `DEVIN_SANDBOX`) is a "[Research Preview]" that sandboxes exec-tool processes (Seatbelt / bwrap+seccomp). Commands "can write only within the workspace and granted `Write(...)` scopes, and can read everything except paths hidden by `Deny(Read(...))` rules". `devin sandbox setup` prints platform prerequisites. VERIFIED (live `devin --help`, `devin sandbox --help`).
  - The sandbox refuses to start if it cannot be applied, and in autonomous mode edit/write tools still prompt. VERIFIED (/cli/sandbox). A headless builder may therefore be unable to edit. UNVERIFIED.
  - The sandbox covers exec-tool processes only; the agent's own file tools are governed by permission rules. VERIFIED (live help wording "for the exec tool").
  - **It defeats `env -i`.** At startup Devin runs `$SHELL` as an interactive login shell and imports its exported variables, so secrets from `.zshrc`/`.bash_profile` come back. VERIFIED (docs, https://docs.devin.ai/cli/troubleshooting). That breaks the KTD-14 per-adapter env allowlist. **Not confirmed live:** no session was started, because Devin is not logged in. Devin's own logs for the two `auth status` runs show only `load_credentials` and `analytics_new` spans before dispatch, with no shell-environment step. So the re-import, if it happens, is tied to sessions, not to every command. VERIFIED (live, `~/.local/share/devin/cli/logs/devin_20260927-2349*.log`); the session-time behavior stays docs-only.
  - **It reads Claude Code config by default** (`read_config_from.claude=true`): CLAUDE.md, `.claude/skills`, `.claude/commands`, `~/.claude.json` MCP servers, and hooks from `.claude/settings*.json`. A Devin builder would pick up the lead-only CLAUDE.md and the Claude hooks. VERIFIED (https://docs.devin.ai/cli/reference/configuration/read-config-from).
  - It scans **`.agents/agents/`** for subagents, which is the directory Triforge never deploys to (KTD13). VERIFIED (https://docs.devin.ai/cli/subagents).
- **(e) Q4, unattended login: PARTIAL.**
  - `devin auth login|logout|status`. `login --force-manual-token-flow` will "Skip browser-based auth and paste a token manually — Useful for remote or SSH sessions where the localhost redirect won't work". VERIFIED (live `devin auth --help`, `devin auth login --help`). This is a paste-token flow, not a device-code poll, so it still needs a person once.
  - The token lives in `~/.local/share/devin/credentials.toml`. VERIFIED (live `auth status` names this path). It **does not expire** and can be copied between machines. VERIFIED (https://docs.devin.ai/cli/enterprise/devin-auth). A one-time login is therefore reusable by leases, but **this host is not logged in**. VERIFIED (live `auth status`).
  - `WINDSURF_API_KEY` is documented only for `devin acp`; whether `-p` honours it is UNVERIFIED. `DEVIN_API_KEY` is for the cloud API. Neither variable appears in the live `--help` text.
  - An account is required: Free (light quota), Pro $20 or Max $200 with daily/weekly quotas, or Enterprise ACUs with a per-user "Use Devin CLI" RBAC permission. VERIFIED (https://devin.ai/pricing; /cli/enterprise/devin-auth). Whether Free includes the CLI is UNVERIFIED.
- **(f) Other capabilities.**
  - **Rules:** `AGENTS.md`, `AGENTS.local.md`, `AGENT.md`, `CLAUDE.md`, `.windsurfrules` (32 KiB cap). VERIFIED (/cli/extensibility/rules).
  - **Skills:** **`.agents/skills/`**, `.devin/skills/`, `.windsurf/skills/`, `~/.agents/skills/`, `~/.config/devin/skills/`, plus imports from `.claude/skills`, `.github/skills` and `.cursor/skills`. VERIFIED (/cli/extensibility/skills/overview). Triforge's session-start `.agents/skills/` copy would reach Devin with no work.
  - **Plugins** (beta): lookup order is `.devin-plugin/plugin.json`, then **`.claude-plugin/plugin.json`**, then a root `plugin.json`. Installs are user-level and synced through Devin Cloud. VERIFIED (/cli/extensibility/plugins/overview). CE's `.devin-plugin/plugin.json` is a name/version/metadata-only manifest, and CE installs with `devin plugins install EveryInc/compound-engineering-plugin`. VERIFIED (CE repo, secondary). CE's `docs/specs/devin.md` was verified against 3000.1.23 and is now stale.
  - **Hooks:** `.devin/hooks.v1.json` plus a Claude-format `hooks` key. Events: PreToolUse, PostToolUse, PermissionRequest, UserPromptSubmit, Stop, PostCompaction, SessionStart, SessionEnd; exit 2 blocks. VERIFIED (/cli/extensibility/hooks/overview).
  - **Subagents:** on by default. VERIFIED.
  - **MCP:** `devin mcp add`. VERIFIED.
  - **CE does not run `devin` headless as a peer.** Its cross-model scripts have no Devin lane. VERIFIED (CE repo, secondary).
- **(g) Data egress (R36).** Inference goes through **Cognition's servers**: the CLI's "model API calls" and the `windsurf_api_client` log target (VERIFIED, /cli/troubleshooting). From there it fans out to Anthropic, OpenAI, Google, Cognition SWE, DeepSeek, Kimi and GLM depending on the model. Cognition's security page says data **may be used for training by default**; paid plans can opt out. VERIFIED for Cognition "Services" (https://docs.devin.ai/admin/security); CLI-specific applicability UNVERIFIED. **Cognition would be a new provider in the R36 egress set.**
- **(h) Fragility.**
  - `auto_update: true` swaps the `current` symlink in the background (curl installs). `attribution: true` adds a `Co-Authored-By: Devin` trailer to commits. Per-run logs always go to `~/.local/share/devin/cli/logs/`, and trace-level logs can contain tokens. VERIFIED (config-file reference; /cli/troubleshooting).
  - **Even `devin auth status` writes a log file** (`devin_<timestamp>_<pid>.log`, about 1 KB) and initializes an analytics client (`init_cli:analytics_new` span) before dispatching the command. VERIFIED (live logs). A telemetry opt-out is UNVERIFIED.
  - Look-alikes: see "Flagged sources".

## 3. Pi (`pi`) and oh-my-pi (`omp`)

- **(a) Identity, version, license.**
  - **Pi:** github.com/**earendil-works/pi** (redirect from badlogic/pi-mono), MIT, npm **`@earendil-works/pi-coding-agent` 0.87.1** (2026-09-22), Node ≥ 22.19. Cadence is 1–3 releases a week. VERIFIED (`gh api repos/badlogic/pi-mono`; `npm view`).
  - `@mariozechner/pi-coding-agent` stops at 0.73.1 and is deprecated. VERIFIED (npm).
  - Pi install: `npm i -g --ignore-scripts @earendil-works/pi-coding-agent` or `curl -fsSL https://pi.dev/install.sh | sh`. VERIFIED (earendil-works/pi `packages/coding-agent/README.md`).
  - **oh-my-pi:** github.com/**can1357/oh-my-pi** ("Fork of Pi", not a GitHub fork; built by Stencil Labs), MIT, npm **`@oh-my-pi/pi-coding-agent` 18.3.5** (2026-09-27), Bun ≥ 1.3.14. It has shipped 644 versions since 2026-01-02, several a day. VERIFIED (OR README; `npm view`).
- **(b) Q1, headless with a pinned model: PASS for both.**
  - Pi modes: `pi -p/--print` (one-shot text), `--mode json` (JSONL events, then exit) and `--mode rpc`. Flags: `--provider`, `--model <provider/id[:thinking]>`, `--thinking off|minimal|low|medium|high|xhigh|max` (clamped to the model), `--no-session`, `--tools`/`--no-tools`, `-ne`/`-ns`/`-nc`, `--offline`. VERIFIED (earendil-works/pi `packages/coding-agent/docs/cli.md`, `docs/cli-integration.md`).
  - Pi has over 30 providers. Per-provider defaults include anthropic `claude-opus-4-8`, openai `gpt-5.5`, google `gemini-3.1-pro-preview` and xai `grok-4.7`. VERIFIED (`docs/providers.md`; `src/core/model-resolver.ts`).
  - omp adds `--mode text|json|rpc|rpc-ui|acp`, a built-in run cap `--max-time <duration>`, `--thinking …|auto`, `--approval-mode`, `--yolo`, `--cwd` and `--add-dir`. VERIFIED (can1357/oh-my-pi `docs/cli-reference.md`).
- **(c) Q2, completion signal: PARTIAL for both.**
  - Pi's `--mode json` stream: session header, `agent_start`, `turn_*`, `message_*`, `tool_execution_end{isError}`, `auto_retry_end{success,finalError}`, `agent_end{willRetry}`, and finally the terminal **`agent_settled`**. The final assistant message carries `stopReason: stop|length|toolUse|error|aborted|deferred` plus `errorMessage`. VERIFIED (`docs/json.md`, `docs/message-types.md`).
  - **In Pi's JSON mode a failed or aborted turn "does not by itself produce a nonzero exit status".** Print mode does exit non-zero on error/aborted. VERIFIED (`docs/cli-integration.md`). So the adapter must require `agent_settled` and read the last `stopReason`, as `_agy_parse_envelope` does for agy.
  - Pi has no run timeout flag. VERIFIED.
  - **omp is the strongest match for agy's envelope, but only in RPC mode.** Each prompt ends in exactly one `prompt_result{status: completed|aborted|error, error{message,provider,model,httpStatus,retryable}}`, followed by `session_settled`. In print and json modes the exit code follows the terminal stop reason (bug #11498 fixed). VERIFIED (OR `docs/rpc.md`; `src/modes/print-mode.ts`).
  - Neither CLI has a denial concept, because Pi has no permission system.
- **(d) Q3, confinement: FAIL for both.**
  - **Pi has no permission system by design:** "No permission popups / No sub-agents / No MCP / No plan mode". VERIFIED (https://pi.dev). Its security doc says Pi "does not ask for approval before every tool call", and the working directory "does not prevent commands from accessing other paths". VERIFIED (`docs/security.md`).
  - Pi gating exists only as extensions. A `tool_call` handler can return `{block:true}`, and a handler that throws blocks the call. There are example `permission-gate.ts`, `protected-paths.ts` and `sandbox/` extensions, the last using `@anthropic-ai/sandbox-runtime`. VERIFIED (`docs/extensions.md`; `examples/extensions/`).
  - With Pi, the whole boundary would be Triforge's worktree plus the `GIT_CONFIG_*` no-push backstop. Pi runs bash as a child process, so the backstop should apply. UNVERIFIED (not probed).
  - **omp's approval mode defaults to `yolo`.** A bash-pattern deny does not cover the same command via the `eval` tool, and the docs call it "not process or filesystem containment". VERIFIED (OR `docs/approval-mode.md`).
  - **omp loads `.env` from the project, `~/.omp/agent/.env`, `~/.omp/.env` and `~/.env`**, which quietly undoes an `env -i` allowlist. VERIFIED (OR `docs/environment-variables.md`).
  - omp also auto-discovers rules, skills, hooks and MCP servers from `.claude`, `.cursor`, `.codex`, `.gemini` and more. VERIFIED (OR README "Discovery").
- **(e) Q4, unattended login: PASS for both.**
  - Pi uses per-provider env keys (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `XAI_API_KEY`, `OPENROUTER_API_KEY`, `KIMI_API_KEY`, `ZAI_API_KEY`, …) or OAuth logins (Claude Pro/Max, ChatGPT/Codex, Copilot, OpenRouter, kimi-coding, xai). Credentials are stored in `~/.pi/agent/auth.json`, relocatable via `PI_CODING_AGENT_DIR`. A key can be `"!cmd"` to fetch it from a secret manager. VERIFIED (`docs/providers.md`, `docs/models.md`).
  - `pi auth check --provider X --json` exits 0/1/2 for ready/not_ready/invalid, a clean liveness probe. VERIFIED (`docs/cli.md`).
  - Gemini CLI/Antigravity login was removed in Pi 0.71.0. VERIFIED (CHANGELOG).
  - omp stores credentials in `~/.omp/agent/agent.db` (SQLite) and takes env tokens such as `ANTHROPIC_OAUTH_TOKEN`, `OPENAI_CODEX_OAUTH_TOKEN` and `XAI_OAUTH_TOKEN`, with multi-account rotation. VERIFIED (OR `docs/providers.md`).
- **(f) Other capabilities.**
  - **Pi context:** reads AGENTS.md and CLAUDE.md from the agent dir, the working directory and its parents, regardless of trust. VERIFIED (`docs/configuration.md`, `docs/security.md`).
  - **Pi skills:** `~/.pi/agent/skills/`, `.pi/skills/`, `~/.agents/skills/` and **`.agents/skills/`** (walking ancestors, trust-gated; headless needs `--approve`). agentskills.io spec, invoked as `/skill:name`. VERIFIED (`docs/skills.md`). `~/.pi/agent/skills/` exists on this host with 85 entries copied in by another tool; it is evidence of the path, not an install.
  - **Pi packages:** `pi install npm:…|git:…|./path` with a `package.json` `"pi": {extensions, skills, prompts, themes}` key. VERIFIED (`docs/packages.md`). CE ships `"pi": {"extensions": ["./.pi/extensions/compound-engineering.ts"], "skills": ["./skills"]}`. Its extension only registers `skillPaths` on `resources_discover`, and CE's workflows need `pi install npm:pi-subagents`. VERIFIED (CE repo, secondary: `package.json`, `.pi/extensions/compound-engineering.ts`, README "Pi").
  - **omp:** built-in `task` subagents in isolated worktrees, native MCP, and skill discovery across the claude, agents, codex, opencode and `.github/skills` locations. Its marketplace reads `.omp-plugin/marketplace.json` and **falls back to `.claude-plugin/marketplace.json`**. VERIFIED (OR `docs/skills.md`, `docs/marketplace.md`). CE's `.omp-plugin/marketplace.json` exists because the omp update checker needs a plugin `version`. VERIFIED (CE repo, secondary: `docs/specs/omp.md`).
  - **CE does not run pi or omp headless as a peer.** VERIFIED (CE repo, secondary).
- **(g) Data egress (R36).**
  - Both are BYOK: code goes to whichever provider is configured. VERIFIED.
  - Pi extras: install/update telemetry and provider-attribution headers are **on by default** (opt out with `PI_TELEMETRY=0`), plus a pi.dev version check (`PI_SKIP_VERSION_CHECK`) and model-catalog refresh (`PI_OFFLINE`). VERIFIED (`docs/settings.md`, `docs/environment-variables.md`).
  - omp extras: a persistent install ID sent to Codex, Anthropic and the auth broker, and optional "auto-QA grievance" pushes. VERIFIED (OR `docs/install-id.md`).
- **(h) Pricing:** both are free (MIT); inference is paid at the provider's rates or subscriptions. VERIFIED.
- **(i) Fragility.**
  - **`pi update --self` installs "the package name returned by the version check endpoint"**, so the server controls which package gets installed. VERIFIED (CHANGELOG 0.73.1).
  - Stale `@mariozechner` package, stale badlogic links (omp's README still uses them), and omp's many-per-day releases. VERIFIED.

## 4. Hermes Agent (Nous Research) — `hermes`

- **(a) Identity.**
  - **The agentic CLI is Nous Research's Hermes Agent:** github.com/NousResearch/hermes-agent, MIT, homepage hermes-agent.nousresearch.com, described as "The agent that grows with you". It is a Python general-purpose, self-improving agent with coding and terminal tools, not a coding-only CLI. VERIFIED (gh api; README).
  - Latest release is **v0.21.5** (tag `v2026.9.24`, 2026-09-24), roughly weekly. VERIFIED (`gh release list`).
  - Install: `curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash`, which clones into `~/.hermes/hermes-agent/`, adds a wrapper at `~/.local/bin/hermes`, and bootstraps uv. Also Docker `nousresearch/hermes-agent`, Nix and Termux. `hermes update` tracks `main`. VERIFIED (`website/docs/getting-started/installation.md`, `updating.md`).
  - **Same name, not this product:**
    - Nous's Hermes 4 LLMs, which Nous calls "not recommended for use inside Hermes Agent".
    - Meta's Hermes JS engine (`hermes-engine`, facebook/hermes).
    - npm `hermes` (segmentio).
    - npm `hermes-cli` (a travel-agency tool).
    - PyPI `hermes` (DLR research-software publishing).
    - PyPI `hermes-cli` and `hermes-ai`.
    
    All VERIFIED (npm/PyPI metadata; `website/docs/integrations/nous-portal.md`).
- **(b) Q1, headless with a pinned model: PASS.**
  - `hermes chat --oneshot -q "…"` (or `-Q`, or any non-TTY stdio), or `--query-file PATH|-`. Flags: `-m/--model` (or `HERMES_INFERENCE_MODEL`), `--provider` (about 45 built-ins: openrouter, nous, anthropic, openai-codex, gemini, zai, kimi-coding, xai, bedrock, copilot, …), `--reasoning none|minimal|low|medium|high|xhigh|max|ultra`, `--max-turns N` (default 500), `--run-budget SECONDS` and `-t/--toolsets`. Default effort is `medium`. VERIFIED (`website/docs/reference/cli-commands.md`; `hermes_cli/_parser.py`; `user-guide/configuration.md`).
  - **Never use `hermes -z`:** it forces `HERMES_YOLO_MODE=1`, bypassing all approvals. VERIFIED (`hermes_cli/oneshot.py`; `_parser.py` help text).
- **(c) Q2, completion signal: PARTIAL (best documented of the four).**
  - `--format stream-json` emits JSONL events `system`, `text`, `tool_use`, `tool_result{is_error}` and a terminal **`result{session_id, exit_code, text, tokens, duration_ms, error}`**. The docs say: "Treat that record as the completion signal; the process exit code matches its `exit_code`." Diagnostics go to stderr. VERIFIED (cli-commands.md).
  - Exit codes: 0 completed; 1 failed, partial, iteration budget hit, or credential/init failure; 130 interrupted; 75 Kanban rate-limit/quota. **Exit 0 also covers a completed turn with no text.** VERIFIED.
  - Denied commands return a BLOCKED error to the model. VERIFIED (`user-guide/security.md`). There is no `denied_actions` equivalent; that a denial appears as `tool_result.is_error` is UNVERIFIED.
- **(d) Q3, confinement: PARTIAL.**
  - Approval modes: `approvals.mode` is `smart` by default (an **auxiliary LLM** judges risk), `manual` or `off`. `-q` sessions default `single_query_mode` to `deny`. A hardline blocklist applies even under YOLO. VERIFIED (security.md).
  - **`git push` is not on the dangerous-command list**; the worktree docs say agents "can edit files, commit, push, and create PRs". VERIFIED (security.md; configuration.md "Git Worktree Isolation").
  - `approvals.deny` fnmatch globs (`"git push*"`) apply before YOLO and on every backend. VERIFIED. They are "a shell-command policy, not … an OS capability sandbox". VERIFIED.
  - Other controls: `HERMES_WRITE_SAFE_ROOT` limits `write_file`/`patch` (not shell). Backends: local (default), docker, ssh, singularity, modal, daytona, vercel_sandbox; container backends skip the dangerous-command checks. A `pre_tool_call` hook can block and fails closed, but needs `--accept-hooks` or `HERMES_ACCEPT_HOOKS=1` headless. VERIFIED (security.md; `features/hooks.md`).
  - Its own `-w/--worktree` **fetches the remote first** and copies gitignored `.env` files in via `.worktreeinclude`. Triforge must not use it. VERIFIED (configuration.md).
  - **It writes outside the worktree by design:** memories (`~/.hermes/memories/`), `state.db`, checkpoints, agent-authored skills in `~/.hermes/skills/`, cron jobs, and a background review process. `delegate_task` spawns up to 10 children. VERIFIED (`features/memory.md`, `features/delegation.md`). A lease would need its own `HERMES_HOME` and `delegation` removed from the toolsets.
  - **Messaging gateway:** Telegram, Discord, Slack and more. `hermes send` reuses the gateway credentials, so a shared HOME exposes bot tokens to a builder. VERIFIED (README; cli-commands.md).
- **(e) Q4, unattended login: PARTIAL.**
  - API key env vars (`OPENROUTER_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `KIMI_API_KEY`, `HF_TOKEN`, …) in `~/.hermes/.env`, OAuth in `~/.hermes/auth.json`, all relocatable via `HERMES_HOME`. Nous Portal uses a browser OAuth with a localhost callback; OpenAI Codex login defaults to device code. VERIFIED (`reference/environment-variables.md`; `integrations/nous-portal.md`, `providers.md`).
  - **Hazard:** `auth.adopt_external_logins: true` is the default. Hermes **borrows and refreshes Claude Code's `~/.claude/.credentials.json` (or its Keychain entry) and Codex's `~/.codex/auth.json`**. These use rotating single-use refresh tokens, so "whichever refreshes first invalidates the other's copy". VERIFIED (security.md "Borrowed CLI logins").
  - A Hermes lease sharing HOME could log out two of the three core CLIs. INFERENCE. This is why Q4 is PARTIAL, not PASS. It is safe only with `adopt_external_logins: false` and a dedicated `HERMES_HOME`.
- **(f) Other capabilities.**
  - **Context files:** first match wins among `.hermes.md`/`HERMES.md`, `AGENTS.override.md`, `AGENTS.md` (chained from the git root), `CLAUDE.md` and `.cursorrules`. `SOUL.md` is global. Context files are scanned for prompt injection, and `--ignore-rules` skips them. VERIFIED (`features/context-files.md`).
  - **Skills:** `~/.hermes/skills/` (agentskills.io format; the agent may create, edit and delete skills there) plus `skills.external_dirs`. **Project `.agents/skills` and `.hermes/skills` load only when the root is in `skills.trusted_project_dirs`.** VERIFIED (`features/skills.md`; `agent/skill_utils.py:429-435`). `~/.hermes/skills/` exists on this host with 84 flat skill dirs copied by another tool; it is evidence of the path, not an install.
  - **Plugins:** Python plugins via `ctx.register_hook`. The gateway hook dir `~/.hermes/hooks/*/HOOK.yaml` is trusted just by placing files there. VERIFIED (hooks.md).
  - **MCP:** supported. VERIFIED.
  - **CE has no Hermes support**; it only mentions Hermes' injection defenses in `AGENTS.md:143`. VERIFIED (CE repo, secondary).
- **(g) Data egress (R36).** Code goes to the configured provider. Auxiliary calls (compression, titles, and the `smart`-mode approval classifier) use the main model by default. The optional Tool Gateway sends web/image/browser traffic to Nous infrastructure, and Portal models are relayed onward, some via OpenRouter. VERIFIED (providers.md; nous-portal.md). **Nous would be a new provider when the Portal is used.**
- **(h) Pricing:** the agent is free (MIT). Nous Portal has a Free tier (free models only), $20/mo (includes $22 of credits) and $100/mo. VERIFIED (https://portal.nousresearch.com/manage-subscription). Higher-tier details are UNVERIFIED.
- **(i) Fragility.**
  - The FAQ says there is no telemetry. VERIFIED (`reference/faq.md`).
  - Passive update checks are on by default (`updates.check false`). VERIFIED.
  - `hermes update` tracks `main`; about 460 PRs landed in the last patch window. VERIFIED.
  - Look-alikes: see "Flagged sources".

---

## Net (lead's synthesis)

**Grok Build is the only one of the four that clears the bar today.**
- The live probe passed Q1 and Q4 under the exact `env -i` shape `_adapter_env` uses: pinned `grok-4.7` plus `--effort high`, and a cached login that refreshed itself.
- Its `json` / `streaming-json` output is an agy-class result envelope with `stopReason` and a terminal `end` event.
- It has real permission modes (`dontAsk` plus `--deny`), a kernel sandbox, and Claude-compatible plugins and skills, including `.agents/skills`.
- It adds **no new provider** to R36, because xAI is already there via Cursor → Grok.

The gaps are specific:
1. Permission denials are not collected in the envelope, so the adapter parses `tool_call_update` failures and leans on the KTD11 `Status:` line.
2. `Bash(git push*)` is prefix-only, so the SELF-09 git backstop stays load-bearing.
3. grok **reads `~/.claude` hooks, settings, MCP and CLAUDE.md by default**. The adapter must export `GROK_CLAUDE_{HOOKS,MCPS,SKILLS,RULES,AGENTS}_ENABLED=0` (and the Cursor equivalents) and turn off `.envrc` loading.
4. The sandbox's CWD-only write scope may break git in a linked worktree.
5. It auto-updates near-daily unless `GROK_DISABLE_AUTOUPDATER=1`.

Next step: a probe cycle before any adapter work. Rows to add:
- exit code on `--max-turns` and on a denial;
- whether `--deny 'Bash(git push*)'` stops `git -C . push`;
- whether hooks fire under `-p`;
- `--sandbox workspace` inside a lease worktree;
- `.agents/skills` pickup under `--trust`;
- whether parallel leases race on the `auth.json` refresh.

Enrolling grok natively would also give Triforge a direct xAI lane that doesn't go through Cursor. That matters because Cursor's `cursor-grok-4.6/4.7-xhigh` pins are currently failing (CUR-12 FAIL in the 2026-09 record; CE notes 4.7 lost the `cursor-` prefix).

**Devin CLI: skill/plugin manifest only.**
- It is a real local agent, but `-p` has **no structured output, no documented exit codes and no effort flag**. The absence of output-format and effort flags is now confirmed against the live 3000.11.3 `--help`.
- `devin auth status` exits 0 even when not logged in (live), so a liveness gate must parse its text.
- This host is not logged in, so no READY probe ran and `-p` behavior is still unobserved.
- It **defeats the `env -i` allowlist** by importing the login shell's environment. This is docs-only; it could not be observed without a session.
- It loads Claude config, including the lead-only CLAUDE.md and hooks, and scans `.agents/agents/`.
- It routes all inference through Cognition, a new egress party that may train on the data by default.

It already reads `.agents/skills/` and `.claude-plugin/plugin.json`, so Triforge's skills reach Devin users with no work. Revisit when `-p` gains a JSON output mode, or if the lead is willing to write an ACP client (`devin acp`, which also has a built-in `--agent-type review` reviewer). After a user `devin auth login`, a follow-up probe row should record:
- the `-p` exit code and output shape;
- whether a variable exported only in `~/.zshrc` shows up under `env -i`.

**Pi: skill manifest only as a worker candidate. omp: skip.**
- Pi's headless JSON stream is clean, and `pi auth check --json` is a nice liveness probe. But Pi **has no permission system by design** and its JSON mode exits 0 on failed turns.
- As a builder, Pi would rely entirely on the worktree plus the git backstop, with nothing inside the tool itself refusing an action. That does not meet Triforge's posture.
- A Triforge-shipped `tool_call` extension could close part of the gap; defer that.
- Pi reads `.agents/skills/` (headless with `--approve`), so a `package.json` `"pi"` key is a cheap skills-only surface if wanted.
- omp's RPC `prompt_result` is the best completion signal in this batch. But omp defaults to yolo approval, **loads `~/.env` and project `.env` behind `env -i`**, and releases several times a day. Skip.

**Hermes Agent: skip for now.**
- It has the best-documented headless contract (`stream-json` `result` with an `exit_code` that matches the process). But its defaults conflict with a leased worker:
  - it adopts and refreshes the **Claude Code and Codex logins**, which can log out the core trio;
  - it writes persistent memory, skills and state to `~/.hermes`;
  - it has subagents plus a messaging gateway;
  - `git push` is not a dangerous command, and the default approval judge is an LLM.
- Enrolling it would need a dedicated `HERMES_HOME` per lease, `adopt_external_logins: false`, `approvals.deny: ["git push*"]`, `delegation` removed, and `skills.trusted_project_dirs` for `.agents/skills`. That is a lot of adapter state for an optional member.
- Revisit if Nous ships a stateless or ephemeral one-shot profile.

### Flagged sources
- **Grok:** npm `grok-cli` (tomasmcm / whitesmith), npm `@vibe-kit/grok-cli`, GitHub `superagent-ai/grok-cli`, and npm `grok` (azulus) are all third-party. The **only** official npm package is `@xai-official/grok`; `@xai/grok` and `@xai-org/grok` do not exist. Secondary SEO sites (felloai.com, jingrey.com, shareallai.github.io, aibuilderclub.com) were not used. The online docs and the repo user guide disagree on default model, subagent default, number of output formats, `.agents/skills` scope and strict-sandbox write paths.
- **Devin:**
  - PyPI `devin-cli` / `revanthpobala/devin-cli` is an unofficial cloud-API wrapper that **installs a colliding `devin` binary**.
  - npm `devin` (0.0.0, with a bin) is ambiguous; npm `devin-cli` and `devin-ai` look like defensive reservations.
  - GitHub `devin-cli/devin-cli.github.io` is an SEO site created 2026-09-21.
  - The GitHub org `Cognition-ai` is not official; the official org is `CognitionAI`.
  - `OnlyTerp/DevinCLI-Unlocked` and `a0yark/patch-devin` are binary-tampering tools.
  - The devin.ai/cli mock-up shows "v2026.9.2"; it is an illustration, not a version source.
  - Every docs.devin.ai page carries an agent-directed header, recorded verbatim and not acted on: "Fetch the complete documentation index at: https://docs.devin.ai/llms.txt. Use this file to discover all available pages before exploring further."
- **Pi / omp:** npm `oh-my-pi` 0.2.0 (acidsugarx) is an unrelated look-alike. npm `pi-coding-agent` 0.0.1 is a placeholder, probably defensive (owner mitsuhiko). `@mariozechner/pi-coding-agent` is deprecated. Many third-party `omp-*` packages exist; only the `@oh-my-pi/*` scope is can1357's. The Pi README and pi.dev list different Discord invites. pi.ai (Inflection) is a different product.
- **Hermes:** npm `hermes-agent` 0.21.5 is a self-described "Unofficial npm bridge" (wyrtensi). PyPI `hermes-agent` 0.19.0 claims "Nous Research" as author but has no project URLs, is stale, and is never mentioned by the repo, so its provenance is UNVERIFIED. The community sites hermesagents.net, hermes-agent.org and hermes-ai.net are unofficial.
- **Prompt injection:** no directive-style injection was found in any fetched page. The Devin llms.txt header above is benign and was recorded, not followed.

### Needs browser (not read this cycle)
- https://x.ai/pricing (Build quotas per plan)
- https://devin.ai/pricing (CLI on the Free plan)
- https://pi.dev/docs/latest, https://omp.sh
- https://portal.nousresearch.com (full tier table)

The repo docs covered the substance of each gating question, so the chrome-devtools pass was skipped.

### Cross-checks performed
- **Grok, local vs online:** the installed `--help` (1.0.34) and `~/.grok/README.md` (2026-08-01 copy) were cross-checked against the online docs and the repo user guide (2026-09-23 sync). The flags the verdicts depend on (`-p`, `-m`, `--effort`, `--output-format`, `--permission-mode`, `--allow/--deny`, `--sandbox`, `--no-subagents`) are present in 1.0.34.
- **Grok, live:** the envelope fields claimed in docs (`text`, `stopReason`, `sessionId`, `num_turns`, `total_cost_usd`, `modelUsage`) were confirmed by the probe.
- **Triforge grounding:** `_cursor_bin` rejecting grok's `agent` was checked against `scripts/lib/cursor.sh:88-115` and CUR-11 in `ops/research/2026-09-probe-record.md`. The `_adapter_env` allowlist and no-push backstop were read from `scripts/lib/lease.sh:274-340`, and the agy envelope contract from `scripts/lib/antigravity.sh:119-154`.
- **CE manifests:** read directly from the clone at `${TMPDIR}/repo-watch-2026-09-27/EveryInc_compound-engineering-plugin` (HEAD a763b39, 2026-09-25): `.grok-plugin/`, `.devin-plugin/`, `.pi/`, `.omp-plugin/`, `package.json`, the README install sections, and `skills/*/scripts/cross-model-*.sh`.
- **Devin, live vs docs:** the live 3000.11.3 `--help` was cross-checked against the docs-based findings. It confirms `-p`, `--prompt-file`, `--model`/`DEVIN_MODEL`, `--permission-mode`, `--sandbox`, `--config` and `--respect-workspace-trust`, and it confirms there is no output-format, effort, max-turns or timeout flag. Differences: the help lists four permission modes, while the docs list aliases plus `autonomous`; and live `acp --help` adds `--agent-type review|summarizer` and `--refusal-fallback`. No Devin model call was made (not logged in).
