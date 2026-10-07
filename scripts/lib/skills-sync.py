#!/usr/bin/env python3
"""scripts/lib/skills-sync.py — the .agents/skills/ refresh (KTD12, R31).

One implementation for both callers: hooks/handlers/session-start.sh (the
project's own .agents/skills/) and _lease_provision_skills in
scripts/lib/lease.sh (a lease worktree's copy).

Ownership rule: Triforge replaces or retires a directory only when it can show
the directory is its own, unchanged copy. The stamp
.agents/skills/.triforge-plugin-version records a content digest for every
directory Triforge wrote:

    version=<plugin version>
    format=2
    skills=<comma-separated names Triforge wrote>
    digest <name> <sha256>

A directory is Triforge-owned when its current digest equals the digest the
stamp recorded for that name. A legacy 3.3.0-3.3.2 stamp (version= and
skills= only, no digests) is migrated: a listed directory counts as
Triforge-owned only when its digest matches a released copy of that skill
(scripts/lib/skill-digests.txt). Everything else is user-owned: skipped with a
notice, never deleted. Without a stamp, only empty slots are written (a
directory whose content already equals the shipped copy is adopted as is).

Safety: a symlinked .agents or .agents/skills is left untouched; every name
must match ^[a-z0-9][a-z0-9-]*$, and every existing entry must be a plain
directory directly inside .agents/skills. The project directory, .agents and
.agents/skills are opened once, each without following a link and relative to
the one before, and every later read, copy, removal, rename and the stamp go
through those descriptors (dir_fd): a directory swapped for a symlink after the
check can't redirect a write out of the project, because the descriptor still
names the directory that was checked (Phase 3 round 4, B2). Copies preserve
symlinks as links (never followed). The stamp is written last, and only when
every copy succeeded, through a temporary file created O_CREAT|O_EXCL|O_NOFOLLOW
under a random name and renamed over it; a copy in flight lives in a directory
made under a random name. No temporary name is predictable, so a symlink
planted at one is never written through.

Lead workflows (KTD12, R16): a shipped skills/at-* directory is a lead workflow
that reaches a lead only from its plugin install. It is never copied into
.agents/skills or a worktree, never listed in the stamp, and an at-* directory
already present there is never replaced or retired, whatever a stamp says —
for refresh purposes the at- prefix means "not Triforge-shipped". A dot entry
under skills/ (skills/.devin-plugin/, the Devin manifest) is packaging, not a
skill: never copied, digested or reported.

Add-only copies (KTD12, KTD16): `add` writes the same portable set into
another skills directory of a fresh lease worktree, .claude/skills for a
claude -p worker. It adds names only: an entry already present (a tracked
directory such as this repo's .claude/skills/watch-cycle/, or a user's own
copy) and every name passed in --skip (the names git tracks there) are left
alone. It never replaces, retires or stamps anything, and walks to its
directory the same way, by descriptors that refuse a symlink.

Usage:
    skills-sync.py sync --plugin-root <dir> --project <dir> [--prefix <text>]
    skills-sync.py add --plugin-root <dir> --project <dir> --dest <rel dir> [--skip <a,b>] [--prefix <text>]
    skills-sync.py digest <dir>
    skills-sync.py table --repo <git checkout> [--tags <glob>]

`sync` and `add` print one notice per line (each starting with --prefix) and
always exit 0 for a refusal or partial copy; 2 is a usage error.
"""

import errno
import hashlib
import json
import os
import re
import secrets
import stat
import subprocess
import sys

STAMP_NAME = ".triforge-plugin-version"
STAMP_FORMAT = "2"
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
IGNORED_FILES = (".DS_Store",)
TMP_PREFIX = ".triforge-tmp-"   # copies in flight; never a valid skill name (NAME_RE), cleaned up on the next run
LEAD_PREFIX = "at-"              # lead workflows: never copied, never owned, never retired (KTD12)
NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)
CLOEXEC = getattr(os, "O_CLOEXEC", 0)
DIR_FLAGS = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | NOFOLLOW | CLOEXEC
# a symlink opened O_NOFOLLOW fails ELOOP (Linux), ENOTDIR (macOS, with
# O_DIRECTORY) or EMLINK (FreeBSD); a file opened O_DIRECTORY fails ENOTDIR
NOT_A_DIR = (errno.ELOOP, errno.ENOTDIR, errno.EMLINK)


def lead_workflow(name):
    return name.startswith(LEAD_PREFIX)


def _entry_line(kind, rel, value):
    return (kind + "\0" + rel + "\0" + value + "\n").encode("utf-8", "surrogateescape")


# --- descriptor-relative primitives (Phase 3 round 4, B2) --------------------
# Every path below is one name relative to a directory descriptor; nothing
# under the project is reached by a path string, so no directory on the way
# can be swapped for a symlink between a check and the write it guards.

def open_dir(name, dir_fd):
    """The directory name in dir_fd, opened without following a link."""
    return os.open(name, DIR_FLAGS, dir_fd=dir_fd)


def lstat_at(dir_fd, name):
    """The lstat of name in dir_fd, or None when nothing is there."""
    try:
        return os.stat(name, dir_fd=dir_fd, follow_symlinks=False)
    except FileNotFoundError:
        return None


def _is_dir_following(dir_fd, name):
    try:
        return stat.S_ISDIR(os.stat(name, dir_fd=dir_fd).st_mode)
    except OSError:
        return False


def _digest_entries(dfd, rel, entries):
    """The entries dir_digest hashes, for the tree open at dfd: what os.walk
    without following links sees (a link to a directory is listed with the
    directories, so .DS_Store is skipped only as a file or a link to one)."""
    for name in os.listdir(dfd):
        path = rel + "/" + name if rel else name
        st = os.stat(name, dir_fd=dfd, follow_symlinks=False)
        if stat.S_ISLNK(st.st_mode):
            if name in IGNORED_FILES and not _is_dir_following(dfd, name):
                continue
            entries.append(("L", path, os.readlink(name, dir_fd=dfd)))
        elif stat.S_ISDIR(st.st_mode):
            cfd = open_dir(name, dfd)
            try:
                _digest_entries(cfd, path, entries)
            finally:
                os.close(cfd)
        elif name in IGNORED_FILES:
            continue
        elif not stat.S_ISREG(st.st_mode):
            raise OSError(errno.EINVAL, "not a regular file", path)
        else:
            # O_NONBLOCK: a FIFO swapped in after the lstat fails the type
            # check below instead of blocking the refresh
            fd = os.open(name, os.O_RDONLY | NOFOLLOW | CLOEXEC | getattr(os, "O_NONBLOCK", 0), dir_fd=dfd)
            with os.fdopen(fd, "rb") as fh:
                if not stat.S_ISREG(os.fstat(fh.fileno()).st_mode):
                    raise OSError(errno.EINVAL, "not a regular file", path)
                entries.append(("F", path, hashlib.sha256(fh.read()).hexdigest()))


def digest_fd(dfd):
    """sha256 over the sorted (kind, relative path, content hash | link target)
    entries of the directory tree open at dfd. Empty directories and .DS_Store
    don't count, so the digest matches what git would record. Anything that is
    not a regular file, a symlink or a directory (a FIFO, a socket, a device —
    which git can't carry, so it is never Triforge's) makes the tree
    unreadable: opening a FIFO would block the refresh. A directory that can't
    be listed raises too, so safe_digest reports it instead of owning it."""
    entries = []
    _digest_entries(dfd, "", entries)
    h = hashlib.sha256()
    for kind, rel, value in sorted(entries):
        h.update(_entry_line(kind, rel, value))
    return h.hexdigest()


def dir_digest(path):
    """digest_fd of the directory at path (the plugin's own tree, or the
    `digest` command's argument)."""
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | CLOEXEC)
    try:
        return digest_fd(fd)
    finally:
        os.close(fd)


def safe_digest(path):
    """dir_digest, or None when a file in the tree can't be read: that one
    directory is left alone and reported, and the rest of the refresh goes on."""
    try:
        return dir_digest(path)
    except OSError:
        return None


def safe_digest_at(dir_fd, name):
    """safe_digest of the directory name in dir_fd, opened without following a link."""
    try:
        fd = open_dir(name, dir_fd)
    except OSError:
        return None
    try:
        return digest_fd(fd)
    except OSError:
        return None
    finally:
        os.close(fd)


def rmtree_at(dir_fd, name):
    """Remove the directory name in dir_fd and everything in it, descending by
    descriptors opened without following a link (a link is unlinked, never
    followed). Raises OSError."""
    fd = open_dir(name, dir_fd)
    try:
        for child in os.listdir(fd):
            st = os.stat(child, dir_fd=fd, follow_symlinks=False)
            if stat.S_ISDIR(st.st_mode):
                rmtree_at(fd, child)
            else:
                os.unlink(child, dir_fd=fd)
    finally:
        os.close(fd)
    os.rmdir(name, dir_fd=dir_fd)


def copytree_at(src, dfd):
    """Copy the contents of the plugin directory src into the directory open
    at dfd: links as links, files and directories with their permission bits
    and times (as shutil.copytree gives them), every entry created exclusively
    relative to the descriptor. Raises OSError."""
    for entry in sorted(os.listdir(src)):
        s = os.path.join(src, entry)
        st = os.lstat(s)
        if stat.S_ISLNK(st.st_mode):
            os.symlink(os.readlink(s), entry, dir_fd=dfd)
        elif stat.S_ISDIR(st.st_mode):
            os.mkdir(entry, 0o700, dir_fd=dfd)
            cfd = open_dir(entry, dfd)
            try:
                copytree_at(s, cfd)
                os.chmod(cfd, stat.S_IMODE(st.st_mode))
                os.utime(cfd, ns=(st.st_atime_ns, st.st_mtime_ns))
            finally:
                os.close(cfd)
        else:
            with open(s, "rb") as fh:
                data = fh.read()
            fd = os.open(entry, os.O_WRONLY | os.O_CREAT | os.O_EXCL | NOFOLLOW | CLOEXEC, 0o600, dir_fd=dfd)
            with os.fdopen(fd, "wb") as out:
                out.write(data)
                out.flush()
                os.chmod(out.fileno(), stat.S_IMODE(st.st_mode))
                os.utime(out.fileno(), ns=(st.st_atime_ns, st.st_mtime_ns))


def read_stamp_at(dir_fd):
    """read_stamp of the stamp in the directory open at dir_fd: a regular file
    opened without following a link (O_NONBLOCK, so a FIFO there fails the
    type check instead of blocking), else None."""
    try:
        fd = os.open(STAMP_NAME, os.O_RDONLY | NOFOLLOW | CLOEXEC | getattr(os, "O_NONBLOCK", 0), dir_fd=dir_fd)
    except OSError:
        return None
    with os.fdopen(fd, "rb") as fh:
        if not stat.S_ISREG(os.fstat(fh.fileno()).st_mode):
            return None
        try:
            text = fh.read().decode("utf-8", "replace")
        except OSError:
            return None
    return parse_stamp(text.splitlines())


def read_stamp(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return None
    return parse_stamp(lines)


def parse_stamp(lines):
    stamp = {"version": "", "format": "", "skills": [], "digests": {}}
    for line in lines:
        if line.startswith("version="):
            stamp["version"] = line[len("version="):].strip()
        elif line.startswith("format="):
            stamp["format"] = line[len("format="):].strip()
        elif line.startswith("skills="):
            stamp["skills"] = [n.strip() for n in line[len("skills="):].split(",") if n.strip()]
        elif line.startswith("digest "):
            parts = line.split()
            if len(parts) == 3:
                stamp["digests"][parts[1]] = parts[2]
    return stamp


def read_table(path):
    table = {}
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                if not line.strip() or line.startswith("#"):
                    continue
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 2:
                    table.setdefault(parts[0], set()).add(parts[1])
    except OSError:
        pass
    return table


def plugin_version(root):
    try:
        with open(os.path.join(root, ".claude-plugin", "plugin.json"), encoding="utf-8") as fh:
            return str(json.load(fh).get("version", "")).strip()
    except Exception:
        return ""


def is_plain_dir(st):
    """An lstat result that is a directory (a link never is)."""
    return st is not None and stat.S_ISDIR(st.st_mode)


class Refused(Exception):
    """A directory on the way can't be used; the message is the notice."""


def enter_dir(parent_fd, name, create, shown):
    """The directory name in parent_fd, opened without following a link and
    created first when absent and create is set. Refused (with the notice)
    for a link or a non-directory; None when absent and not created."""
    st = lstat_at(parent_fd, name)
    if st is not None and stat.S_ISLNK(st.st_mode):
        raise Refused(shown + " is a symlink — left untouched (Triforge refreshes only a real directory inside the project; remove the link to let it manage the copy).")
    if st is not None and not stat.S_ISDIR(st.st_mode):
        if create or shown != ".agents":   # a file at .agents/skills: the refresh can't make it (a degraded run, as before)
            raise Refused("WARNING could not create " + shown + " — skills not refreshed (session continues).")
        raise Refused(shown + " exists and is not a directory — skills not refreshed.")
    if st is None:
        if not create:
            return None
        try:
            os.mkdir(name, 0o777, dir_fd=parent_fd)
        except FileExistsError:
            pass
        except OSError:
            raise Refused("WARNING could not create " + shown + " — skills not refreshed (session continues).")
    try:
        return open_dir(name, parent_fd)
    except OSError as exc:
        if exc.errno in NOT_A_DIR:   # swapped for a link or a file after the lstat
            raise Refused(shown + " is a symlink or not a directory — left untouched.")
        raise Refused("WARNING could not open " + shown + " — skills not refreshed (session continues).")


def sync(plugin_root, project, prefix):
    out = []

    def note(msg):
        out.append(prefix + msg)

    src_root = os.path.join(plugin_root, "skills")
    if not os.path.isdir(src_root):
        return out
    version = plugin_version(plugin_root)
    table = read_table(os.path.join(plugin_root, "scripts", "lib", "skill-digests.txt"))
    try:
        fds = [os.open(os.path.realpath(project), DIR_FLAGS)]
    except OSError:
        note("WARNING could not open the project directory — skills not refreshed (session continues).")
        return out
    try:
        agents_fd = enter_dir(fds[0], ".agents", False, ".agents")
        dest_fd = None
        if agents_fd is not None:
            fds.append(agents_fd)
            dest_fd = enter_dir(agents_fd, "skills", False, ".agents/skills")
            if dest_fd is not None:
                fds.append(dest_fd)
        stamp = read_stamp_at(dest_fd) if dest_fd is not None else None
        if dest_fd is not None and stamp and version and stamp["version"] == version and stamp["format"] == STAMP_FORMAT:
            return out    # current: no copies, no notice
        if dest_fd is not None and not version:
            return out    # plugin version unreadable: keep what is deployed rather than refresh blind
        if agents_fd is None:
            agents_fd = enter_dir(fds[0], ".agents", True, ".agents")
            fds.append(agents_fd)
        if dest_fd is None:
            dest_fd = enter_dir(agents_fd, "skills", True, ".agents/skills")
            fds.append(dest_fd)
        _sync_at(dest_fd, src_root, version, table, stamp, note)
    except Refused as exc:
        note(str(exc))
    finally:
        for fd in fds:
            os.close(fd)
    return out


def _sync_at(dest_fd, src_root, version, table, stamp, note):
    """The refresh itself, every step relative to dest_fd (.agents/skills)."""

    def owned(name, digest):
        if stamp is None or lead_workflow(name):
            return False
        if stamp["format"] == STAMP_FORMAT:
            return stamp["digests"].get(name) == digest
        return name in stamp["skills"] and digest in table.get(name, ())

    shipped = []
    written = {}
    kept, skipped, retired, failed = [], [], [], False
    for leftover in os.listdir(dest_fd):
        # a copy (a directory) or a stamp (a file) an earlier run did not finish
        st = lstat_at(dest_fd, leftover) if leftover.startswith(TMP_PREFIX) else None
        if st is None or stat.S_ISLNK(st.st_mode):
            continue
        try:
            if stat.S_ISDIR(st.st_mode):
                rmtree_at(dest_fd, leftover)
            else:
                os.unlink(leftover, dir_fd=dest_fd)
        except OSError:
            pass
    for name, valid in shipped_entries(src_root):
        if not valid:
            skipped.append(name + "(invalid-name)")
            continue
        src = os.path.join(src_root, name)
        shipped.append(name)
        st = lstat_at(dest_fd, name)
        if st is not None:
            if not is_plain_dir(st):
                skipped.append(name + "(not-a-plain-directory)")
                continue
            current, shipped_digest = safe_digest_at(dest_fd, name), safe_digest(src)
            if current is None or shipped_digest is None:
                failed = failed or shipped_digest is None
                skipped.append(name + ("(unreadable)" if current is None else "(unreadable-source)"))
                continue
            if current == shipped_digest:
                written[name] = current    # already the shipped copy
                continue
            if not owned(name, current):
                kept.append(name)
                continue
        try:
            written[name] = copy_into_place(src, dest_fd, name, True)
        except OSError:
            failed = True
            skipped.append(name + ("(replace-failed)" if lstat_at(dest_fd, name) is not None else "(copy-failed)"))

    previous = []
    if stamp:
        previous = sorted(set(stamp["skills"]) | set(stamp["digests"]))
    retired_kept = []
    for name in previous:
        if name in shipped or not NAME_RE.match(name) or lead_workflow(name):
            continue    # an at-* entry in a stamp never makes an at-* directory Triforge's to retire
        st = lstat_at(dest_fd, name)
        if st is None:
            continue
        digest = safe_digest_at(dest_fd, name) if is_plain_dir(st) else None
        if digest is not None and owned(name, digest):
            try:
                rmtree_at(dest_fd, name)
                retired.append(name)
            except OSError:
                skipped.append(name + "(remove-failed)")
        else:
            retired_kept.append(name)

    if failed:
        note("WARNING .agents/skills refresh incomplete (stamp not written; re-runs next session).")
    else:
        body = ["version=" + version, "format=" + STAMP_FORMAT, "skills=" + ",".join(sorted(written))]
        body += ["digest " + n + " " + written[n] for n in sorted(written)]
        try:
            replace_file_at(dest_fd, STAMP_NAME, "\n".join(body) + "\n")
            note(".agents/skills refreshed to " + (version or "?") + " (Triforge replaces only its own unchanged copies, identified by content digest; keep customizations in a differently named directory; lead workflows (at-*) are not copied)"
                 + ("; retired no-longer-shipped: " + " ".join(retired) if retired else "") + ".")
        except OSError:
            note("WARNING .agents/skills refreshed but the version stamp could not be written — the refresh re-runs next session.")
    if kept:
        note(".agents/skills kept as user-owned (content differs from Triforge's copy, so it was not replaced; the shipped version of each is not installed there): " + " ".join(kept) + ".")
    if retired_kept:
        note(".agents/skills kept as user-owned (no longer shipped, but changed since Triforge wrote it): " + " ".join(retired_kept) + ".")
    if skipped:
        note(".agents/skills entries left untouched (symlink, not a plain directory directly inside .agents/skills, unreadable, or invalid name): " + " ".join(skipped) + ".")


def shipped_entries(src_root):
    """The shipped skill directories under skills/, sorted, as (name, valid)
    pairs: every plain directory except a dot entry (packaging: skills/
    .devin-plugin/ is the Devin manifest) and an at-* lead workflow, which
    stays in the plugin install. valid: the name matches NAME_RE, so it is in
    the portable set."""
    entries = []
    for name in sorted(os.listdir(src_root)):
        src = os.path.join(src_root, name)
        if name.startswith(".") or lead_workflow(name) or not os.path.isdir(src) or os.path.islink(src):
            continue
        entries.append((name, bool(NAME_RE.match(name))))
    return entries


def replace_file_at(dir_fd, name, text):
    """Write <name> in the directory open at dir_fd through a temporary sibling
    created O_CREAT|O_EXCL|O_NOFOLLOW under a random name, then renamed over
    it, both relative to dir_fd: a symlink planted at a temporary name can't
    exist (the name is unknown in advance, and an existing entry fails the
    exclusive create), and one at <name> is replaced, never written through.
    Raises OSError."""
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | NOFOLLOW | CLOEXEC
    for _ in range(8):
        tmp = TMP_PREFIX + "file-" + secrets.token_hex(8)
        try:
            fd = os.open(tmp, flags, 0o666, dir_fd=dir_fd)
        except FileExistsError:
            continue
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(text)
            os.rename(tmp, name, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
        except OSError:
            try:
                os.unlink(tmp, dir_fd=dir_fd)
            except OSError:
                pass
            raise
        return
    raise OSError(errno.EEXIST, "no free temporary name")


def make_tmp_dir(dir_fd, prefix):
    """A new directory (0700) under a random name in dir_fd; its name."""
    for _ in range(8):
        name = prefix + secrets.token_hex(8)
        try:
            os.mkdir(name, 0o700, dir_fd=dir_fd)
        except FileExistsError:
            continue
        return name
    raise OSError(errno.EEXIST, "no free temporary name")


def copy_into_place(src, dest_fd, name, replace):
    """Copy src to <name> in the directory open at dest_fd through a temporary
    sibling renamed into place: a copy interrupted half-way (the hook's
    timeout, a crash) would otherwise leave a partial directory that no
    recorded digest matches, and the next refresh would keep it as the user's.
    The sibling is made under a random name, so no link can be planted at it
    in advance, and every step is relative to dest_fd. replace (sync): digest
    the copy and remove the directory already at <name> first, and return the
    digest; without it (add) the name must be free, and None is returned. A
    failure removes the temporary copy and raises OSError."""
    tmp = ""
    try:
        tmp = make_tmp_dir(dest_fd, TMP_PREFIX + name + "-")
        tfd = open_dir(tmp, dest_fd)
        try:
            copytree_at(src, tfd)
            os.chmod(tfd, stat.S_IMODE(os.stat(src).st_mode))
            digest = digest_fd(tfd) if replace else None
        finally:
            os.close(tfd)
        if replace and lstat_at(dest_fd, name) is not None:
            rmtree_at(dest_fd, name)
        os.rename(tmp, name, src_dir_fd=dest_fd, dst_dir_fd=dest_fd)
        return digest
    except OSError:
        try:
            if tmp and lstat_at(dest_fd, tmp) is not None:
                rmtree_at(dest_fd, tmp)
        except OSError:
            pass
        raise


def add(plugin_root, project, dest_rel, skip, prefix):
    """Write each portable skill missing from <project>/<dest_rel> (add-only)."""
    out = []

    def note(msg):
        out.append(prefix + msg)

    src_root = os.path.join(plugin_root, "skills")
    parts = [p for p in dest_rel.split("/") if p]
    if not os.path.isdir(src_root) or not parts or any(p in (".", "..") for p in parts):
        return out
    # down from the project directory by descriptors (B2): each component
    # opened without following a link, created when absent
    try:
        fds = [os.open(os.path.realpath(project), DIR_FLAGS)]
    except OSError:
        note("WARNING could not open the project directory — skills not added to " + dest_rel + ".")
        return out
    try:
        for i, p in enumerate(parts):
            shown = "/".join(parts[:i + 1])
            st = lstat_at(fds[-1], p)
            if st is not None and stat.S_ISLNK(st.st_mode):
                note(dest_rel + ": " + shown + " is a symlink — left untouched (skills not added).")
                return out
            if st is not None and not stat.S_ISDIR(st.st_mode):
                note(dest_rel + ": " + shown + " exists and is not a directory — skills not added.")
                return out
            try:
                if st is None:
                    try:
                        os.mkdir(p, 0o777, dir_fd=fds[-1])
                    except FileExistsError:
                        pass
                fds.append(open_dir(p, fds[-1]))
            except OSError:
                # a failed create, or a link or a file swapped in after the check
                note("WARNING could not create " + dest_rel + " — skills not added.")
                return out
        dest_fd = fds[-1]
        added, present, failed = [], [], []
        for name, valid in shipped_entries(src_root):
            if not valid:
                continue
            if name in skip or lstat_at(dest_fd, name) is not None:
                present.append(name)
                continue
            try:
                copy_into_place(os.path.join(src_root, name), dest_fd, name, False)
                added.append(name)
            except OSError:
                failed.append(name)
    finally:
        for fd in fds:
            os.close(fd)
    if failed:
        note("WARNING " + dest_rel + ": could not add " + " ".join(failed) + ".")
    if present:
        note(dest_rel + ": left as they are (already present or tracked there): " + " ".join(present) + ".")
    return out


def table(repo, tag_glob):
    tags = subprocess.run(["git", "-C", repo, "tag", "-l", tag_glob], check=True,
                          capture_output=True, text=True).stdout.split()
    rows = {}
    for tag in sorted(tags):
        listing = subprocess.run(["git", "-C", repo, "ls-tree", "-r", "-z", tag, "--", "skills/"],
                                 check=True, capture_output=True).stdout
        per_skill = {}
        for item in listing.split(b"\0"):
            if not item:
                continue
            meta, path = item.split(b"\t", 1)
            mode, kind, sha = meta.split()
            parts = path.decode("utf-8", "surrogateescape").split("/")
            if len(parts) < 3 or kind != b"blob":
                continue
            name, rel = parts[1], "/".join(parts[2:])
            if rel.rsplit("/", 1)[-1] in IGNORED_FILES or lead_workflow(name) or name.startswith("."):
                continue
            blob = subprocess.run(["git", "-C", repo, "cat-file", "blob", sha.decode()], check=True,
                                  capture_output=True).stdout
            if mode == b"120000":
                entry = ("L", rel, blob.decode("utf-8", "surrogateescape"))
            else:
                entry = ("F", rel, hashlib.sha256(blob).hexdigest())
            per_skill.setdefault(name, []).append(entry)
        for name, entries in per_skill.items():
            h = hashlib.sha256()
            for kind, rel, value in sorted(entries):
                h.update(_entry_line(kind, rel, value))
            rows.setdefault((name, h.hexdigest()), []).append(tag)
    print("# scripts/lib/skill-digests.txt — digests of every released copy of each shipped skill")
    print("# (KTD12). Generated by: python3 scripts/lib/skills-sync.py table --repo . --tags '" + tag_glob + "'")
    print("# Read by skills-sync.py to migrate a legacy 3.3.0-3.3.2 stamp (names only, no digests): a")
    print("# stamp-listed directory is Triforge-owned only when its digest is listed here for its name.")
    print("# Stamps from 3.3.3 on record their own digests, so this table only needs the releases that")
    print("# wrote the legacy format. Columns: <skill> TAB <sha256> TAB <tags carrying that content>.")
    for (name, digest) in sorted(rows):
        print(name + "\t" + digest + "\t" + ",".join(rows[(name, digest)]))


def main(argv):
    if len(argv) >= 2 and argv[1] == "digest" and len(argv) == 3:
        print(dir_digest(argv[2]))
        return 0
    if len(argv) >= 2 and argv[1] in ("sync", "add", "table"):
        opts = {}
        i = 2
        while i < len(argv):
            if argv[i] in ("--plugin-root", "--project", "--prefix", "--repo", "--tags", "--dest", "--skip") and i + 1 < len(argv):
                opts[argv[i]] = argv[i + 1]
                i += 2
            else:
                sys.stderr.write("skills-sync.py: unknown argument " + argv[i] + "\n")
                return 2
        if argv[1] == "add":
            if "--plugin-root" not in opts or "--project" not in opts or "--dest" not in opts:
                sys.stderr.write("skills-sync.py add: --plugin-root, --project and --dest are required\n")
                return 2
            skip = set(n for n in opts.get("--skip", "").split(",") if n)
            for line in add(opts["--plugin-root"], opts["--project"], opts["--dest"], skip, opts.get("--prefix", "")):
                print(line)
            return 0
        if argv[1] == "sync":
            if "--plugin-root" not in opts or "--project" not in opts:
                sys.stderr.write("skills-sync.py sync: --plugin-root and --project are required\n")
                return 2
            for line in sync(opts["--plugin-root"], opts["--project"], opts.get("--prefix", "")):
                print(line)
            return 0
        table(opts.get("--repo", "."), opts.get("--tags", "v3.*"))
        return 0
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
