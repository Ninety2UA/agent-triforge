#!/usr/bin/env python3
"""monitors.py — state, classification and output of the two PostToolUse
monitors, context-monitor.sh ("context") and tool-failure-monitor.sh
("failures"). The shell handlers keep the hook contract (worker marker,
ON_CRASH: ALLOW trap, exit 0) and call this with the payload on stdin.

State lives outside the project for either lead (R21):
    ${TMPDIR}/triforge-monitors-<uid>/<checkout name>-<hash>/<session>.context
                                                             <session>.failures
TMPDIR must be a directory no other user can rename entries in: owned by this
user or root, and without group or other write unless it has the sticky bit.
The per-user base and the checkout's directory are checked on every call: each
must be a real directory (not a symlink) owned by this user; group or other
permission bits are taken away (0700). Anything that fails a check leaves the
hook inert with a note (once per session when the base can hold the marker).
The three directories are opened once, without following a link, and held:
every later create, read, write, rename, listing and removal goes through those
descriptors (dir_fd), so a directory renamed or swapped for a symlink after the
check can't redirect a write. State files are read without following a link
and opened O_NONBLOCK (a FIFO planted there fails the regular-file check at
once instead of blocking the hook), and a write goes to an O_EXCL|O_NOFOLLOW
temp file renamed into place. Every
value printed is stripped of control characters, so no output line can start
with "{" (Claude Code parses such hook stdout as JSON).

Exit codes: 0 done (a degraded state is a stderr note, never a code); 3 the
context monitor needs the lead's tool vocabulary (the handler reads it through
the helper library and calls again with CM_VOCAB_FRESH=1, CM_VOCAB=<name TAB
read>); anything else is a crash the handler reports.
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
# O_NONBLOCK on every open (Phase 3 round 4, B6): a FIFO planted where a
# directory or a state file belongs then fails the type check at once, instead
# of blocking the hook in open() before the check runs.
NONBLOCK = getattr(os, "O_NONBLOCK", 0)
DIR_FLAGS = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | NONBLOCK


def clean(value, limit=300):
    """A value safe to print on one line: control characters (newlines too) removed."""
    return CONTROL.sub("", str(value))[:limit]


class Inert(Exception):
    """A state directory can't be trusted; the hook does nothing this call.
    path names it; base_fd is the trusted per-user directory above it (None
    when the base or TMPDIR itself failed); shared marks a TMPDIR another user
    could rename entries in."""

    def __init__(self, path, base_fd=None, shared=False):
        super().__init__(path)
        self.base_fd = base_fd
        self.shared = shared


def checkout_root():
    """The nearest ancestor of the working directory holding .git, else the working directory."""
    here = os.path.realpath(os.getcwd())
    d = here
    while d and d != "/":
        if os.path.lexists(os.path.join(d, ".git")):
            return d
        d = os.path.dirname(d)
    return here


def _open_private(name, dir_fd, path, base_fd=None):
    """Open the directory name (relative to dir_fd) without following a link,
    creating it 0700 when missing; refuse a symlink, a non-directory or another
    user's directory (Inert); take group and other bits away. Returns the fd."""
    flags = DIR_FLAGS | os.O_NOFOLLOW
    try:
        fd = os.open(name, flags, dir_fd=dir_fd)
    except FileNotFoundError:
        try:
            os.mkdir(name, 0o700, dir_fd=dir_fd)
        except FileExistsError:
            pass
        try:
            fd = os.open(name, flags, dir_fd=dir_fd)
        except OSError as exc:
            raise Inert(path, base_fd) from exc
    except OSError as exc:
        raise Inert(path, base_fd) from exc
    try:
        st = os.fstat(fd)
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
            raise Inert(path, base_fd)
        if st.st_mode & 0o077:
            os.fchmod(fd, 0o700)
            if os.fstat(fd).st_mode & 0o077:
                raise Inert(path, base_fd)
    except BaseException:
        os.close(fd)
        raise
    return fd


class StateDir:
    """The checkout's monitor directory and the per-user base above it, held
    open: every operation below goes through their descriptors."""

    def __init__(self, root):
        tmp = os.environ.get("TMPDIR") or "/tmp"
        try:
            tfd = os.open(tmp, DIR_FLAGS)
        except OSError as exc:
            raise Inert(tmp) from exc
        try:
            st = os.fstat(tfd)
            if st.st_uid not in (os.getuid(), 0) or (st.st_mode & 0o022 and not st.st_mode & stat.S_ISVTX):
                raise Inert(tmp, shared=True)
            base_name = "triforge-monitors-%d" % os.getuid()
            self.base_path = os.path.join(tmp, base_name)
            self.base_fd = _open_private(base_name, tfd, self.base_path)
        finally:
            os.close(tfd)
        name = re.sub(r"[^A-Za-z0-9._-]", "_", os.path.basename(root))[:64] or "root"
        self.child_name = name + "-" + hashlib.sha1(root.encode("utf-8", "surrogateescape")).hexdigest()[:12]
        self.path = os.path.join(self.base_path, self.child_name)
        self.fd = _open_private(self.child_name, self.base_fd, self.path, self.base_fd)

    def read(self, name):
        return read_at(self.fd, name)

    def odd(self, name):
        """Whether name is there but neither a regular file nor a link (a FIFO,
        a socket, a directory): read() gave "" for it, and the next write
        replaces it (B6)."""
        try:
            mode = os.stat(name, dir_fd=self.fd, follow_symlinks=False).st_mode
        except OSError:
            return False
        return not stat.S_ISREG(mode) and not stat.S_ISLNK(mode)

    def note_odd(self, name, who, session):
        if self.odd(name):
            self.note_once(session + "." + name + ".odd-noted",
                           who + ": NOTE the state file " + os.path.join(self.path, name) + " is not a regular file "
                           "(a FIFO or a socket, say), so it was read as empty and is replaced (B6)")

    def write(self, name, text):
        write_at(self.fd, name, text)

    def note_once(self, name, message):
        note_once_at(self.fd, name, message)

    def prune(self, days=3):
        """Remove regular files older than days (links and dirs left alone)."""
        cutoff = time.time() - days * 86400
        try:
            names = os.listdir(self.fd)
        except OSError:
            return
        for name in names:
            try:
                st = os.stat(name, dir_fd=self.fd, follow_symlinks=False)
                if stat.S_ISREG(st.st_mode) and st.st_mtime < cutoff:
                    os.unlink(name, dir_fd=self.fd)
            except OSError:
                pass


def read_regular(name, dir_fd=None, follow=False, limit=65536):
    """A regular file's bytes (up to limit), read relative to dir_fd (without
    following a link unless follow); None for anything else. Opened
    O_NONBLOCK, so a FIFO there returns at once; the flag is cleared before
    reading."""
    try:
        fd = os.open(name, os.O_RDONLY | NONBLOCK | (0 if follow else os.O_NOFOLLOW), dir_fd=dir_fd)
    except OSError:
        return None
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return None
        if NONBLOCK:
            os.set_blocking(fd, True)
        with os.fdopen(fd, "rb") as f:
            fd = -1
            return f.read(limit)
    except OSError:
        return None
    finally:
        if fd >= 0:
            os.close(fd)


def read_at(dir_fd, name):
    """A regular file's text, read relative to dir_fd without following a link; "" otherwise."""
    return (read_regular(name, dir_fd) or b"").decode("utf-8", "replace")


def write_at(dir_fd, name, text):
    """Replace name (relative to dir_fd) with text: an O_EXCL|O_NOFOLLOW temp
    file renamed over it (the rename replaces a link at name, never writes
    through it)."""
    tmp = "%s.tmp.%d" % (name, os.getpid())
    for _ in range(2):
        try:
            fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=dir_fd)
            break
        except FileExistsError:
            os.unlink(tmp, dir_fd=dir_fd)
    else:
        raise OSError("could not create " + tmp)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    os.rename(tmp, name, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)


def note_once_at(dir_fd, name, message):
    """Print message on stderr unless the marker name exists in dir_fd; then create it."""
    try:
        os.stat(name, dir_fd=dir_fd, follow_symlinks=False)
        return
    except OSError:
        pass
    try:
        write_at(dir_fd, name, "")
    except OSError:
        pass
    sys.stderr.write(clean(message, 600) + "\n")


def inert_note(exc, who, what, session):
    """The note for an untrusted state directory (once per session when the
    per-user base is trusted and holds the marker, else on every call)."""
    if exc.shared:
        message = (who + ": NOTE TMPDIR " + str(exc) + " lets another user rename entries in it (group or other write "
                   "without the sticky bit, or another user's directory) — " + what + " is off (R21)")
    else:
        message = (who + ": NOTE " + str(exc) + " is not a private directory (a symlink, not a directory, "
                   "another user's, or its permissions can't be narrowed) — " + what + " is off (R21)")
    if exc.base_fd is not None:
        note_once_at(exc.base_fd, os.path.basename(str(exc)) + "." + who + "." + session + ".inert-noted", message)
    else:
        sys.stderr.write(clean(message, 600) + "\n")


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
# Options read with their arguments: the short letters that take a value
# (attached, "-k2", or as the next word when the letter ends its cluster) and
# the long names that take one when no "=" is attached.
UNIQ_VALUE = ("fsw", ("--skip-fields", "--skip-chars", "--check-chars"))
SORT_VALUE = ("ktST", ("--key", "--field-separator", "--buffer-size", "--temporary-directory", "--parallel",
                       "--batch-size", "--random-source", "--files0-from", "--sort"))
XXD_VALUE = {"-c", "-cols", "-g", "-groupsize", "-l", "-len", "-o", "-offset", "-s", "-seek", "-n", "-name"}


def _long_is(a, full, shortest):
    """Whether the long option a (with or without =value) names full, as GNU
    getopt accepts any unambiguous prefix of at least shortest characters."""
    name = a.split("=", 1)[0]
    return len(name) >= shortest and full.startswith(name)


def _walk(args, spec, on_short=None, on_long=None):
    """The operands of args under spec (value letters, value long names):
    option values are skipped, attached or not. on_short(letter) and
    on_long(arg) return False to stop the walk (the command writes); then
    None is returned."""
    letters, longs = spec
    ops, i = [], 0
    while i < len(args):
        a = args[i]
        if a == "--":
            ops += args[i + 1:]
            break
        if a.startswith("--"):
            if on_long is not None and on_long(a) is False:
                return None
            if "=" not in a and any(_long_is(a, full, 4) for full in longs):
                i += 1
        elif a.startswith("-") and a != "-":
            for j, c in enumerate(a[1:]):
                if on_short is not None and on_short(c) is False:
                    return None
                if c in letters:
                    if j == len(a) - 2:
                        i += 1
                    break
        else:
            ops.append(a)
        i += 1
    return ops


def _sed_reads(args):
    scripts, i, rest = [], 0, []
    while i < len(args):
        a = args[i]
        if a.startswith("--"):
            if _long_is(a, "--in-place", 4) or _long_is(a, "--file", 3) or _long_is(a, "--line-length", 3):
                return False
            if _long_is(a, "--expression", 4):
                if "=" in a:
                    scripts.append(a.split("=", 1)[1])
                elif i + 1 < len(args):
                    scripts.append(args[i + 1])
                    i += 1
                else:
                    return False
        elif a.startswith("-") and a != "-":
            for j, c in enumerate(a[1:]):
                if c in "ifl":
                    return False   # in place, a script file, a line length: not a plain print
                if c == "e":
                    if j < len(a) - 2:
                        scripts.append(a[j + 2:])
                    elif i + 1 < len(args):
                        scripts.append(args[i + 1])
                        i += 1
                    else:
                        return False
                    break
        else:
            rest.append(a)
        i += 1
    if not scripts:
        if not rest:
            return False
        scripts.append(rest[0])
    return all(SED_PRINT.match(s) for s in scripts)


def _awk_reads(args):
    """Only -F and -v (attached or not) are read; any other option runs, loads
    or writes code. The program text must not redirect, pipe or call system."""
    i, prog = 0, None
    while i < len(args):
        a = args[i]
        if a == "--":
            prog = args[i + 1] if i + 1 < len(args) else None
            break
        if a in ("-F", "-v"):
            i += 2
            continue
        if a.startswith("-F") or a.startswith("-v"):
            i += 1
            continue
        if a.startswith("-") and a != "-":
            return False
        prog = a
        break
    if prog is None:
        return False
    return not any(x in prog for x in (">", "|", "system"))


def _xxd_reads(args):
    ops, i = [], 0
    while i < len(args):
        a = args[i]
        if a.startswith("-r"):
            return False   # -r / -revert writes a binary
        if a in XXD_VALUE:
            i += 2
            continue
        if not (a.startswith("-") and a != "-"):
            ops.append(a)
        i += 1
    return len(ops) <= 1   # a second operand is the output file


def _command_reads(name, args):
    if name not in READERS:
        return False
    if name == "sed":
        return _sed_reads(args)
    if name == "uniq":
        ops = _walk(args, UNIQ_VALUE)
        return ops is not None and len(ops) <= 1   # a second operand is the output file
    if name == "xxd":
        return _xxd_reads(args)
    if name == "sort":
        return _walk(args, SORT_VALUE, on_short=lambda c: c != "o",
                     on_long=lambda a: not (_long_is(a, "--output", 3) or _long_is(a, "--compress-program", 4))) is not None
    if name == "find":
        return not any(a in FIND_WRITES for a in args)
    if name == "awk":
        return _awk_reads(args)
    if name == "rg":
        return not any(_long_is(a, "--pre", 5) for a in args if a.startswith("--"))
    if name == "ag":
        return not any(_long_is(a, "--pager", 4) for a in args if a.startswith("--"))
    if name == "fd":
        return not any((a.startswith("--") and (_long_is(a, "--exec", 4) or _long_is(a, "--exec-batch", 7)))
                       or (a.startswith("-") and not a.startswith("--") and ("x" in a[1:] or "X" in a[1:]))
                       for a in args)
    if name == "tree":
        return not any(a.startswith("-") and not a.startswith("--") and "o" in a[1:] for a in args)
    if name == "file":
        return not any(a == "--compile" or (a.startswith("-") and not a.startswith("--") and "C" in a[1:]) for a in args)
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
        sd = StateDir(root)
    except Inert as exc:
        inert_note(exc, "context-monitor", "paralysis detection", session)
        return 0
    plugin_root = os.environ.get("CM_PLUGIN_ROOT", "")
    h = hashlib.sha1()
    for p in (os.path.join(root, "ops", "roster.toml"), os.path.join(plugin_root, "scripts", "lib", "registry.sh")):
        data = read_regular(p, follow=True, limit=1 << 20)
        h.update(b"-" if data is None else data)
    key = h.hexdigest() + "|" + plugin_root
    if os.environ.get("CM_VOCAB_FRESH") == "1":
        vocab = os.environ.get("CM_VOCAB", "").split("\n")[0]
        sd.note_odd("lead-vocab", "context-monitor", session)
        sd.write("lead-vocab", key + "\n" + vocab + "\n")
    else:
        cached = sd.read("lead-vocab").split("\n")
        if len(cached) < 2 or cached[0] != key:
            return 3
        vocab = cached[1]
    lead_name, read_list = (vocab.split("\t") + ["", ""])[:2]
    read_vocab = read_list.split()
    if not read_vocab:
        sd.note_once(session + ".vocab-noted",
                     "context-monitor: NOTE the " + (lead_name or "current") + " lead's tool vocabulary is empty or the lead "
                     "could not be resolved (lead.tool_vocab_read in scripts/lib/registry.sh) — paralysis detection is off "
                     "this session (R21, R44)")
        return 0
    tool = str(d.get("tool_name") or "unknown")
    is_read = tool in read_vocab
    if not is_read and tool + "(read)" in read_vocab:
        ti = d.get("tool_input")
        is_read = isinstance(ti, dict) and reads_only(ti.get("command"))
    state = session + ".context"
    old = sd.read(state)
    if not old:
        sd.note_odd(state, "context-monitor", session)
        sd.prune()
    c = counts(old, ("total_calls", "consecutive_reads", "last_write_at"))
    total = c["total_calls"] + 1
    reads, last_write = (c["consecutive_reads"] + 1, c["last_write_at"]) if is_read else (0, total)
    sd.write(state, "---\ntotal_calls: %d\nconsecutive_reads: %d\nlast_write_at: %d\n---\n" % (total, reads, last_write))
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
        sd = StateDir(checkout_root())
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
        sd.note_once(session + ".signal-noted",
                     "tool-failure-monitor: NOTE the PostToolUse payload for " + tool + " carries no failure signal "
                     "(plain-text tool_response, no exit code), so its failures are not counted this session (R44)")
    state = session + ".failures"
    old = sd.read(state)
    if not old:
        sd.note_odd(state, "tool-failure-monitor", session)
    c = counts(old, ("failure_count", "consecutive_failures"))
    if not failed:
        new = "---\nfailure_count: %d\nconsecutive_failures: 0\n---\n" % c["failure_count"]
        if old and old != new:
            sd.write(state, new)
        return 0
    total, consecutive = c["failure_count"] + 1, c["consecutive_failures"] + 1
    sd.write(state, "---\nfailure_count: %d\nconsecutive_failures: %d\n---\n" % (total, consecutive))
    if consecutive >= 5:
        line = "WARN:%d consecutive tool failures (latest: %s). Consider investigating before continuing." % (consecutive, tool)
    elif total >= 10:
        line = "WARN:%d total tool failures this session (latest: %s). Check %s for details." % (total, tool,
                                                                                               os.path.join(sd.path, state))
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
