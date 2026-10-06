#!/usr/bin/env python3
"""monitors.py — state, classification and output of the two PostToolUse
monitors, context-monitor.sh ("context") and tool-failure-monitor.sh
("failures"). The shell handlers keep the hook contract (worker marker,
ON_CRASH: ALLOW trap, exit 0) and call this with the payload on stdin.

State lives outside the project for either lead (R21):
    ${TMPDIR}/triforge-monitors-<uid>/<checkout name>-<hash>/<session>.context
                                                             <session>.failures
The per-user base and the checkout's directory are checked on every call: each
must be a real directory (not a symlink) owned by this user; group or other
permission bits are taken away (0700). One that fails the check leaves the hook
inert with one note per session. State files are read and written without
following a link (O_NOFOLLOW), and a write goes to an O_EXCL temp file renamed
into place. Every value printed is stripped of control characters, so no
output line can start with "{" (Claude Code parses such hook stdout as JSON).

Exit codes: 0 done (a degraded state is a stderr note, never a code); 3 the
context monitor needs the lead's tool vocabulary (the handler reads it through
the helper library and calls again with CM_VOCAB_FRESH=1, CM_VOCAB=<name TAB
read TAB action>); anything else is a crash the handler reports.
"""
import hashlib
import json
import os
import re
import shlex
import stat
import sys
import time

CONTROL = re.compile(r"[\x00-\x1f\x7f]")


def clean(value, limit=300):
    """A value safe to print on one line: control characters (newlines too) removed."""
    return CONTROL.sub("", str(value))[:limit]


class Inert(Exception):
    """The state directory can't be trusted; the hook does nothing this call."""


def checkout_root():
    """The nearest ancestor of the working directory holding .git, else the working directory."""
    here = os.path.realpath(os.getcwd())
    d = here
    while d and d != "/":
        if os.path.lexists(os.path.join(d, ".git")):
            return d
        d = os.path.dirname(d)
    return here


def _private_dir(path):
    """Create path (0700) when missing; refuse a symlink, a non-directory or
    another user's directory; take group and other bits away."""
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | os.O_NOFOLLOW
    try:
        fd = os.open(path, flags)
    except FileNotFoundError:
        try:
            os.mkdir(path, 0o700)
        except FileExistsError:
            pass
        try:
            fd = os.open(path, flags)
        except OSError as exc:
            raise Inert(path) from exc
    except OSError as exc:
        raise Inert(path) from exc
    try:
        st = os.fstat(fd)
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
            raise Inert(path)
        if st.st_mode & 0o077:
            os.fchmod(fd, 0o700)
            if os.fstat(fd).st_mode & 0o077:
                raise Inert(path)
    finally:
        os.close(fd)
    return path


def state_dirs(root):
    """(base, checkout dir) — both checked private; raises Inert naming the one that is not."""
    base = os.path.join(os.environ.get("TMPDIR") or "/tmp", "triforge-monitors-%d" % os.getuid())
    _private_dir(base)
    name = re.sub(r"[^A-Za-z0-9._-]", "_", os.path.basename(root))[:64] or "root"
    digest = hashlib.sha1(root.encode("utf-8", "surrogateescape")).hexdigest()[:12]
    child = os.path.join(base, name + "-" + digest)
    try:
        _private_dir(child)
    except Inert as exc:
        exc.base = base
        raise
    return base, child


def read_text(path):
    """A regular file's text, read without following a link; "" otherwise."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        return ""
    with os.fdopen(fd, "r", encoding="utf-8", errors="replace") as f:
        if not stat.S_ISREG(os.fstat(f.fileno()).st_mode):
            return ""
        return f.read(65536)


def write_text(path, text):
    """Replace path with text: an O_EXCL|O_NOFOLLOW temp file renamed over it
    (the rename replaces a link at path, never writes through it)."""
    tmp = "%s.tmp.%d" % (path, os.getpid())
    for _ in range(2):
        try:
            fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            break
        except FileExistsError:
            os.unlink(tmp)
    else:
        raise OSError("could not create " + tmp)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    os.rename(tmp, path)


def note_once(marker, message):
    """Print message on stderr unless marker exists; then create marker."""
    if os.path.lexists(marker):
        return
    try:
        write_text(marker, "")
    except OSError:
        pass
    sys.stderr.write(clean(message, 600) + "\n")


def inert_note(exc, who, what, session):
    """The one note for an untrusted state directory (once per session when
    the base is trusted and only the checkout's directory is not)."""
    message = (who + ": NOTE " + str(exc) + " is not a private directory (a symlink, not a directory, "
               "another user's, or its permissions can't be narrowed) — " + what + " is off (R21)")
    base = getattr(exc, "base", "")
    if base:
        note_once(os.path.join(base, os.path.basename(str(exc)) + "." + who + "." + session + ".inert-noted"), message)
    else:
        sys.stderr.write(clean(message, 600) + "\n")


def prune(directory, days=3):
    """Remove regular files older than days in directory (links and dirs left alone)."""
    cutoff = time.time() - days * 86400
    try:
        names = os.listdir(directory)
    except OSError:
        return
    for name in names:
        p = os.path.join(directory, name)
        try:
            st = os.lstat(p)
            if stat.S_ISREG(st.st_mode) and st.st_mtime < cutoff:
                os.unlink(p)
        except OSError:
            pass


def load_payload():
    try:
        d = json.load(sys.stdin)
    except Exception:
        d = {}
    return d if isinstance(d, dict) else {}


def session_of(d):
    return re.sub(r"[^A-Za-z0-9._-]", "_", str(d.get("session_id") or ""))[:80] or "session"


def counts(text, keys):
    out = {}
    for k in keys:
        m = re.search(r"^" + k + r": ([0-9]+)", text, re.M)
        out[k] = int(m.group(1)) if m else 0
    return out


# --- read-only shell commands (the "<tool>(read)" vocabulary entries) --------

READERS = {"cat", "head", "tail", "grep", "egrep", "fgrep", "rg", "ag", "ls", "tree", "wc", "nl", "file", "stat",
           "du", "df", "pwd", "which", "type", "cut", "uniq", "diff", "cmp", "comm", "jq", "basename", "dirname",
           "realpath", "readlink", "column", "od", "xxd", "hexdump", "strings", "fd", "echo", "printf", "true",
           "cd", "find", "sed", "awk", "sort", "git"}
GIT_READS = {"status", "log", "show", "diff", "blame", "grep", "ls-files", "ls-tree", "rev-parse", "describe",
             "cat-file", "shortlog"}
FIND_WRITES = {"-delete", "-exec", "-execdir", "-ok", "-okdir", "-fprint", "-fprint0", "-fprintf", "-fls"}
SEPARATORS = {"|", "||", "&&", ";", "&", "|&", ";;"}
# Output redirections: a file target is a write; only these targets are not.
FILE_REDIRECTS = {">", ">>", ">|", "&>", "&>>"}
NULL_TARGETS = {"/dev/null", "/dev/stdout", "/dev/stderr"}
# sed scripts that only print: N p, N,M p, $ p, /re/ p, /re/,/re/ p
SED_PRINT = re.compile(r"^\s*(?:(?:\d+|\$)(?:\s*,\s*(?:\d+|\$))?|/(?:[^/\\]|\\.)*/(?:\s*,\s*/(?:[^/\\]|\\.)*/)?)?\s*p\s*$")


def _operands(args):
    return [a for a in args if not a.startswith("-") or a == "-"]


def _sed_reads(args):
    scripts, i, rest = [], 0, []
    while i < len(args):
        a = args[i]
        if a in ("-i", "--in-place") or a.startswith("-i") or a.startswith("--in-place"):
            return False
        if a in ("-f", "--file") or a.startswith("--file=") or (a.startswith("-f") and len(a) > 2):
            return False
        if a in ("-e", "--expression"):
            if i + 1 >= len(args):
                return False
            scripts.append(args[i + 1])
            i += 2
            continue
        if a.startswith("--expression="):
            scripts.append(a.split("=", 1)[1])
        elif a.startswith("-e") and len(a) > 2:
            scripts.append(a[2:])
        elif a.startswith("-"):
            pass
        else:
            rest.append(a)
        i += 1
    if not scripts:
        if not rest:
            return False
        scripts.append(rest[0])
    return all(SED_PRINT.match(s) for s in scripts)


def _command_reads(name, args):
    if name not in READERS:
        return False
    if name == "sed":
        return _sed_reads(args)
    if name == "uniq":
        return len(_operands(args)) <= 1
    if name == "xxd":
        return not any(a in ("-r", "-revert") for a in args) and len(_operands(args)) <= 1
    if name == "sort":
        return not any(a.startswith("-o") or a.startswith("--output") for a in args)
    if name == "find":
        return not any(a in FIND_WRITES for a in args)
    if name == "awk":
        return not any(a == "-f" or ">" in a or "|" in a or "system" in a for a in args)
    if name == "rg":
        return not any(a == "--pre" or a.startswith("--pre=") for a in args)
    if name == "fd":
        return not any(a in ("-x", "--exec", "-X", "--exec-batch") or a.startswith("--exec") for a in args)
    if name == "tree":
        return "-o" not in args
    if name == "file":
        return not any(a == "-C" or a == "--compile" for a in args)
    if name == "git":
        while len(args) >= 2 and args[0] == "-C":
            args = args[2:]
        if any(a == "-c" or a.startswith("--config") or a.startswith("--exec-path") for a in args[:1]):
            return False
        sub = [a for a in args if not a.startswith("-")]
        if not sub or sub[0] not in GIT_READS:
            return False
        return not any(a.startswith("--output") or a in ("-O", "--open-files-in-pager", "--ext-diff", "--textconv")
                       or a.startswith("--open-files-in-pager") for a in args)
    return True


def reads_only(cmd, depth=0):
    """True when every command in cmd only reads; anything unparsed is False."""
    if isinstance(cmd, list):
        if len(cmd) >= 3 and os.path.basename(str(cmd[0])) in ("bash", "sh", "zsh") and str(cmd[1]) in ("-c", "-lc"):
            return reads_only(str(cmd[2]), depth + 1)
        cmd = " ".join(shlex.quote(str(w)) for w in cmd)
    if not isinstance(cmd, str) or not cmd.strip() or depth > 2 or "`" in cmd or "$(" in cmd:
        return False
    try:
        lex = shlex.shlex(cmd.replace("\n", " ; "), posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        toks = list(lex)
    except ValueError:
        return False
    segs, cur, i = [], [], 0
    while i < len(toks):
        t = toks[i]
        target = toks[i + 1] if i + 1 < len(toks) else ""
        if t in SEPARATORS:
            segs.append(cur)
            cur = []
        elif t in FILE_REDIRECTS or t == ">&" or t in ("<", "<<", "<<<", "<&"):
            if cur and cur[-1].isdigit():
                cur.pop()   # the descriptor number of N>... is not an operand
            if t in FILE_REDIRECTS and target not in NULL_TARGETS:
                return False
            if t == ">&" and not (target.isdigit() or target == "-"):
                return False
            i += 1
        elif set(t) <= set("();<>|&"):
            return False
        else:
            cur.append(t)
        i += 1
    segs.append(cur)
    segs = [s for s in segs if s]
    if not segs:
        return False
    for s in segs:
        while s and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", s[0]):
            s = s[1:]
        if not s:
            continue
        name, args = os.path.basename(s[0]), s[1:]
        if name in ("bash", "sh", "zsh") and len(args) >= 2 and args[0] in ("-c", "-lc"):
            if not reads_only(args[1], depth + 1):
                return False
            continue
        if not _command_reads(name, args):
            return False
    return True


# --- the two monitors ---------------------------------------------------------

def main_context():
    d = load_payload()
    session = session_of(d)
    root = checkout_root()
    try:
        _base, child = state_dirs(root)
    except Inert as exc:
        inert_note(exc, "context-monitor", "paralysis detection", session)
        return 0
    plugin_root = os.environ.get("CM_PLUGIN_ROOT", "")
    h = hashlib.sha1()
    for p in (os.path.join(root, "ops", "roster.toml"), os.path.join(plugin_root, "scripts", "lib", "registry.sh")):
        try:
            with open(p, "rb") as f:
                h.update(f.read())
        except OSError:
            h.update(b"-")
    key = h.hexdigest() + "|" + plugin_root
    cache_path = os.path.join(child, "lead-vocab")
    if os.environ.get("CM_VOCAB_FRESH") == "1":
        vocab = os.environ.get("CM_VOCAB", "").split("\n")[0]
        write_text(cache_path, key + "\n" + vocab + "\n")
    else:
        cached = read_text(cache_path).split("\n")
        if len(cached) < 2 or cached[0] != key:
            return 3
        vocab = cached[1]
    fields = (vocab.split("\t") + ["", "", ""])[:3]
    lead_name, read_vocab = fields[0], fields[1].split()
    if not read_vocab:
        note_once(os.path.join(child, session + ".vocab-noted"),
                  "context-monitor: NOTE the " + (lead_name or "current") + " lead's tool vocabulary is empty or the lead "
                  "could not be resolved (lead.tool_vocab_read in scripts/lib/registry.sh) — paralysis detection is off "
                  "this session (R21, R44)")
        return 0
    tool = str(d.get("tool_name") or "unknown")
    is_read = tool in read_vocab
    if not is_read and tool + "(read)" in read_vocab:
        ti = d.get("tool_input")
        is_read = isinstance(ti, dict) and reads_only(ti.get("command"))
    state_path = os.path.join(child, session + ".context")
    old = read_text(state_path)
    if not old:
        prune(child)
    c = counts(old, ("total_calls", "consecutive_reads", "last_write_at"))
    total = c["total_calls"] + 1
    reads, last_write = (c["consecutive_reads"] + 1, c["last_write_at"]) if is_read else (0, total)
    write_text(state_path, "---\ntotal_calls: %d\nconsecutive_reads: %d\nlast_write_at: %d\n---\n" % (total, reads, last_write))
    out = []
    if reads >= 8:
        out += ["Context monitor: %d consecutive read-only operations without writing code." % reads,
                "Consider: Are you stuck? Either write code, report a blocker, or spawn a subagent.",
                "If researching intentionally, continue — but be aware of context usage."]
    if total >= 200:
        out += ["Context monitor: CRITICAL — %d tool calls. Context window is likely near capacity." % total,
                "Strongly consider: save state (ops/STATE.md), wrap session, spawn subagents for remaining work."]
    elif total >= 150:
        out.append("Context monitor: WARNING — %d tool calls. Consider spawning subagents for intensive operations." % total)
    for line in out:
        sys.stdout.write(clean(line, 400) + "\n")
    return 0


def main_failures():
    d = load_payload()
    session = session_of(d)
    try:
        _base, child = state_dirs(checkout_root())
    except Inert as exc:
        inert_note(exc, "tool-failure-monitor", "failure tracking", session)
        return 0
    tool = re.sub(r"[^A-Za-z0-9._:()-]", "_", str(d.get("tool_name") or "unknown"))[:80]
    resp = d.get("tool_response", {})
    failed, signal = False, True
    if isinstance(resp, dict):
        failed = resp.get("is_error") is True or bool(resp.get("error"))
    elif isinstance(resp, str):
        m = re.match(r"\s*Exit code:\s*(-?[0-9]+)", resp)
        if m:
            failed = int(m.group(1)) != 0
        else:
            signal = False
    if not signal:
        note_once(os.path.join(child, session + ".signal-noted"),
                  "tool-failure-monitor: NOTE the PostToolUse payload for " + tool + " carries no failure signal "
                  "(plain-text tool_response, no exit code), so its failures are not counted this session (R44)")
    state_path = os.path.join(child, session + ".failures")
    old = read_text(state_path)
    c = counts(old, ("failure_count", "consecutive_failures"))
    if not failed:
        if old:
            write_text(state_path, "---\nfailure_count: %d\nconsecutive_failures: 0\n---\n" % c["failure_count"])
        return 0
    total, consecutive = c["failure_count"] + 1, c["consecutive_failures"] + 1
    write_text(state_path, "---\nfailure_count: %d\nconsecutive_failures: %d\n---\n" % (total, consecutive))
    if consecutive >= 5:
        line = "WARN:%d consecutive tool failures (latest: %s). Consider investigating before continuing." % (consecutive, tool)
    elif total >= 10:
        line = "WARN:%d total tool failures this session (latest: %s). Check %s for details." % (total, tool, state_path)
    else:
        return 0
    sys.stdout.write(clean(line, 600) + "\n")
    return 0


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else ""
    if which == "context":
        sys.exit(main_context())
    if which == "failures":
        sys.exit(main_failures())
    sys.stderr.write("monitors.py: usage: monitors.py context|failures < payload\n")
    sys.exit(64)
