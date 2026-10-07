#!/usr/bin/env bash
# scripts/lib/instructions.sh — the user project's instruction files (R9, R39, R40; U15): detection in the project, every directory above it and the user level, whether Triforge's AGENTS.md pointer reaches a lead, and the ask-first writers at-setup calls (the @AGENTS.md import, the pointer-block merge under the AGENTS.md byte budget, the 3.x template conversion)
#
# Standalone: sourced by scripts/invoke-external.sh (the loader, ahead of
# lease.sh) and directly by hooks/handlers/session-start.sh, so the hook's
# notices still work when the full loader fails. Nothing runs at source time
# but assignments and function definitions, and nothing here needs another
# lib: read_regular comes from _READ_REGULAR_PY (common.sh) when it is in
# scope, else from the same lines below; cli_field (registry.sh) is called for
# a lead's reader, and without it every reader is unknown. Bash 3.2 and zsh:
# the shell layer only parses arguments; every rule lives in the python
# program _INSTR_PY, so the two shells run the same code.
#
# The instruction readers (the Key Decision, ops/research/2026-09-27-cli-updates.md),
# kept as data in READERS (_INSTR_PY) and named per CLI by the registry field
# "instructions" (KTD1), so nothing here branches on a CLI:
#   claude-md-shadow  reads AGENTS.md (cwd and every directory above) only while
#     no CLAUDE.md, .claude/CLAUDE.md or CLAUDE.local.md exists in the working
#     directory or above it; ~/.claude/CLAUDE.md, the user tier, does not count.
#     A CLAUDE.md-family file that imports AGENTS.md (an `@AGENTS.md` token,
#     its path relative to the file holding it) loads it with the file.
#   agents-chain  reads ${CODEX_HOME:-~/.codex}/AGENTS.md, then one file per
#     directory from the project root (the nearest directory holding .git)
#     down to the working directory, AGENTS.override.md replacing AGENTS.md at
#     its level, into one combined budget of project_doc_max_bytes (32768 by
#     default, from ${CODEX_HOME:-~/.codex}/config.toml), and drops the rest.
#     A project whose trust is explicitly "untrusted" gets no project
#     AGENTS.md.
#
# Symlinks: the directory walk runs over the physical path (symlinks in the
# directories above resolved first, like pwd -P). Detection reads a symlinked
# instruction file through its link, read-only, and marks it "symlink"; a link
# to a FIFO, a device or a missing target is "unreadable". Every read opens
# O_NONBLOCK and accepts regular files only, so a FIFO never stalls a walk.
# The writers refuse a symlinked target, and a target whose own directory is a
# symlink (rc 2): they replace a file in place, in its directory, never
# through a link.
#
# Writers: rc 20 (needs-ask) without --yes, the planned change printed and
# nothing written; with --yes, the change goes into a temp file in the same
# directory (O_EXCL, O_NOFOLLOW, through a directory descriptor opened
# O_NOFOLLOW) renamed over the target, after a re-read shows the target still
# holds the bytes the plan was made from (rc 80 when it changed meanwhile).
# Each is idempotent: a run with nothing to change prints "unchanged:" and
# returns 0 without asking. Lead-only: a lease worker or a lease root is
# refused (rc 45, _lead_only --any-host when the loader is in scope, else the
# worker marker). Every reader's user-level files (user_owned: the user tier
# under HOME, the user-level file and its override in the reader home) are
# read, never written: each writer refuses one, or any file in the directory
# of one, before any plan and also with --yes (rc 2), by identity, or by the
# physical path for a file that does not exist yet.
#
# Return codes: 0 ok · 1 hidden or an unknown reader
# (instruction_pointer_visibility) · 2 refused input · 3 over the AGENTS.md
# byte budget (instruction_merge_pointer and the merge in
# instruction_convert_stale) · 20 needs-ask · 45 lead-only refusal · 64 usage ·
# 69 unavailable (no python3, no template) · 80 degraded (a write failed, or
# the target changed while it was planned).

# The plugin root this file belongs to, for templates/AGENTS.md when the
# loader's _TRIFORGE_PLUGIN_ROOT is not in scope (the hook sources this file
# alone). bash names the file in BASH_SOURCE, zsh through %x (eval'd, so bash
# never parses the zsh form).
_INSTR_ROOT=""
if [ -n "${BASH_SOURCE:-}" ]; then
  _INSTR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" || _INSTR_ROOT=""
elif [ -n "${ZSH_VERSION:-}" ]; then
  _INSTR_ROOT="$(cd "$(dirname "$(eval 'echo "${(%):-%x}"')")/../.." 2>/dev/null && pwd)" || _INSTR_ROOT=""
fi

# _INSTR_READ_PY — the prelude, then read_regular(path[, text]): the same
# lines as _READ_REGULAR_PY in scripts/lib/common.sh (_PY_PRELUDE, then the
# reader), used when that is not in scope; SELF-27 compares the two.
_INSTR_READ_PY='
import os, sys
try:
    _tf_here = os.path.realpath(os.getcwd())
except OSError:
    _tf_here = None
sys.path[:] = [_p for _p in sys.path if os.path.isabs(_p) and os.path.realpath(_p) != _tf_here]
del _tf_here

def read_regular(p, text=False):
    import os, stat
    fd = os.open(p, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0))
    with os.fdopen(fd, "r" if text else "rb") as f:
        if not stat.S_ISREG(os.fstat(f.fileno()).st_mode):
            raise OSError("not a regular file: " + p)
        return f.read()
'

# _INSTR_PY — the program: argv is <op> <helper name> <args...>.
#   detect <dir>                         instruction_files_detect
#   visibility <lead> <reader> <dir>     instruction_pointer_visibility
#   add-import <file> <yes>              instruction_add_import
#   merge <dir> <template> <yes>         instruction_merge_pointer
#   convert <file> <template> <yes>      instruction_convert_stale
# The 3.x fingerprint (moved here from session-start.sh) is the template's
# signature line plus at least 3 of the 8 Triforge-specific headings every v3.*
# templates/CLAUDE.md carries, at any heading level: a copy with sections
# removed, added or reworded still matches. EXACT_3X holds the SHA-256 of the
# template at every v3.* tag (six distinct files, v3.0.0 … v3.3.3): only a
# byte-identical copy, which holds nothing of the user's, is ever removed.
_INSTR_PY='
# runs after the read_regular lines, whose prelude dropped the working
# directory (the user project) from sys.path: a hashlib.py or re.py planted
# there never runs
import hashlib, os, re, stat, sys

CLAUDE_KINDS = ("CLAUDE.md", ".claude/CLAUDE.md", "CLAUDE.local.md")
AGENTS_KINDS = ("AGENTS.md", "AGENTS.override.md")
STALE_KINDS = ("CLAUDE.md", ".claude/CLAUDE.md")
SIGNATURE = b"It works with the **Agent Triforge** plugin"
HEADING = re.compile(rb"^#{1,6}[ \t\v\f\r]+(?:Multi-agent system|Four coordination modes|Shared file protocol|Execution phases|Assignment heuristic|Portable skills|Specialized agents|Agent invocation patterns)", re.M)
EXACT_3X = {
    "473c761816efbc5c4a0ac86bfaf4b78b2b14374d39e49ef6fd00a28f1fb795f2": "v3.0.0",
    "7896bcc8e284b7b1c6859b9d570f055f4183b58ac95df66e07f96a1b3b291bf7": "v3.0.1",
    "24a0a4e2df4c2f64f024380bbfb0d7f707dee22704082be11515da327694ae31": "v3.1.0",
    "3bef92f62040e569a78f4ba4d698ffcd6cb81f9e06945e24947aa1cc55354d52": "v3.2.0",
    "222c49b8879aa1a734414e329c98e865b610468a1eb0e611076d0899368ae584": "v3.3.0-v3.3.2",
    "4390b47bfb21d327508cf4e2f43fecd7f08fa7fd774baf7d5ee57b6c84dbda5e": "v3.3.3",
}
# an import: a whitespace-separated word @AGENTS.md or @<path>/AGENTS.md (a
# backticked mention is prose, not an import); only trailing punctuation or a
# #fragment may follow the name, so @AGENTS.md.bak names another file
IMPORT = re.compile(rb"@((?:\S*/)?)AGENTS\.md(?:[.,;:!?)]*|#\S*)")
START = b"<!-- triforge:start -->"
END = b"<!-- triforge:end -->"
# The instruction readers a lead can run, named by its registry field
# "instructions" (KTD1). Data only, keyed by reader, never by CLI:
#   shadow       the files at the cwd or above (up to /) that hide AGENTS.md
#                unless one of them imports it
#   user_tier    that family under HOME: always loaded, never a shadow, its
#                imports count
#   home_env, home_default  the reader home: $<home_env>, else HOME/<default>
#   user_level   the file taken from that home before the project files
#   override     the file that replaces AGENTS.md at its level
#   root_marker  the files are read from the nearest directory holding it down
#                to the cwd ("": every directory from / down)
#   budget, budget_key, config  the combined byte budget, and the key in
#                <home>/<config> that sets it ("": no budget)
#   trust_table, trust_key, untrusted  a project whose entry there carries
#                that value gets no project AGENTS.md ("": no trust rule)
READERS = {
    "claude-md-shadow": {
        "shadow": CLAUDE_KINDS, "user_tier": ".claude/CLAUDE.md",
        "home_env": "", "home_default": "", "user_level": "", "override": "", "root_marker": "",
        "budget": 0, "budget_key": "", "config": "",
        "trust_table": "", "trust_key": "", "untrusted": "",
    },
    "agents-chain": {
        "shadow": (), "user_tier": "",
        "home_env": "CODEX_HOME", "home_default": ".codex", "user_level": "AGENTS.md",
        "override": "AGENTS.override.md", "root_marker": ".git",
        "budget": 32768, "budget_key": "project_doc_max_bytes", "config": "config.toml",
        "trust_table": "projects", "trust_key": "trust_level", "untrusted": "untrusted",
    },
}
# the reader whose byte budget instruction_merge_pointer checks: the one with a budget
BUDGETED = [n for n, r in READERS.items() if r["budget_key"]][0]


def emit(stream, text):
    stream.buffer.write(text.encode("utf-8", "surrogateescape") + b"\n")
    stream.flush()


def out(text):
    emit(sys.stdout, text)


def err(text):
    emit(sys.stderr, text)


def clean(text):
    return re.sub(r"[\x00-\x1f\x7f]", "?", text)


def home():
    h = os.environ.get("HOME", "")
    return h if h.startswith("/") else ""


def reader_home(r):
    if r["home_env"] and os.environ.get(r["home_env"], ""):
        return os.path.abspath(os.environ[r["home_env"]])
    return os.path.join(home(), r["home_default"]) if r["home_default"] and home() else ""


def lexists(p):
    try:
        os.lstat(p)
        return True
    except OSError:
        return False


def islink(p):
    try:
        return stat.S_ISLNK(os.lstat(p).st_mode)
    except OSError:
        return False


def load(p):
    try:
        return read_regular(p)
    except (OSError, ValueError):
        return None


def level_file(r, level, name="AGENTS.md"):
    # the one file the reader takes from a directory: its override over <name>
    for n in ([r["override"]] if r["override"] else []) + [name]:
        p = os.path.join(level, n)
        d = load(p) if level and lexists(p) else None
        if d is not None:
            return p, d
    return None, None


def linked(level, kind):
    p = level
    for part in kind.split("/"):
        p = os.path.join(p, part)
        if islink(p):
            return True
    return False


def same_file(a, b):
    try:
        return os.path.samefile(a, b)
    except OSError:
        return os.path.realpath(a) == os.path.realpath(b)


def levels_up(start):
    out_ = [start]
    while out_[-1] != "/":
        out_.append(os.path.dirname(out_[-1]))
    return out_


def read_levels(r, cwd):
    # the directories the reader takes files from, in reading order: from the
    # nearest directory holding its root marker (else the cwd) down to the cwd,
    # or from / down without a marker
    ups = levels_up(cwd)
    if r["root_marker"]:
        ups = ups[:next((i for i, l in enumerate(ups) if lexists(os.path.join(l, r["root_marker"]))), 0) + 1]
    return list(reversed(ups))


def is_3x(data):
    return SIGNATURE in data and len(HEADING.findall(data)) >= 3


def exact_3x(data):
    return EXACT_3X.get(hashlib.sha256(data).hexdigest(), "")


def has_block(data):
    s = data.find(START)
    return s >= 0 and data.find(END, s) > s


def block_end(data):
    return data.find(END, data.find(START)) + len(END)


def imports(path, data, targets):
    # True when the file at path imports AGENTS.md from one of targets
    # (physical directories). The path of an import is relative to the
    # directory of the file holding it, ~/ is HOME, an absolute path stands,
    # ".." collapses lexically (as cd does) before symlinks resolve.
    base = os.path.dirname(path)
    for word in data.split():
        m = IMPORT.fullmatch(word)
        if not m:
            continue
        d = os.fsdecode(m.group(1))
        if d.startswith("~/"):
            if not home():
                continue
            d = home().rstrip("/") + "/" + d[2:]
        elif not d.startswith("/"):
            d = base + "/" + d
        d = os.path.normpath(d)
        if os.path.isdir(d) and os.path.realpath(d) in targets:
            return True
    return False


def import_line(kind, level, target):
    rel = os.path.relpath(target, level)
    prefix = "" if rel == "." else rel + "/"
    return ("@../" if kind.startswith(".claude/") else "@") + prefix + "AGENTS.md"


def user_tiers():
    return [os.path.join(home(), r["user_tier"]) for r in READERS.values() if r["user_tier"] and home()]


def is_user_tier(path):
    return lexists(path) and any(lexists(u) and same_file(path, u) for u in user_tiers())


def user_files():
    # (path, label) of every file a reader takes from the directories of the
    # user, from READERS: its user tier under HOME, then its user-level file
    # and override in its reader home ($<home_env> honored, as reader_home
    # does)
    files = []
    for r in READERS.values():
        if r["user_tier"] and home():
            files.append((os.path.join(home(), r["user_tier"]), "user-tier ~/" + r["user_tier"]))
        rh = reader_home(r)
        if not rh:
            continue
        shown = "$" + r["home_env"] if r["home_env"] and os.environ.get(r["home_env"], "") else "~/" + r["home_default"]
        files += [(os.path.join(rh, n), "user-level " + shown + "/" + n) for n in (r["user_level"], r["override"]) if n]
    return files


def user_owned(path):
    # why no writer may write path ("" when one may): it is, or would be, one
    # of user_files, or it sits in the directory of one. same_file
    # compares by identity where both exist (a hard link; a link to the file
    # or to its directory) and by physical path where one does not, so an
    # absent target is caught too
    files = user_files()
    for u, label in files:
        if same_file(path, u):
            return path + " is your " + label + ", which Triforge reads and never writes; edit it yourself"
    for u, label in files:
        if same_file(os.path.dirname(path), os.path.dirname(u)):
            return path + " is in the directory of your " + label + ", which Triforge reads and never writes; edit it yourself"
    return ""


def kind_names(kinds):
    return ", ".join(kinds[:-1]) + " or " + kinds[-1] if len(kinds) > 1 else "".join(kinds)


def row(kind, where, path, level, project):
    data = load(path)
    if data is None:
        states = ["unreadable"]
    elif kind in CLAUDE_KINDS:
        states = ["imports" if imports(path, data, {project}) else "no-import"]
        if kind in STALE_KINDS and where != "user" and is_3x(data):
            states.append("stale-3x-exact" if exact_3x(data) else "stale-3x-edited")
        else:
            states.append("user-owned")
    else:
        states = ["override"] if kind == "AGENTS.override.md" else []
        states.append("pointer" if has_block(data) else "no-pointer")
    if linked(level, kind):
        states.append("symlink")
    imp = import_line(kind, level, project) if kind in CLAUDE_KINDS and where != "user" else "-"
    return "\t".join((kind, where, ",".join(states), clean(path), clean(imp)))


def detect(fn, start):
    if not os.path.isdir(start):
        err(fn + ": REFUSED — " + clean(start) + " is not a directory (rc 2)")
        return 2
    project = os.path.realpath(start)
    for level in levels_up(project):
        where = "project" if level == project else "above"
        for kind in CLAUDE_KINDS + AGENTS_KINDS:
            path = os.path.join(level, kind)
            if not lexists(path) or is_user_tier(path):
                continue
            out(row(kind, where, path, level, project))
    for r in READERS.values():
        if r["user_tier"] and home() and lexists(os.path.join(home(), r["user_tier"])):
            out(row(r["user_tier"], "user", os.path.join(home(), r["user_tier"]), home(), project))
        rh = reader_home(r) if r["user_level"] else ""
        for kind in AGENTS_KINDS:
            if rh and kind in (r["user_level"], r["override"]) and lexists(os.path.join(rh, kind)):
                out(row(kind, "user", os.path.join(rh, kind), rh, project))
    return 0


def toml_load(data, r):
    # the reader budget key and trust entries, from a TOML parser when there
    # is one, else from a line scan (macOS /usr/bin/python3 has neither
    # tomllib nor tomli)
    try:
        try:
            import tomllib
        except ImportError:
            import tomli as tomllib
    except ImportError:
        tomllib = None
    if tomllib is not None:
        try:
            cfg = tomllib.loads(data.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return None
        table = cfg.get(r["trust_table"]) if r["trust_table"] else None
        table = table if isinstance(table, dict) else {}
        trust = {k: v.get(r["trust_key"]) for k, v in table.items() if isinstance(v, dict)}
        return {"max": cfg.get(r["budget_key"]) if r["budget_key"] else None, "trust": trust}
    cfg = {"max": None, "trust": {}}
    head = re.compile(r"^\[\s*" + re.escape(r["trust_table"]) + r"\s*\.\s*(\"([^\"]*)\"|\x27([^\x27]*)\x27)\s*\]\s*(#.*)?$") if r["trust_table"] else None
    size = re.compile(r"^" + re.escape(r["budget_key"]) + r"\s*=\s*([0-9_]+)\s*(#.*)?$") if r["budget_key"] else None
    trust = re.compile(r"^" + re.escape(r["trust_key"]) + r"\s*=\s*\"([^\"]*)\"\s*(#.*)?$") if r["trust_key"] else None
    table = None
    for raw in data.decode("utf-8", "replace").splitlines():
        line = raw.strip()
        m = head.match(line) if head else None
        if m:
            table = m.group(2) if m.group(2) is not None else m.group(3)
            continue
        if line.startswith("["):
            table = ""
            continue
        m = size.match(line) if size else None
        if m and table is None:
            cfg["max"] = int(m.group(1).replace("_", ""))
        m = trust.match(line) if trust else None
        if m and table:
            cfg["trust"][table] = m.group(1)
    return cfg


def reader_config(r):
    # (settings, path, state) of <reader home>/<config>; state absent | read | unreadable
    rh = reader_home(r)
    path = os.path.join(rh, r["config"]) if rh and r["config"] else ""
    empty = {"max": None, "trust": {}}
    if not path or not lexists(path):
        return empty, path, "absent"
    data = load(path)
    cfg = toml_load(data, r) if data is not None else None
    if cfg is None:
        return empty, path, "unreadable"
    return cfg, path, "read"


def budget_of(r, cfg, path):
    v = cfg["max"]
    if isinstance(v, int) and not isinstance(v, bool) and v >= 0:
        return v, r["budget_key"] + " in " + path
    return r["budget"], "the default"


def user_level(r):
    # (path, bytes) of the file the reader takes from its home first
    rh = reader_home(r) if r["user_level"] else ""
    return level_file(r, rh, r["user_level"]) if rh else (None, None)


def visibility(fn, lead, reader, start):
    # an unknown reader fails closed: the pointer is not known to reach the lead
    if not os.path.isdir(start):
        err(fn + ": REFUSED — " + clean(start) + " is not a directory (rc 2)")
        return 2
    r = READERS.get(reader)
    if r is None:
        named = "names no instruction reader for " + lead + " (its instructions field is empty or missing)" if not reader else "names the reader " + reader + " for " + lead + ", which this library does not know"
        return say(lead, "hidden", "unknown reader: the registry " + named + ", so AGENTS.md is not known to reach it")
    return reach(lead, r, os.path.realpath(start))


def say(lead, verdict, why):
    out("\t".join((clean(lead), verdict, clean(why))))
    return 0 if verdict == "visible" else 1


def reach(lead, r, cwd):
    # every rule the reader has, in the order it applies them: an untrusted
    # project, the files it takes (the user-level one, then one per directory,
    # its override over AGENTS.md), the budget, the shadow files
    levels = read_levels(r, cwd)
    cfg, cfg_path, cfg_state = reader_config(r)
    for key, value in cfg["trust"].items():
        if r["untrusted"] and value == r["untrusted"] and isinstance(key, str) and os.path.realpath(key) in (levels[0], cwd):
            return say(lead, "hidden", "the project " + key + " is marked " + value + " in " + cfg_path + " (" + r["trust_key"] + " = \"" + value + "\"), so this reader takes no project AGENTS.md")
    budget, source = budget_of(r, cfg, cfg_path)
    note = " (" + cfg_path + " is unreadable, so the default applies)" if cfg_state == "unreadable" else ""
    up, ud = user_level(r)
    used = user = len(ud) if ud is not None else 0
    pointers = []
    for level in levels:
        p, d = level_file(r, level)
        if d is None:
            continue
        if has_block(d):
            pointers.append((p, level, used + block_end(d)))
        used += len(d)
    if not pointers:
        for level in levels:
            a, o = os.path.join(level, "AGENTS.md"), os.path.join(level, r["override"] or "AGENTS.md")
            d = load(a) if r["override"] and lexists(a) else None
            if d is not None and has_block(d) and load(o) is not None:
                return say(lead, "hidden", "shadowed by " + o + ": this reader takes it instead of " + a + " at that level; merge the pointer block into it by hand, or remove it")
        return say(lead, "hidden", "no AGENTS.md between " + levels[0] + " and " + cwd + " holds the Triforge pointer block; instruction_merge_pointer adds it")
    pointer, plevel, end = pointers[0]
    if r["budget_key"] and end > budget:
        return say(lead, "hidden", "over budget: the pointer block in " + pointer + " ends at byte " + str(end) + " of the files this reader combines (user-level " + str(user) + " bytes first), past " + str(budget) + " (" + source + "), where it stops reading" + note)
    tail = ": the pointer block ends at byte " + str(end) + " of the files this reader combines, within " + str(budget) + " (" + source + ")" if r["budget_key"] else ""
    if r["shadow"]:
        shadows = []
        for level in levels_up(cwd):
            for kind in r["shadow"]:
                p = os.path.join(level, kind)
                if lexists(p) and not is_user_tier(p):
                    shadows.append((p, kind, level))
        if not shadows:
            tail += ": no " + kind_names(r["shadow"]) + " at " + cwd + " or above"
        else:
            for p in [s[0] for s in shadows] + [u for u in user_tiers() if lexists(u)]:
                d = load(p)
                if d is not None and imports(p, d, set(l for _, l, _ in pointers)):
                    return say(lead, "visible", p + " imports " + pointer + ", so it is loaded with that file" + note)
            p, kind, level = shadows[0]
            fix = "add the line " + import_line(kind, level, plevel) + " to " + p + " (instruction_add_import " + p + (", run from " + plevel if plevel != cwd else "") + ")"
            return say(lead, "hidden", "shadowed by " + ", ".join(s[0] for s in shadows) + ": this reader takes AGENTS.md only while no " + kind_names(r["shadow"]) + " exists in the working directory or above, and none of them imports " + pointer + "; " + fix)
    return say(lead, "visible", pointer + " is read" + tail + note)


def refuse(fn, why, rc=2):
    err(fn + ": REFUSED — " + clean(why) + " (rc " + str(rc) + ")")
    return rc


def target_of(fn, arg, kinds):
    # (path, kind, level, None) for a writable instruction file, or (.., rc)
    path = os.path.abspath(arg)
    base = os.path.basename(path)
    parent = os.path.dirname(path)
    if base == "CLAUDE.md" and os.path.basename(parent) == ".claude":
        kind, level = ".claude/CLAUDE.md", os.path.dirname(parent)
    else:
        kind, level = base, parent
    if kind not in kinds:
        return path, kind, level, refuse(fn, path + " is not one of " + ", ".join(kinds))
    why = user_owned(path)
    if why:
        return path, kind, level, refuse(fn, why)
    if islink(parent):
        return path, kind, level, refuse(fn, parent + " is a symlink: the file would be written outside the directory it is named in; pass the physical path, or edit it yourself")
    if islink(path):
        return path, kind, level, refuse(fn, path + " is a symlink: Triforge replaces a regular file in place and never writes through a link; edit the link target yourself")
    return path, kind, level, None


def write_file(dirpath, name, old, new):
    # the change, in a temp file renamed over <dirpath>/<name>; old is the
    # content the plan was made from (None: the file was absent). Returns ""
    # or why nothing was written.
    dfd = os.open(dirpath, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    tmp = None
    try:
        try:
            fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=dfd)
        except FileNotFoundError:
            cur, mode = None, 0o666 & ~current_umask()
        else:
            with os.fdopen(fd, "rb") as f:
                st = os.fstat(f.fileno())
                if not stat.S_ISREG(st.st_mode):
                    return "it is no longer a regular file"
                cur, mode = f.read(), stat.S_IMODE(st.st_mode)
        if cur != old:
            return "it changed while the change was planned"
        for _ in range(8):
            tmp = "." + name + ".triforge-" + str(os.getpid()) + "-" + os.urandom(4).hex()
            try:
                fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=dfd)
                break
            except FileExistsError:
                tmp = None
        if tmp is None:
            return "no temp file could be created"
        with os.fdopen(fd, "wb") as f:
            f.write(new)
            f.flush()
            os.fsync(f.fileno())
            os.fchmod(f.fileno(), mode)
        os.rename(tmp, name, src_dir_fd=dfd, dst_dir_fd=dfd)
        tmp = None
        return ""
    finally:
        if tmp is not None:
            try:
                os.unlink(tmp, dir_fd=dfd)
            except OSError:
                pass
        os.close(dfd)


def current_umask():
    u = os.umask(0)
    os.umask(u)
    return u


def add_import(fn, arg, yes):
    path, kind, level, rc = target_of(fn, arg, CLAUDE_KINDS)
    if rc is not None:
        return rc
    project = os.path.realpath(os.getcwd())
    lev = os.path.realpath(level)
    if not (project == lev or project.startswith(lev.rstrip("/") + "/")):
        return refuse(fn, path + " is neither in this project (" + project + ") nor above it, so it never shadows its AGENTS.md")
    if not lexists(path):
        return refuse(fn, path + " does not exist; nothing shadows AGENTS.md there")
    data = load(path)
    if data is None:
        return refuse(fn, path + " is not a regular file")
    if imports(path, data, {project}):
        out("unchanged: " + path + " already imports " + os.path.join(project, "AGENTS.md"))
        return 0
    line = import_line(kind, lev, project)
    new = data + (b"\n" if data and not data.endswith(b"\n") else b"") + os.fsencode(line) + b"\n"
    plan = "add the line " + line + " to " + path + ", so Claude Code loads " + os.path.join(project, "AGENTS.md") + " with it"
    if not lexists(os.path.join(project, "AGENTS.md")):
        plan += " (this project has no AGENTS.md yet; instruction_merge_pointer creates it)"
    if not yes:
        out("needs-ask: would " + plan)
        out("  apply : instruction_add_import " + path + " --yes")
        return 20
    why = write_file(os.path.dirname(path), os.path.basename(path), data, new)
    if why:
        return refuse(fn, path + " not written: " + why, 80)
    out("changed: " + path + ": added the line " + line)
    return 0


def merge_plan(fn, dirarg, template):
    # (rc, dict): the merge of the template block into <dir>/AGENTS.md
    if not os.path.isdir(dirarg):
        return refuse(fn, dirarg + " is not a directory"), None
    target = os.path.realpath(dirarg)
    path = os.path.join(target, "AGENTS.md")
    why = user_owned(path)
    if why:
        return refuse(fn, why), None
    tmpl = load(template) if template else None
    if tmpl is None or not has_block(tmpl) or tmpl.count(START) != 1:
        return refuse(fn, "the pointer block template " + (template or "(no plugin root)") + " is missing or has no single marked block", 69), None
    block = tmpl[tmpl.find(START):block_end(tmpl)]
    if islink(path):
        return refuse(fn, path + " is a symlink: Triforge replaces a regular file in place and never writes through a link; merge the block into the link target yourself"), None
    old = None
    if lexists(path):
        old = load(path)
        if old is None:
            return refuse(fn, path + " is not a regular file"), None
        ns, ne = old.count(START), old.count(END)
        if ns == 0 and ne == 0:
            new = old + (b"\n" if old and not old.endswith(b"\n") else b"") + (b"\n" if old else b"") + block + b"\n"
            action = "append"
        elif ns == 1 and ne == 1 and old.find(START) < old.find(END):
            new = old[:old.find(START)] + block + old[block_end(old):]
            action = "replace"
        else:
            return refuse(fn, path + " holds " + str(ns) + " start and " + str(ne) + " end markers of the pointer block, not one pair in order; fix them by hand"), None
    else:
        new = block + b"\n"
        action = "create"
    # the files the budgeted reader would combine with the new AGENTS.md: its
    # user-level file, one per directory from its root down to the parent of
    # <dir>, then this one
    r = READERS[BUDGETED]
    cfg, cfg_path, _ = reader_config(r)
    budget, source = budget_of(r, cfg, cfg_path)
    up, ud = user_level(r)
    user = len(ud) if ud is not None else 0
    above = 0
    for level in read_levels(r, target)[:-1]:
        p, d = level_file(r, level)
        above += len(d) if d is not None else 0
    total = user + above + len(new)
    override = os.path.join(target, r["override"]) if r["override"] else ""
    return 0, {"path": path, "target": target, "old": old, "new": new, "action": action,
               "budget": budget, "source": source, "key": r["budget_key"], "user": user, "above": above,
               "total": total, "override": override if override and load(override) is not None else ""}


def merge_check(fn, plan):
    # rc 3 when the combined files would run past the budget; the override warning
    if plan["total"] > plan["budget"]:
        return refuse(fn, "over the " + BUDGETED + " budget: with the pointer block, " + plan["path"] + " would be " + str(len(plan["new"])) + " bytes, and the files that reader combines " + str(plan["total"]) + " bytes (user-level " + str(plan["user"]) + " + the files from the project root down " + str(plan["above"]) + " + this file " + str(len(plan["new"])) + "), past " + str(plan["budget"]) + " (" + plan["source"] + "), so the block would be cut off; nothing written. Shorten the files, or raise " + plan["key"] + " yourself", 3)
    if plan["override"]:
        plain = ", ".join(n for n, r in READERS.items() if not r["override"])
        out("warning: " + plan["override"] + " exists, so the " + BUDGETED + " reader takes it instead of " + plan["path"] + " at this level and will not see the pointer block (a reader without overrides, " + plain + ", still does); merge the block into the override by hand, or remove it")
    return 0


PLAN_WORDS = {"append": "append the Triforge pointer block to", "replace": "replace the Triforge pointer block in", "create": "create"}
DONE_WORDS = {"append": "appended the Triforge pointer block", "replace": "replaced the Triforge pointer block", "create": "created with the Triforge pointer block"}


def budget_note(plan):
    return "the " + BUDGETED + " budget: " + str(plan["total"]) + " of " + str(plan["budget"]) + " bytes"


def describe(plan):
    return PLAN_WORDS[plan["action"]] + " " + plan["path"] + " (" + str(len(plan["old"]) if plan["old"] is not None else 0) + " -> " + str(len(plan["new"])) + " bytes; " + budget_note(plan) + ")"


def merge_apply(fn, plan):
    why = write_file(plan["target"], "AGENTS.md", plan["old"], plan["new"])
    if why:
        return refuse(fn, plan["path"] + " not written: " + why, 80)
    out("changed: " + plan["path"] + ": " + DONE_WORDS[plan["action"]] + " (" + str(len(plan["new"])) + " bytes; " + budget_note(plan) + ")")
    return 0


def merge(fn, dirarg, template, yes):
    rc, plan = merge_plan(fn, dirarg, template)
    if rc:
        return rc
    if plan["old"] == plan["new"]:
        out("unchanged: " + plan["path"] + " already holds the current pointer block")
        return 0
    rc = merge_check(fn, plan)
    if rc:
        return rc
    if not yes:
        out("needs-ask: would " + describe(plan))
        out("  apply : instruction_merge_pointer " + plan["target"] + " --yes")
        return 20
    return merge_apply(fn, plan)


def convert(fn, arg, template, yes):
    path, kind, level, rc = target_of(fn, arg, STALE_KINDS)
    if rc is not None:
        return rc
    if not lexists(path):
        out("unchanged: " + path + " does not exist; nothing to convert")
        return 0
    data = load(path)
    if data is None:
        return refuse(fn, path + " is not a regular file")
    version = exact_3x(data)
    if not version:
        if is_3x(data):
            return refuse(fn, path + " is a Triforge 3.x template copy with your own edits in it, so it is not removed; edit it by hand: drop the Triforge sections and add the line " + import_line(kind, level, os.path.realpath(level)) + ", or move your own rules into AGENTS.md")
        return refuse(fn, path + " is not a Triforge 3.x template copy; nothing to convert")
    rc, plan = merge_plan(fn, level, template)
    if rc:
        return rc
    rc = merge_check(fn, plan) if plan["old"] != plan["new"] else 0
    if rc:
        return rc
    then = "" if plan["old"] == plan["new"] else ", and " + describe(plan)
    if not yes:
        out("needs-ask: would remove " + path + " (an unmodified copy of the Triforge " + version + " templates/CLAUDE.md), so Claude Code reads AGENTS.md natively" + then)
        out("  apply : instruction_convert_stale " + path + " --yes")
        return 20
    if plan["old"] != plan["new"]:
        rc = merge_apply(fn, plan)
        if rc:
            return rc
    dfd = os.open(os.path.dirname(path), os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        name = os.path.basename(path)
        try:
            fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=dfd)
            with os.fdopen(fd, "rb") as f:
                cur = f.read() if stat.S_ISREG(os.fstat(f.fileno()).st_mode) else None
        except OSError:
            cur = None
        if cur != data:
            return refuse(fn, path + " not removed: it changed while the change was planned", 80)
        os.unlink(name, dir_fd=dfd)
    finally:
        os.close(dfd)
    out("changed: " + path + ": removed (an unmodified copy of the Triforge " + version + " template)")
    lev = os.path.realpath(level)
    for k in CLAUDE_KINDS:
        p = os.path.join(lev, k)
        d = load(p) if lexists(p) else None
        if d is not None and not imports(p, d, {lev}):
            out("note: " + p + " still exists and does not import AGENTS.md, so Claude Code still skips AGENTS.md here; instruction_add_import " + p + " offers the line")
    return 0


def main(argv):
    op, fn, args = argv[0], argv[1], argv[2:]
    if op == "detect":
        return detect(fn, args[0])
    if op == "visibility":
        return visibility(fn, args[0], args[1], args[2])
    if op == "add-import":
        return add_import(fn, args[0], args[1] == "1")
    if op == "merge":
        return merge(fn, args[0], args[1], args[2] == "1")
    if op == "convert":
        return convert(fn, args[0], args[1], args[2] == "1")
    return 64


try:
    sys.exit(main(sys.argv[1:]))
except OSError as e:
    err(sys.argv[2] + ": ERROR " + clean(str(e)) + " (rc 80)")
    sys.exit(80)
'

# _instr_py <op> <helper> <args...> — run _INSTR_PY (rc 69 without python3).
_instr_py() {
  if ! command -v python3 >/dev/null 2>&1; then
    printf '%s: python3 not found — the instruction-file helpers need it (rc 69)\n' "$2" >&2
    return 69
  fi
  python3 -c "${_READ_REGULAR_PY:-$_INSTR_READ_PY}
${_INSTR_PY}" "$@"
}

# _instr_writer_ok <helper> — 0 in a lead context: _lead_only --any-host when
# the loader is in scope (the worker marker, then a lease root), else the
# worker marker alone; rc 45 otherwise.
_instr_writer_ok() {
  if command -v _lead_only >/dev/null 2>&1; then
    _lead_only "$1" --any-host
    return $?
  fi
  if [ -n "${TRIFORGE_LEASE_WORKER:-}" ]; then
    printf '%s: REFUSED — a lead-only helper, called from a lease worker (TRIFORGE_LEASE_WORKER=%s) (rc 45)\n' "$1" "$TRIFORGE_LEASE_WORKER" >&2
    return 45
  fi
  return 0
}

# _instr_reader <lead> — the lead's instruction reader, registry data (KTD1):
# the CLI's "instructions" field through cli_field; nothing for a CLI without
# one, an unregistered name, or no registry in scope (the reader is then
# unknown, and visibility fails closed).
_instr_reader() {
  if command -v cli_field >/dev/null 2>&1; then
    cli_field "$1" instructions 2>/dev/null
    return $?
  fi
  return 2
}

# _instr_template — templates/AGENTS.md of this plugin (the loader's root, else
# the root this file sits in).
_instr_template() {
  printf '%s/templates/AGENTS.md\n' "${_TRIFORGE_PLUGIN_ROOT:-$_INSTR_ROOT}"
}

# _instr_args <helper> <usage> <args...> — parse "<one path> [--yes]" in any
# order into _INSTR_ARG and _INSTR_YES (0|1); rc 64 with the usage line.
_instr_args() {
  local FN=$1 USAGE=$2 A
  shift 2
  _INSTR_ARG=""
  _INSTR_YES=0
  for A in "$@"; do
    case "$A" in
      --yes) _INSTR_YES=1 ;;
      --*)
        printf '%s: usage: %s (unknown flag %s)\n' "$FN" "$USAGE" "$A" >&2
        return 64
        ;;
      *)
        if [ -n "$_INSTR_ARG" ]; then
          printf '%s: usage: %s\n' "$FN" "$USAGE" >&2
          return 64
        fi
        _INSTR_ARG=$A
        ;;
    esac
  done
  return 0
}

# instruction_files_detect [<dir>] — one line per instruction file, read-only:
#   <kind> TAB <where> TAB <state> TAB <path> TAB <import line>
# kind   CLAUDE.md | .claude/CLAUDE.md | CLAUDE.local.md | AGENTS.md |
#        AGENTS.override.md
# where  project (<dir>, default the working directory) | above (each
#        directory above it, nearest first, up to /) | user (~/.claude/CLAUDE.md,
#        then ${CODEX_HOME:-~/.codex}/AGENTS.md and AGENTS.override.md). The
#        user-tier ~/.claude/CLAUDE.md is a user line wherever the walk meets it
#        (compared by identity).
# state  comma-separated: for a CLAUDE.md-family file "imports" (it imports
#        <dir>'s AGENTS.md) or "no-import", then "stale-3x-exact" (an unmodified
#        copy of the 3.x templates/CLAUDE.md), "stale-3x-edited" (a copy with
#        edits) or "user-owned"; for AGENTS.md "pointer" (it holds the marked
#        block) or "no-pointer", AGENTS.override.md "override" first; "unreadable"
#        alone for anything that is not a readable regular file (a FIFO, a
#        directory, a dangling link); "symlink" last when the file or its .claude
#        directory is a link.
# import the line that would import <dir>'s AGENTS.md from that file (relative
#        to it: @AGENTS.md, @../AGENTS.md, @proj/AGENTS.md), "-" otherwise.
# Control characters in a path print as "?". rc 0; 2 <dir> is not a
# directory; 69 no python3.
instruction_files_detect() {
  _instr_py detect instruction_files_detect "${1:-.}"
}

# instruction_pointer_visibility <lead> [<dir>] — whether Triforge's AGENTS.md
# (the one holding the pointer block) reaches <lead> started in <dir> (default
# the working directory), and why: one line "<lead> TAB visible|hidden TAB
# <why>", the why naming the fix. rc 0 visible, 1 hidden, 2 <dir> is not a
# directory, 64 usage, 69 no python3. The lead's reader is registry data
# (KTD1, `cli_field <lead> instructions`), one of READERS: claude-md-shadow
# (the CLAUDE.md family shadows AGENTS.md unless one imports it) or
# agents-chain (an untrusted project, an AGENTS.override.md at the block's
# level, the byte budget). An empty or unknown reader fails closed: "hidden",
# rc 1, the why starting "unknown reader:".
instruction_pointer_visibility() {
  local LEAD=${1:-} READER=""
  if [ -z "$LEAD" ] || [ "$#" -gt 2 ]; then
    echo "instruction_pointer_visibility: usage: instruction_pointer_visibility <lead> [<dir>]" >&2
    return 64
  fi
  READER=$(_instr_reader "$LEAD") || READER=""
  _instr_py visibility instruction_pointer_visibility "$LEAD" "$READER" "${2:-.}"
}

# instruction_add_import <file> [--yes] — add the line that imports this
# project's AGENTS.md (the working directory's) to a CLAUDE.md, .claude/CLAUDE.md
# or CLAUDE.local.md in the project or above it. Without --yes: the planned
# line ("needs-ask: …") and rc 20. A file that already imports it is left
# alone ("unchanged: …", rc 0). Refused (rc 2): another kind of file, a
# user-level file or one in its directory (~/.claude/CLAUDE.md, ~/.claude/,
# ${CODEX_HOME:-~/.codex}/), a file outside the project's directory chain, a
# missing or non-regular file, a symlink or a symlinked directory.
instruction_add_import() {
  _instr_args instruction_add_import "instruction_add_import <file> [--yes]" "$@" || return $?
  if [ -z "$_INSTR_ARG" ]; then
    echo "instruction_add_import: usage: instruction_add_import <file> [--yes]" >&2
    return 64
  fi
  _instr_writer_ok instruction_add_import || return $?
  _instr_py add-import instruction_add_import "$_INSTR_ARG" "$_INSTR_YES"
}

# instruction_merge_pointer [<dir>] [--yes] — put templates/AGENTS.md's marked
# block into <dir>/AGENTS.md (default the working directory): replace the
# marked block there, append it when there is none, create the file when it
# is absent. Before anything is asked or written, the files the budgeted
# reader (agents-chain) would combine — its user-level file
# (AGENTS.override.md over AGENTS.md in ${CODEX_HOME:-~/.codex}), one file per
# directory from the project root down to the parent of <dir> (the override
# over AGENTS.md), and the new <dir>/AGENTS.md — are checked against
# project_doc_max_bytes from ${CODEX_HOME:-~/.codex}/config.toml, else 32768:
# over it, rc 3 naming the sizes, nothing written. An AGENTS.override.md in
# <dir> gets a "warning:" line (that reader takes it instead; the file is
# never written). Refused (rc 2), with or without --yes: a <dir> that is the
# directory of a user-level file (${CODEX_HOME:-~/.codex}, ~/.claude; through
# a link or another spelling too), an AGENTS.md that is a user-level one (a
# hard link), a symlinked or non-regular AGENTS.md, markers not in one
# ordered pair.
instruction_merge_pointer() {
  _instr_args instruction_merge_pointer "instruction_merge_pointer [<dir>] [--yes]" "$@" || return $?
  _instr_writer_ok instruction_merge_pointer || return $?
  _instr_py merge instruction_merge_pointer "${_INSTR_ARG:-.}" "$(_instr_template)" "$_INSTR_YES"
}

# instruction_convert_stale <file> [--yes] — for a CLAUDE.md or .claude/CLAUDE.md
# that is byte for byte a 3.x templates/CLAUDE.md (EXACT_3X): merge the pointer
# block into that project directory's AGENTS.md (instruction_merge_pointer's
# plan and budget check, rc 3 over it), then remove the copy, so Claude Code
# reads AGENTS.md natively; a "note:" line names any CLAUDE.md-family file
# that still shadows it there. A copy with edits, a file that is no 3.x
# copy, or one in the directory of a user-level file, is refused (rc 2) and
# never removed. Without --yes: the plan and rc 20. A file already gone:
# "unchanged: …", rc 0.
instruction_convert_stale() {
  _instr_args instruction_convert_stale "instruction_convert_stale <file> [--yes]" "$@" || return $?
  if [ -z "$_INSTR_ARG" ]; then
    echo "instruction_convert_stale: usage: instruction_convert_stale <file> [--yes]" >&2
    return 64
  fi
  _instr_writer_ok instruction_convert_stale || return $?
  _instr_py convert instruction_convert_stale "$_INSTR_ARG" "$(_instr_template)" "$_INSTR_YES"
}
