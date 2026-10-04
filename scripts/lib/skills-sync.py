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

Safety: a symlinked .agents or .agents/skills, or one that resolves outside the
project, is left untouched; every name must match ^[a-z0-9][a-z0-9-]*$, and
every existing entry must be a plain directory directly inside .agents/skills.
Copies preserve symlinks as links (never followed). The stamp is written last,
tmp + rename, and only when every copy succeeded.

Lead workflows (KTD12, R16): a shipped skills/at-* directory is a lead workflow
that reaches a lead only from its plugin install. It is never copied into
.agents/skills or a worktree, never listed in the stamp, and an at-* directory
already present there is never replaced or retired, whatever a stamp says —
for refresh purposes the at- prefix means "not Triforge-shipped". A dot entry
under skills/ (skills/.devin-plugin/, the Devin manifest) is packaging, not a
skill: never copied, digested or reported.

Usage:
    skills-sync.py sync --plugin-root <dir> --project <dir> [--prefix <text>]
    skills-sync.py digest <dir>
    skills-sync.py table --repo <git checkout> [--tags <glob>]

`sync` prints one notice per line (each starting with --prefix) and always
exits 0 for a refusal or partial refresh; 2 is a usage error.
"""

import errno
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

STAMP_NAME = ".triforge-plugin-version"
STAMP_FORMAT = "2"
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
IGNORED_FILES = (".DS_Store",)
TMP_PREFIX = ".triforge-tmp-"   # copies in flight; never a valid skill name (NAME_RE), cleaned up on the next run
LEAD_PREFIX = "at-"              # lead workflows: never copied, never owned, never retired (KTD12)


def lead_workflow(name):
    return name.startswith(LEAD_PREFIX)


def _entry_line(kind, rel, value):
    return (kind + "\0" + rel + "\0" + value + "\n").encode("utf-8", "surrogateescape")


def _walk_error(err):
    # A directory that can't be listed would otherwise be skipped silently, and a
    # tree holding one would still digest as Triforge's own copy: raise, so
    # safe_digest reports the directory instead of owning it.
    raise err


def dir_digest(path):
    """sha256 over the sorted (kind, relative path, content hash | link target)
    entries of a directory tree. Empty directories and .DS_Store don't count,
    so the digest matches what git would record. Anything that is not a
    regular file, a symlink or a directory (a FIFO, a socket, a device — which
    git can't carry, so it is never Triforge's) makes the tree unreadable:
    opening a FIFO would block the refresh."""
    entries = []
    for root, dirs, files in os.walk(path, followlinks=False, onerror=_walk_error):
        dirs.sort()
        for d in dirs:
            full = os.path.join(root, d)
            if os.path.islink(full):
                rel = os.path.relpath(full, path).replace(os.sep, "/")
                entries.append(("L", rel, os.readlink(full)))
        for f in files:
            if f in IGNORED_FILES:
                continue
            full = os.path.join(root, f)
            rel = os.path.relpath(full, path).replace(os.sep, "/")
            if os.path.islink(full):
                entries.append(("L", rel, os.readlink(full)))
            elif not os.path.isfile(full):
                raise OSError(errno.EINVAL, "not a regular file", full)
            else:
                with open(full, "rb") as fh:
                    entries.append(("F", rel, hashlib.sha256(fh.read()).hexdigest()))
    h = hashlib.sha256()
    for kind, rel, value in sorted(entries):
        h.update(_entry_line(kind, rel, value))
    return h.hexdigest()


def safe_digest(path):
    """dir_digest, or None when a file in the tree can't be read: that one
    directory is left alone and reported, and the rest of the refresh goes on."""
    try:
        return dir_digest(path)
    except OSError:
        return None


def read_stamp(path):
    stamp = {"version": "", "format": "", "skills": [], "digests": {}}
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return None
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


def plain_dir_inside(path, parent_real):
    return (not os.path.islink(path)) and os.path.isdir(path) \
        and os.path.dirname(os.path.realpath(path)) == parent_real


def sync(plugin_root, project, prefix):
    out = []

    def note(msg):
        out.append(prefix + msg)

    src_root = os.path.join(plugin_root, "skills")
    if not os.path.isdir(src_root):
        return out
    version = plugin_version(plugin_root)
    table = read_table(os.path.join(plugin_root, "scripts", "lib", "skill-digests.txt"))
    agents = os.path.join(project, ".agents")
    dest = os.path.join(agents, "skills")
    if os.path.islink(agents) or os.path.islink(dest):
        note(".agents or .agents/skills is a symlink — left untouched (Triforge refreshes only a real directory inside the project; remove the link to let it manage the copy).")
        return out
    if os.path.lexists(agents) and not os.path.isdir(agents):
        note(".agents exists and is not a directory — skills not refreshed.")
        return out
    expected = os.path.join(os.path.realpath(project), ".agents", "skills")
    if os.path.lexists(dest) and os.path.realpath(dest) != expected:
        note(".agents/skills resolves outside the project (symlinked ancestor) — left untouched.")
        return out

    stamp_path = os.path.join(dest, STAMP_NAME)
    stamp = read_stamp(stamp_path) if os.path.isfile(stamp_path) and not os.path.islink(stamp_path) else None
    if os.path.isdir(dest) and stamp and version and stamp["version"] == version and stamp["format"] == STAMP_FORMAT:
        return out    # current: no copies, no notice
    if os.path.isdir(dest) and not version:
        return out    # plugin version unreadable: keep what is deployed rather than refresh blind
    try:
        os.makedirs(dest, exist_ok=True)
    except OSError:
        note("WARNING could not create .agents/skills — skills not refreshed (session continues).")
        return out
    dest_real = os.path.realpath(dest)
    if dest_real != expected:
        note(".agents/skills resolves outside the project (symlinked ancestor) — left untouched.")
        return out

    def owned(name, digest):
        if stamp is None or lead_workflow(name):
            return False
        if stamp["format"] == STAMP_FORMAT:
            return stamp["digests"].get(name) == digest
        return name in stamp["skills"] and digest in table.get(name, ())

    shipped = []
    written = {}
    kept, skipped, retired, failed = [], [], [], False
    for leftover in os.listdir(dest):
        # a copy an earlier run did not finish
        if leftover.startswith(TMP_PREFIX) and not os.path.islink(os.path.join(dest, leftover)):
            shutil.rmtree(os.path.join(dest, leftover), ignore_errors=True)
    for name in sorted(os.listdir(src_root)):
        src = os.path.join(src_root, name)
        if name.startswith("."):
            continue    # packaging, not a skill: skills/.devin-plugin/ is the Devin manifest
        if lead_workflow(name) or not os.path.isdir(src) or os.path.islink(src):
            continue    # a lead workflow (at-*) stays in the plugin install
        if not NAME_RE.match(name):
            skipped.append(name + "(invalid-name)")
            continue
        shipped.append(name)
        target = os.path.join(dest, name)
        if os.path.lexists(target):
            if not plain_dir_inside(target, dest_real):
                skipped.append(name + "(not-a-plain-directory)")
                continue
            current, shipped_digest = safe_digest(target), safe_digest(src)
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
        # Copy into a temporary sibling first and rename it into place: a copy
        # interrupted half-way (the hook's timeout, a crash) would otherwise
        # leave a partial directory that no recorded digest matches, and the
        # next refresh would keep it as the user's.
        tmp_dir = os.path.join(dest, TMP_PREFIX + name + "-" + str(os.getpid()))
        try:
            if os.path.lexists(tmp_dir):
                shutil.rmtree(tmp_dir)
            shutil.copytree(src, tmp_dir, symlinks=True)
            digest = dir_digest(tmp_dir)
            if os.path.lexists(target):
                shutil.rmtree(target)
            os.rename(tmp_dir, target)
            written[name] = digest
        except (OSError, shutil.Error):
            failed = True
            skipped.append(name + ("(replace-failed)" if os.path.lexists(target) else "(copy-failed)"))
            try:
                if os.path.lexists(tmp_dir):
                    shutil.rmtree(tmp_dir)
            except OSError:
                pass

    previous = []
    if stamp:
        previous = sorted(set(stamp["skills"]) | set(stamp["digests"]))
    retired_kept = []
    for name in previous:
        if name in shipped or not NAME_RE.match(name) or lead_workflow(name):
            continue    # an at-* entry in a stamp never makes an at-* directory Triforge's to retire
        target = os.path.join(dest, name)
        if not os.path.lexists(target):
            continue
        digest = safe_digest(target) if plain_dir_inside(target, dest_real) else None
        if digest is not None and owned(name, digest):
            try:
                shutil.rmtree(target)
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
        tmp = stamp_path + ".tmp." + str(os.getpid())
        try:
            with open(tmp, "w", encoding="utf-8") as fh:
                fh.write("\n".join(body) + "\n")
            os.replace(tmp, stamp_path)
            note(".agents/skills refreshed to " + (version or "?") + " (Triforge replaces only its own unchanged copies, identified by content digest; keep customizations in a differently named directory; lead workflows (at-*) are not copied)"
                 + ("; retired no-longer-shipped: " + " ".join(retired) if retired else "") + ".")
        except OSError:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            note("WARNING .agents/skills refreshed but the version stamp could not be written — the refresh re-runs next session.")
    if kept:
        note(".agents/skills kept as user-owned (content differs from Triforge's copy, so it was not replaced; the shipped version of each is not installed there): " + " ".join(kept) + ".")
    if retired_kept:
        note(".agents/skills kept as user-owned (no longer shipped, but changed since Triforge wrote it): " + " ".join(retired_kept) + ".")
    if skipped:
        note(".agents/skills entries left untouched (symlink, not a plain directory directly inside .agents/skills, unreadable, or invalid name): " + " ".join(skipped) + ".")
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
    if len(argv) >= 2 and argv[1] in ("sync", "table"):
        opts = {}
        i = 2
        while i < len(argv):
            if argv[i] in ("--plugin-root", "--project", "--prefix", "--repo", "--tags") and i + 1 < len(argv):
                opts[argv[i]] = argv[i + 1]
                i += 2
            else:
                sys.stderr.write("skills-sync.py: unknown argument " + argv[i] + "\n")
                return 2
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
