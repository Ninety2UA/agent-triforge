# Codex: project trust (Step 1b, read-only detection, D-026) and invocation

Under a Codex lead this skill is invoked as `$at-setup`; the walk is the same.

Since Codex 0.147.0, `codex exec` reads project-tier files (`.codex/hooks.json`, `.codex/config.toml`, `.codex/.rules`) only in a **trusted** project; the root `AGENTS.md` is skipped only when trust is explicitly `untrusted` (D-045). Trust lives at the user tier, `~/.codex/config.toml`, which Triforge never writes (R18). Detect the exact-path entry and report it; the user adds it by hand when missing:

```bash
CODEX_TRUST=$(CT_PROJECT="$(python3 -c 'import os; print(os.path.realpath(os.getcwd()))')" python3 -c '
import os, sys
try:
    import tomllib
except ImportError:
    print("unknown (no tomllib)"); sys.exit(0)
path = os.path.expanduser("~/.codex/config.toml")
project = os.environ["CT_PROJECT"]
try:
    with open(path, "rb") as f:
        cfg = tomllib.load(f)
except FileNotFoundError:
    print("no-user-config"); sys.exit(0)
except Exception as exc:
    print("unreadable (" + str(exc)[:60] + ")"); sys.exit(0)
entry = (cfg.get("projects") or {}).get(project)
if isinstance(entry, dict) and entry.get("trust_level"):
    print("trusted (" + str(entry.get("trust_level")) + ")")
else:
    parents = [p for p in (cfg.get("projects") or {}) if project.startswith(p.rstrip("/") + "/")]
    print("no exact-path trust entry" + ("; parent entries exist: " + ", ".join(parents) + " (whether a parent covers subdirectories is unverified)" if parents else ""))
' 2>/dev/null)
echo "CODEX-TRUST: ${CODEX_TRUST:-unknown}"
```

- `trusted (...)`: project-tier Codex files apply under `exec`; nothing to do.
- `no exact-path trust entry`: print the block for the user to add to `~/.codex/config.toml` (never write it yourself):

  ```toml
  [projects."<absolute project path>"]
  trust_level = "trusted"
  ```

  Explain what stays covered without it: the role instructions ride as a prompt prefix, and the root `AGENTS.md` still loads (only an explicit `untrusted` blocks it, D-045). `.codex/config.toml` (memories off) and `.codex/hooks.json` are skipped until the entry exists: `invoke_codex` never passes `--dangerously-bypass-hook-trust`, so project hooks go through Codex's own trust under `exec`.
- `no-user-config` / `unreadable` / `unknown`: report as is; setup continues.
