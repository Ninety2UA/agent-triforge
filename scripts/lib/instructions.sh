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
#     directory or above it; the user tier does not count: CLAUDE.md in
#     Claude Code's config home, $CLAUDE_CONFIG_DIR when that is an absolute
#     path outside the project, ~/.claude when it is unset, and none when it
#     is empty, relative or in the project (tier_home), so a project file is
#     never taken for the user's. Once the config home moves, Claude Code
#     2.1.296 loads ~/.claude/CLAUDE.md as a project file at HOME, and so it
#     is a file above the project here too.
#     A CLAUDE.md-family file that imports AGENTS.md (an `@AGENTS.md` token,
#     its path relative to the file holding it) loads it with the file. The
#     token counts only in Markdown text, where Claude Code reads imports:
#     never in a code block (fenced or indented), a code span, HTML (bar the
#     rest of the line after a comment that opens an HTML block, which Claude
#     Code reads), a link destination or title or front matter (md_scan,
#     which reads the blocks as marked does and counts what it cannot place
#     as no import). Claude Code takes the whole token up to a # as
#     the path (@AGENTS.md. names AGENTS.md.), and a path it does not read
#     whole is none (path_ok, emphasis). An import line is written or
#     offered only when this reader reads it back as the project's import
#     (reads_back): a token ends at whitespace (no escaped form is written or
#     read here), a path that starts with ~/ is read from HOME, and a #, a
#     backslash, <, [, ], a * or _ that may pair, or a first character
#     other than a letter, a digit, . _ or - keeps it from being read whole,
#     so a directory named that way, or named ~, between that file and the
#     project leaves no import line there; a CLAUDE.md in the project
#     holding `@AGENTS.md`, no path, is the fix. The writer also reads back
#     the whole file with the line appended, and refuses a file that ends
#     inside a code block, an HTML block or another place no import is
#     read, naming it.
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
# under HOME and the one in $<home_env> that tier_home takes, the user-level
# file and its override in the reader home) are
# read, never written: each writer refuses one, or any file in the directory
# of one, before any plan and also with --yes (rc 2), by identity, or by the
# physical path for a file that does not exist yet. HOME and every directory
# above it are refused the same way (home_why: same_file against the physical
# HOME and its ancestors, as _tb_home_anchor in bootstrap.sh compares), since
# an instruction file there is read for every project under it; HOME unset or
# not a directory protects nothing. Run from HOME or above it, which is no
# project, the refusal says to start in a project directory.
#
# Return codes: 0 ok · 1 hidden or an unknown reader
# (instruction_pointer_visibility) · 2 refused input, an import line that
# would not read back as the project's import included
# (instruction_add_import) · 3 over the AGENTS.md byte budget
# (instruction_merge_pointer and the merge in
# instruction_convert_stale) · 20 needs-ask · 45 lead-only refusal · 64 usage ·
# 69 unavailable (no python3, no template, no private temp dir for the
# watchdog) · 80 degraded (a write failed, or the target changed while it was
# planned) · 124, 137 or 143 a read-only run given up on (_instr_py: 30 s
# unless the caller sets _INSTR_SECS; a writer with --yes is never bounded).

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
import array, bisect, hashlib, mmap, os, re, stat, sys

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
# an import: a whitespace-separated word @AGENTS.md or @<path>/AGENTS.md in
# the Markdown text md_scan finds. Claude Code takes the whole word up to a #
# as the path, so only a #fragment may follow the name: the word @AGENTS.md.
# names the file AGENTS.md., the word @AGENTS.md) (as in "see @AGENTS.md)")
# names AGENTS.md), and @AGENTS.md.bak another file. path_ok and emphasis
# hold the <path> part to what Claude Code reads whole
IMPORT = re.compile(rb"@((?:\S*/)?)AGENTS\.md(?:#\S*)?")
WORD = re.compile(rb"\S*")


class Found(bytes):
    # an import md_scan found: its word, which group() gives, with its
    # <path> part as group(1), as an IMPORT match does. One object per word
    # (found_word), so a file of many imports holds each word once
    __slots__ = ()

    def group(self, i=0):
        return self if i == 0 else IMPORT.fullmatch(self).group(1)


FOUND = {}


def found_word(m):
    # the Found for an IMPORT match
    w = m.group()
    f = FOUND.get(w)
    if f is None:
        f = FOUND[w] = Found(w)
    return f
START = b"<!-- triforge:start -->"
END = b"<!-- triforge:end -->"
# Claude Code (its memory loader, read in the 2.1.294 build) reads an import
# from Markdown text alone: it skips a file over MD_MAX bytes, drops a BOM
# with the front matter block it starts (FRONT, its own pattern, \s as in
# JavaScript), lexes the rest with marked 15.0.12 (GFM off) and scans the
# text tokens, so an import in a code block (fenced or indented), a code
# span, HTML, a link destination or title, an image description or a link
# reference definition loads nothing, nor does a word that an earlier path
# takes in (joined). md_scan reads a file the same way. Its block side is
# marked itself: MdLexer is Lexer.blockTokens and the block tokenizers it
# calls, line for line (their quirks included: the lazy lines of a quote
# lexed as blocks of their own, the list item that ends after its first
# line, a tag name that ends its line, a label or title over lines), on the
# text as the UTF-16 code units marked counts (js_text). Its patterns are
# marked block rules (MK_*) with the JavaScript \s (JS_SPACE), dot (JS_DOT,
# no line terminator), $ (\Z) and multiline ^ (JS_BOL); lheading answers
# from a table of the lines that end its scan, so no rule rescans a line.
# Work, steps and nesting are bounded, and a file past a bound counts no
# import (md_scan says where). The inline side keeps to what is text for
# certain (text_words): what it cannot place counts as not text, so its
# error is "hidden, offer the fix", never an import reported that is not
# loaded. Its patterns: TITLE the quotes of a link title, INLINE the
# inline HTML, email autolink (its local part and @, where no other opening
# matches) and link destination openings, closed by CLOSE, a complete TAG or
# the rest of a link (link_ends): \s* (WS, the JavaScript \s in UTF-8),
# the destination <...> (ANGLE, whose backslash takes no line end) or a run
# of all but space, tab, newline and controls (RUN, cut at a parenthesis
# PAREN finds unbalanced), a title after [ \t]* and at most one newline
# (SEP), \s* and ")"
MD_MAX = 4194304
# what Triforge reads of an AGENTS.md or AGENTS.override.md, the reader
# config and the pointer block template (load): their first FILE_MAX + 1
# bytes at most, which hold all it looks for in any it writes or reads
# whole (the pointer block, a budget key or trust entry); a longer file
# counts at its full size in a budget, and no writer writes it (it was not
# read whole), nor is anything past FILE_MAX in it known
FILE_MAX = MD_MAX
JS_SPACE = r"[\t\n\x0b\x0c\r \u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]"
# the front matter pattern of Claude Code, ---\s*\n[\s\S]*?---\s*\n?, with
# its first \s*\n taken once in a lookahead (no search re-enters one): a
# shorter run gains nothing, as no --- starts in it, and retrying each one is
# quadratic in a long run
FRONT = re.compile(r"---(?=(" + JS_SPACE + r"*\n))\1[\s\S]*?---" + JS_SPACE + r"*\n?")
JS_TRIM = "\t\n\x0b\x0c\r \xa0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeff"
JS_WS = "\t\n\x0b\x0c\r \xa0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff"
JS_DOT = "[^\n\r\u2028\u2029]"
JS_BOL = "(?:\\A|(?<=[\n\r\u2028\u2029]))"
ASTRAL = re.compile("[\U00010000-\U0010ffff]")
SURROGATE = re.compile("[\ud800-\udfff]")
MK_TAGS = "address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h[1-6]|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|meta|nav|noframes|ol|optgroup|option|p|param|search|section|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul"
# The regex engine keeps a frame, a few hundred bytes, for every pass of a
# repeated group (one character repeated keeps none), and macOS keeps those
# pages resident from one match to the next: marked rules such as its
# paragraph, (?:\n(?!...)[^\n]+)*, matched over 4 MiB took GBs. So each
# repeated group that can run long is bounded at REP passes, matched again
# from where it stopped while it moves (runs), or read off a run of one
# character (blank_end); a rule that backtracks into such a group is
# followed step by step in code (quote_end, html_end, def_end), each the
# same match as the marked rule it names
REP = "{0,1024}"
# a thematic break: three of its character, then any more of it, spaces and
# tabs, which are the lines (?:-[\t ]*){3,} matches
MK_HR_SRC = " {0,3}(-[\t ]*-[\t ]*-[-\t ]*|_[ \t]*_[ \t]*_[_ \t]*|\\*[ \t]*\\*[ \t]*\\*[* \t]*)(?:\n+|\\Z)"
# the lines that end a paragraph (marked paragraph, its (?!...)). The fence
# that interrupts one is ~{3,}[^\n]*\n in marked: ~{3} and [^\n]*\n match the
# same lines, and in a lookahead only whether one does counts, while ~{3,}
# retries every shorter run on a last line of ~ with no newline, which is
# quadratic in it
MK_INTERRUPT = (MK_HR_SRC + "| {0,3}#{1,6}(?:" + JS_SPACE + "|\\Z)| {0,3}>| {0,3}(?:`{3,}(?=[^`\n]*\n)|~{3})[^\n]*\n"
                "| {0,3}(?:[*+-]|1[.)]) |</?(?:" + MK_TAGS + ")(?: +|\n|/?>)|<(?:script|pre|style|textarea|!--)| +\n")
# the lines of a paragraph after its first ([^\n]+), REP of them
MK_PARA_MORE = re.compile("(?:\n(?!" + MK_INTERRUPT + ")[^\n]+)" + REP)
MK_BLANKS = re.compile("[ \t\n]*")
MK_NEWLINES = re.compile("\n+")
# lines of indented code, each with the blank lines after it, REP of each
MK_CODE_RUN = re.compile("(?:(?: {4}| {0,3}\t)[^\n]+(?:\n(?:[ \t]*(?:\n|\\Z))" + REP + ")?)" + REP)
MK_FENCES = re.compile(" {0,3}(`{3,}(?=[^`\n]*(?:\n|\\Z))|~{3,})([^\n]*)(?:\n|\\Z)(?:|([\\s\\S]*?)(?:\n|\\Z))(?:( {0,3}\\1[~`]* *)(?=\n|\\Z)|\\Z)")
MK_HEADING = re.compile(" {0,3}(#{1,6})(?=" + JS_SPACE + "|\\Z)(" + JS_DOT + "*)(?:\n+|\\Z)")
MK_HR = re.compile(MK_HR_SRC)
# the lines of a quote, REP of them: a > line whose text after "> ?" is not
# empty with the paragraph lines after it (REP of them), or an empty one
MK_QUOTE_RUN = re.compile("(?: {0,3}>(?: [^\n]|[^ \n])[^\n]*(?:\n(?!" + MK_INTERRUPT + ")[^\n]+)" + REP + "(?:\n|\\Z)| {0,3}> ?(?:\n|\\Z))" + REP)
MK_QUOTE_OPEN = re.compile(" {0,3}> ?")
MK_LIST = re.compile("( {0,3}(?:[*+-]|[0-9]{1,9}[.)]))(?:[ \t][^\n]+?)?(?:\n|\\Z)")
# the HTML block rule of marked, by its kinds (html_end): type 1 (script,
# pre, style, textarea), the comment, processing instruction, declaration
# and CDATA kinds, a block tag, any other open tag alone on its line with
# its attributes (REP of them), a closing tag alone on its line
MK_HTML_PRE = re.compile(" {0,3}<(script|pre|style|textarea)[" + JS_WS + ">]", re.I | re.A)
MK_HTML_DECL = re.compile(" {0,3}(?:<!--(?:-?>|[\\s\\S]*?(?:-->|\\Z))[^\n]*(\n+|\\Z)|<\\?[\\s\\S]*?(?:\\?>\n*|\\Z)|<![A-Z][\\s\\S]*?(?:>\n*|\\Z)"
                          "|<!\\[CDATA\\[[\\s\\S]*?(?:\\]\\]>\n*|\\Z))", re.I | re.A)
MK_HTML_BLOCK = re.compile(" {0,3}</?(?:" + MK_TAGS + ")(?: +|\n|/?>)", re.I | re.A)
MK_HTML_OPEN = re.compile(" {0,3}<(?!script|pre|style|textarea)[a-z][\\w-]*", re.I | re.A)
MK_HTML_ATTRS = re.compile("(?: +[a-zA-Z:_][\\w.:-]*(?: *= *\"[^\"\n]*\"| *= *\x27[^\x27\n]*\x27| *= *[^" + JS_WS + "\"\x27=<>`]+)?)" + REP, re.I | re.A)
MK_HTML_SHUT = re.compile(" */?>(?=[ \t]*(?:\n|\\Z))", re.I | re.A)
MK_HTML_CLOSE = re.compile(" {0,3}</(?!script|pre|style|textarea)[a-z][\\w-]*" + JS_SPACE + "*>(?=[ \t]*(?:\n|\\Z))", re.I | re.A)
MK_HTML_GAP = re.compile("\n[ \t]*\n")
# the link reference definition rule of marked, by its parts (def_end): the
# [ and the label (REP of its characters), what may follow the ]: before the
# destination, the destination, a title of each kind, the end of its line
MK_DEF_OPEN = re.compile(" {0,3}\\[(?!" + JS_SPACE + "*\\])")
MK_DEF_LABEL = re.compile("(?:\\\\" + JS_DOT + "|[^\\[\\]\\\\])" + REP)
MK_DEF_GAP = re.compile(" *(?:\n[ \t]*)?")
MK_DEF_DEST = re.compile("[^<" + JS_WS + "][^" + JS_WS + "]*")
# a > that a space, a newline or the end follows (no other can end the
# destination of a definition the rest of it matches), or a line end (one
# of the characters JS_DOT leaves out)
MK_DEF_ANGLE = re.compile(">(?=[ \n]|\\Z)|" + JS_DOT.replace("[^", "["))
MK_DEF_SEP = re.compile("( *)(?:\n[ \t]*)?")
MK_DEF_QUOTE = re.compile("(?<!\\\\)\"")
MK_DEF_PAREN = re.compile("\\([^()]*\\)")
MK_DEF_END = re.compile(" *(?:\n+|\\Z)")
MK_TEXT = re.compile("[^\n]+")
# lheading: a first line that may open none of MK_LH_OPEN, then lines up to
# the first one that is an underline (a match), opens one of them or is
# blank before a newline, or holds a line terminator other than \n (no match)
MK_LH_OPEN = "(?:[*+-]|[0-9]{1,9}[.)]) |(?: {4}| {0,3}\t)| {0,3}(?:`{3,}|~{3,})| {0,3}>| {0,3}#{1,6}| {0,3}<[^\n>]+>\n"
MK_LH_FIRST = re.compile(MK_LH_OPEN)
MK_LH_EVENT = re.compile("^(?:( {0,3}(?:=+|-+) *(?=\n|\\Z))|" + JS_SPACE + "*?\n|" + MK_LH_OPEN + "|[^\n]*[\r\u2028\u2029])", re.M)
MK_LH_UNDER = re.compile(" {0,3}(?:=+|-+) *(?:\n+|\\Z)")
MK_LH_STOP = re.compile("[\r\u2028\u2029]")
MK_CODE_INDENT = re.compile(JS_BOL + "(?: {1,4}| {0,3}\t)")
MK_QUOTE_START = re.compile(" {0,3}>")
MK_QUOTE_SETEXT = re.compile("\n {0,3}((?:=+|-+) *)(?=\n|\\Z)")
MK_QUOTE_MARK = re.compile(JS_BOL + " {0,3}>[ \t]?")
MK_BLANK = re.compile("[ \t]*\\Z")
MK_NONSPACE = re.compile("[^ ]")
MK_TABS = re.compile("^\t+")
# what Claude Code reads in an HTML block that opens with a comment: the rest
# outside its comments (uncomment), each @ at its start or after a
# JavaScript space and the path after it, (?:^|\s)@((?:[^\s\\]|\\ )+) with
# \s as in JavaScript (MK_AT: at_paths, the path REP characters at a time)
MK_AT_OPEN = re.compile("(?:^|" + JS_SPACE + ")@(?=[^" + JS_WS + "\\\\]|\\\\ )")
MK_AT_PATH = re.compile("(?:[^" + JS_WS + "\\\\]|\\\\ )" + REP)
TITLE = {b"\"": b"\"", b"\x27": b"\x27", b"(": b")"}
INLINE = re.compile(rb"<(!--|\?|!\[CDATA\[|!(?=[A-Za-z])|/?(?=[A-Za-z]))|<()(?=[A-Za-z0-9.!#$%&\x27*+/=?^_`{|}~-]+@)|\]\(")
CLOSE = {b"!--": b"-->", b"?": b"?>", b"![CDATA[": b"]]>", b"!": b">", b"@": b">"}
# what a link label is read over (labels): its brackets, backslashes and
# backticks
LABEL_AT = re.compile(rb"[\[\]\\`]")
INLINE_ANY = re.compile(rb"[\[\]<`*_]")
TICKS = re.compile(rb"`+")
# TAG, WS and ANGLE, each a repeated group, REP passes at a time (tag_end,
# ws_end, angle_end): an HTML tag, </?[A-Za-z][\w:-]* and its attributes
# (?:\s+[A-Za-z:_][\w.:-]*(?:\s*=\s*(?:"[^"]*"|\x27[^\x27]*\x27|[^\s"\x27=<>`]+))?)*?
# then \s*/?>; the JavaScript \s in UTF-8; the characters of <...>
TAG = re.compile(rb"</?[A-Za-z][\w:-]*")
TAG_ATTRS = re.compile(rb"(?:\s+[A-Za-z:_][\w.:-]*(?:\s*=\s*(?:\"[^\"]*\"|\x27[^\x27]*\x27|[^\s\"\x27=<>`]+))?)" + REP.encode())
TAG_SHUT = re.compile(rb"\s*/?>")
WS = re.compile(rb"(?:[\t\n\x0b\x0c\r ]|\xc2\xa0|\xe1\x9a\x80|\xe2\x80[\x80-\x8a\xa8\xa9\xaf]|\xe2\x81\x9f|\xe3\x80\x80|\xef\xbb\xbf)" + REP.encode())
ANGLE = re.compile(rb"(?:\\(?!\xe2\x80[\xa8\xa9])[^\n\r]|[^\n<>\\])" + REP.encode())
RUN = re.compile(rb"[^ \t\n\x00-\x1f]*")
SEP = re.compile(rb"[ \t]*(?:\n[ \t]*)?")
PAREN = re.compile(rb"(?<!\\)(\\*)([()])")
# the <path> part of an import (path_ok): Claude Code ends the path at a #,
# a backslash or a JavaScript space, and marked may read a <, [ or ] in it as
# HTML or a link (PATH_CUT); it keeps a path only when it starts with ./, ~/,
# / or one of A-Z a-z 0-9 . _ - (PATH_HEAD), and drops a special absolute
# one (sP in its build: // or ?? at the start, a first directory net or
# network, the macOS /.vol, /.file, /.nofollow, /.resolve; PATH_ROOTS is
# wider), its first directory compared without zero-width characters
PATH_CUT = re.compile(rb"[#\\<\[\]]|\xc2\xa0|\xe1\x9a\x80|\xe2\x80[\x80-\x8a\xa8\xa9\xaf]|\xe2\x81\x9f|\xe3\x80\x80|\xef\xbb\xbf")
PATH_HEAD = re.compile(rb"~/|/|[A-Za-z0-9._-]")
PATH_ROOTS = (b"net", b"network", b"system", b".vol", b".file", b".nofollow", b".resolve")
ZERO_WIDTH = re.compile(rb"\xe2\x80[\x8c-\x8f\xaa-\xae]|\xe2\x81[\xaa-\xaf]|\xef\xbb\xbf")
ALNUM = re.compile(rb"[A-Za-z0-9]")
SPACE = (b"", b" ", b"\t", b"\n", b"\r", b"\x0b", b"\x0c")
# where a path may start (joined): marked may begin a text token after the
# last character of a code span, an HTML tag, a link or emphasis, after the
# [ of a link label and the * or _ that opens emphasis (TOKEN_EDGE), and
# after an escape, a backslash and one of PUNCT
TOKEN_EDGE = b"`>)][*_"
PUNCT = re.compile(rb"[!-/:-@\[-`{-~]")
# The instruction readers a lead can run, named by its registry field
# "instructions" (KTD1). Data only, keyed by reader, never by CLI:
#   shadow       the files at the cwd or above (up to /) that hide AGENTS.md
#                unless one of them imports it
#   user_tier    the file of that family in the reader home (tier_home):
#                always loaded, never a shadow, its imports count
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
        "shadow": CLAUDE_KINDS, "user_tier": "CLAUDE.md",
        "home_env": "CLAUDE_CONFIG_DIR", "home_default": ".claude", "user_level": "", "override": "", "root_marker": "",
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


def tier_home(r, project):
    # the directory the reader takes its user tier from: $<home_env> as set
    # when it is an absolute path that is neither project nor below it,
    # HOME/<home_default> when it is unset, else "" (no user tier). Claude
    # Code 2.1.296 reads CLAUDE.md from $CLAUDE_CONFIG_DIR in place of
    # ~/.claude when the variable is set; an empty or relative value names a
    # directory relative to where it started, and one in the project makes a
    # project file its user memory, so neither counts: the files there stay
    # project files (shadows the writers may plan for), and no user tier
    # import counts
    if r["home_env"] not in os.environ:
        return os.path.join(home(), r["home_default"]) if r["home_default"] and home() else ""
    h = os.environ[r["home_env"]]
    p = os.path.realpath(h) if h.startswith("/") else ""
    return h if p and p != project and not p.startswith(project.rstrip("/") + "/") else ""


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


def load(p, cap=FILE_MAX):
    # (bytes, size) of the regular file at p: no more than its first cap + 1
    # bytes, so a huge file is never read whole, and its length: those bytes
    # when they are all of it, else the fstat size of the descriptor read
    # (the file opened, not one put there meanwhile), past cap; (None, 0)
    # when unreadable. read_regular reads to the end, so its checks are made
    # here the same way: O_NONBLOCK (a FIFO never stalls), a regular file
    try:
        fd = os.open(p, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0))
        with os.fdopen(fd, "rb") as f:
            st = os.fstat(f.fileno())
            if not stat.S_ISREG(st.st_mode):
                return None, 0
            data = f.read(cap + 1)
            return data, len(data) if len(data) <= cap else max(st.st_size, len(data))
    except (OSError, ValueError):
        return None, 0


def readable(p):
    # True when p is a regular file load can read, none of it read
    return load(p, 0)[0] is not None


def load_md(p):
    # a CLAUDE.md-family file as md_scan needs it: no more than its first
    # MD_MAX + 1 bytes, which already tell a file over MD_MAX (no import is
    # read from it, and add_import refuses it before any write); None when
    # unreadable. The 3.x fingerprint reads the same bytes: no file over
    # MD_MAX is an exact copy (exact_3x), and is_3x looks for the template
    # lines in the first MD_MAX + 1 bytes
    return load(p, MD_MAX)[0]


def level_file(r, level, name="AGENTS.md"):
    # (path, bytes, size) of the one file the reader takes from a directory
    # (load): its override over <name>
    for n in ([r["override"]] if r["override"] else []) + [name]:
        p = os.path.join(level, n)
        d, size = load(p) if level and lexists(p) else (None, 0)
        if d is not None:
            return p, d, size
    return None, None, 0


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


def md_body(data):
    # (prefix, body): what Claude Code drops from a file before it lexes it
    # for imports (a BOM with the front matter block after it; without one
    # the BOM stays, where it keeps the first line from opening a block),
    # and the rest with each \r\n and \r read as \n, as marked reads it
    bom = 3 if data.startswith(b"\xef\xbb\xbf") else 0
    m = None
    if data.startswith(b"---", bom):
        # only then may FRONT match, so only then is data decoded for it
        text = data[bom:].decode("utf-8", "surrogateescape")
        m = FRONT.match(text)
    cut = bom + len(text[:m.end()].encode("utf-8", "surrogateescape")) if m else 0
    return data[:cut], data[cut:].replace(b"\r\n", b"\n").replace(b"\r", b"\n")


def js_text(body):
    # body as the JavaScript string marked lexes: UTF-16 code units (a
    # character past U+FFFF as its two surrogates, an invalid byte as
    # U+FFFD), so every offset and length is the one marked computes. The
    # characters past U+FFFF are replaced 65536 characters at a time, so
    # their pieces stay few
    text = body.decode("utf-8", "replace")
    if not ASTRAL.search(text):
        return text
    return "".join(ASTRAL.sub(lambda m: chr(0xd7c0 + (ord(m.group()) >> 10)) + chr(0xdc00 + (ord(m.group()) & 0x3ff)), text[i:i + 65536]) for i in range(0, len(text), 65536))


def js_bytes(text):
    # the UTF-8 bytes of a js_text string (its surrogate pairs joined): one
    # with no surrogate is the same as its own UTF-8, else 65536 code units
    # at a time, a piece never ending between the two of a pair
    if not SURROGATE.search(text):
        return text.encode("utf-8")
    out, a, n = [], 0, len(text)
    while a < n:
        b = min(n, a + 65536)
        while b < n and "\ud800" <= text[b - 1] <= "\udbff":
            b += 1
        out.append(text[a:b].encode("utf-16-le", "surrogatepass").decode("utf-16-le", "surrogatepass").encode("utf-8", "surrogatepass"))
        a = b
    return b"".join(out)


def js_search(s, rx):
    # String.prototype.search: the offset of the first match, -1 for none
    m = rx.search(s)
    return m.start() if m else -1


def ints(n, fill=0, kind="i"):
    # n numbers, each fill: ints of 4 bytes, or bytes (kind "B"). Past 65536
    # of them, an anonymous mmap viewed as such, which goes back to the
    # system once dropped: malloc on macOS keeps a large block it frees,
    # often for no later one of another size, so the arrays of one pass
    # after another would stay resident together
    if n < 65536:
        return array.array(kind, [fill]) * n
    size = n * (4 if kind == "i" else 1)
    m = mmap.mmap(-1, size)
    if fill:
        block = (array.array(kind, [fill]) * (65536 // (4 if kind == "i" else 1))).tobytes()
        for i in range(0, size, 65536):
            m[i:min(size, i + 65536)] = block[:min(65536, size - i)]
    return memoryview(m).cast(kind)


class Chunk(str):
    # parts of a string joined by grow
    __slots__ = ()


def grow(parts, *more):
    # parts, a string kept as a list of its parts, with more appended: at
    # 8192 parts, those after the chunks (Chunk) joined into one more chunk,
    # so a token or quote that grows by many small parts holds no object for
    # each, and no chunk is joined again before the end (macOS keeps each
    # larger string built of the same parts resident)
    parts.extend(more)
    if len(parts) >= 8192:
        c = 0
        while c < len(parts) and type(parts[c]) is Chunk:
            c += 1
        parts[c:] = [Chunk("".join(parts[c:]))]


def cut(parts, size, n):
    # parts, a string of size characters kept as its parts, cut to its first
    # n characters in place
    while parts and size - len(parts[-1]) >= n:
        size -= len(parts.pop())
    if size > n:
        parts[-1] = parts[-1][:len(parts[-1]) - (size - n)]


def by_lines(f, text):
    # f(text), f a substitution by rules that match within a line and never
    # at a newline (the marks of a quote, a setext line in one, the indent of
    # code), 65536 characters at a time, each piece after the first starting
    # at a newline: the same text, while sub keeps no list of all its pieces
    if len(text) <= 65536:
        return f(text)
    out, a, n = [], 0, len(text)
    while a < n:
        b = text.find("\n", a + 65536)
        b = n if b < 0 else b
        out.append(f(text[a:b]))
        a = b
    return "".join(out)


def quote_text(craw):
    # the text marked lexes for a group of quote lines
    return MK_QUOTE_MARK.sub("", MK_QUOTE_SETEXT.sub("\n    \\1", craw))


def code_text(raw):
    # the text of an indented code block
    return MK_CODE_INDENT.sub("", raw)


def runs(rx, s, p):
    # the end of rx, a repeat bounded at REP passes, matched again from where
    # it stopped while it moves: the end the unbounded repeat reaches, as
    # nothing follows it and each pass matches the same from where it starts
    while True:
        e = rx.match(s, p).end()
        if e == p:
            return p
        p = e


def blank_end(src, pos, one):
    # the end of the blank lines at pos, (?:[ \t]*(?:\n|\Z))+ (one: at least
    # one, else -1; marked newline) or * (the blank lines a line of code
    # takes): from the run of spaces, tabs and newlines there, its last
    # newline, or the end of src when the run reaches it
    q = MK_BLANKS.match(src, pos).end()
    if q == len(src):
        return q
    k = src.rfind("\n", pos, q)
    return k + 1 if k >= 0 else -1 if one else pos


def code_end(src, pos):
    # the end of marked code, (?:(?: {4}| {0,3}\t)[^\n]+(?:\n(?:[ \t]*(?:\n|\Z))*)?)+,
    # at pos, -1 for none: MK_CODE_RUN again while it moves, each run then
    # taking the blank lines its last line of code took past REP
    p = pos
    while True:
        e = MK_CODE_RUN.match(src, p).end()
        if e == p:
            return p if p > pos else -1
        p = blank_end(src, e, False)


def para_end(src, pos):
    # the end of marked paragraph, [^\n]+(?:\n(?!MK_INTERRUPT)[^\n]+)*, at
    # pos, -1 for none
    m = MK_TEXT.match(src, pos)
    return runs(MK_PARA_MORE, src, m.end()) if m else -1


def quote_end(src, pos):
    # the end of marked blockquote, (?: {0,3}> ?(?:PARAGRAPH|[^\n]*)(?:\n|\Z))+,
    # at pos, -1 for none: MK_QUOTE_RUN again while it moves. A run stops at
    # a line that is no > line, or past REP paragraph lines; the paragraph
    # goes on there when the line before is a > line whose text is not
    # empty, or one of its own lines, and this line may join it
    n, p = len(src), pos
    while True:
        e = runs(MK_QUOTE_RUN, src, p)
        if e == p:
            return p if p > pos else -1
        if e == n or src[e - 1] != "\n":
            return e
        ls = max(p, src.rfind("\n", p, e - 1) + 1)
        if MK_QUOTE_START.match(src, ls) and MK_QUOTE_OPEN.match(src, ls).end() == e - 1:
            return e
        f = runs(MK_PARA_MORE, src, e - 1)
        if f == e - 1:
            return e
        if f == n:
            return n
        p = f + 1


def html_end(src, pos):
    # the end of marked html at pos, its kinds in its order, -1 for none.
    # Type 1 ends after the line of its first closing tag that a newline
    # follows, and those newlines (marked reads </\1>[^\n]*\n+ there: tried
    # from each such tag only up to the next one on its line, the end is the
    # same), else at the end of src. A block tag, an open tag (the attributes
    # REP at a time: none fits where " */?>" does, so the end is the one the
    # lazy repeat finds) and a closing tag end at the first blank line after
    # them with the blank lines that follow ((?:\n[ \t]*)+\n), else at the end
    m = MK_HTML_PRE.match(src, pos)
    if m:
        c = re.compile("</" + m.group(1).lower() + ">", re.I | re.A).search(src, m.end())
        e = src.find("\n", c.end()) if c else -1
        return len(src) if e < 0 else MK_NEWLINES.match(src, e).end()
    m = MK_HTML_DECL.match(src, pos)
    if m:
        return m.end()
    m = MK_HTML_BLOCK.match(src, pos)
    if not m:
        m = MK_HTML_OPEN.match(src, pos)
        if m:
            m = MK_HTML_SHUT.match(src, runs(MK_HTML_ATTRS, src, m.end()))
    if not m:
        m = MK_HTML_CLOSE.match(src, pos)
    if not m:
        return -1
    g = MK_HTML_GAP.search(src, m.end())
    if not g:
        return len(src)
    return src.rfind("\n", g.start(), MK_BLANKS.match(src, g.start()).end()) + 1


def def_end(src, pos):
    # the end of marked def at pos, -1 for none, its backtracking followed:
    # the label is its longest run, the only one a ] can follow; then each
    # destination in turn (a run of characters, or <...> to each > on its
    # line), and for each a title when spaces or a newline lead to one,
    # then none: the first that the end of the line follows (MK_DEF_END)
    m = MK_DEF_OPEN.match(src, pos)
    if not m:
        return -1
    b = runs(MK_DEF_LABEL, src, m.end())
    if b == m.end() or not src.startswith("]:", b):
        return -1
    for d in def_dests(src, MK_DEF_GAP.match(src, b + 2).end()):
        s = MK_DEF_SEP.match(src, d).end()
        if s > d:
            for t in def_titles(src, s):
                e = MK_DEF_END.match(src, t)
                if e:
                    return e.end()
        e = MK_DEF_END.match(src, d)
        if e:
            return e.end()
    return -1


def def_dests(src, d):
    # the ends of the destination of a definition at d, in the order marked
    # tries them: a run of characters ([^<\s][^\s]*, one end), or <.*?> to
    # each > on its line that a space, a newline or the end follows (after
    # any other, def_end finds neither a separator nor the end of the line)
    if src[d:d + 1] != "<":
        m = MK_DEF_DEST.match(src, d)
        if m:
            yield m.end()
        return
    q = d + 1
    while True:
        a = MK_DEF_ANGLE.search(src, q)
        if not a or a.group() != ">":
            return
        q = a.end()
        yield q


def def_titles(src, t):
    # the ends of a title at t, in the order marked tries them: "..." to its
    # first " no backslash comes before, then to each " a backslash comes
    # before, the last first ("(?:\\"?|[^"\\])*" backtracking); \x27...\x27
    # to its first \x27 with no blank line before it; (...) with no ( or )
    # in it
    c = src[t:t + 1]
    if c == "\"":
        # (only those a space, a newline or the end follows, as no other
        # can be followed by the end of the line, MK_DEF_END)
        m = MK_DEF_QUOTE.search(src, t + 1)
        hi = m.start() if m else len(src)
        if m:
            yield hi + 1
        q = src.rfind("\"", t + 1, hi)
        while q >= 0:
            if src[q + 1:q + 2] in (" ", "\n", ""):
                yield q + 1
            q = src.rfind("\"", t + 1, q)
    elif c == "\x27":
        q = src.find("\x27", t + 1)
        if q >= 0 and src.find("\n\n", t + 1, q) < 0:
            yield q + 1
    elif c == "(":
        m = MK_DEF_PAREN.match(src, t)
        if m:
            yield m.end()


class MdStop(Exception):
    # md_scan stops reading: a bound passed, or marked would throw
    pass


class MdBound(str):
    # the where of md_scan when it read no import because a bound stopped
    # it (the file size, work, steps or nesting): the reason, which
    # add_import names in a sentence of its own (no block holds the line)
    pass


class MdTok:
    # a marked block token: its type, raw and text (lists of parts, joined
    # when read), the tokens of a blockquote, the items of a list ([raw,
    # text, tokens] each), its offset in the source it was lexed from, for
    # a fenced code block whether no closing fence ends it, and for a list
    # read in a scan what md_walk reads from the items it dropped (later)
    __slots__ = ("type", "rp", "tp", "tokens", "items", "at", "open", "later")

    def __init__(self, kind, at, raw, text=None, tokens=None):
        self.type, self.at, self.rp, self.tp, self.tokens, self.items, self.open, self.later = kind, at, [raw], None if text is None else [text], tokens, None, False, None

    @property
    def raw(self):
        if len(self.rp) > 1:
            self.rp = ["".join(self.rp)]
        return self.rp[0]

    @property
    def text(self):
        if len(self.tp) > 1:
            self.tp = ["".join(self.tp)]
        return self.tp[0]


class MdList(list):
    # the tokens of one source in a scan (MdLexer with keep off): a token
    # that is no longer the last one never changes again (a merge, or a
    # quote lexing its last token again, takes the last one only), so what
    # md_walk reads from it goes to later when walk is on (md_later), and it
    # is dropped; only the last token is kept. With upto (the top level of
    # the where of md_scan), the last token that starts at upto or before
    # it is kept too, with all after it: a quote may end past upto, and the
    # tokens come in the order of their starts
    __slots__ = ("later", "walk", "upto")

    def __init__(self, walk, upto=None):
        list.__init__(self)
        self.later, self.walk, self.upto = [], walk, upto

    def append(self, t):
        if self and (self.upto is None or t.at <= self.upto):
            if self.walk:
                md_later(self[-1:], self.later)
            del self[:]
        list.append(self, t)


class MdLexer:
    # marked Lexer.blockTokens (GFM and pedantic off, no extensions) and the
    # tokenizers it calls, line for line: state.top, the merge of a code
    # block, a definition or the next line into the paragraph or text before
    # it, the merge of the first paragraph of a quote group into the last
    # one (lastParagraphClipped), a list or blockquote token consuming its
    # raw (so a quote ends at a code block and its lazy lines are lexed again
    # outside it). Bounded: work (characters lexed and scanned, nested
    # sources again) and steps (blocks, list lines, quote groups) grow with
    # the file, nesting stops past 40 quotes and lists; past one MdStop.
    # keep off (md_scan): each token list an MdList, which reads (walk on)
    # and drops what can no longer change, the same lexing in the same
    # order, so a file of many blocks holds a few tokens at a time
    def __init__(self, size, keep=True, walk=False):
        self.top = True
        self.work, self.steps, self.depth = 0, 0, 0
        self.max_work, self.max_steps = 12 * size + 4000000, 300000 + size // 8
        self.lh, self.rules = {}, {}
        self.keep, self.walk = keep, walk

    def tokens(self):
        # a new list for the tokens of a source
        return [] if self.keep else MdList(self.walk)

    def charge(self, n):
        self.work += n
        if self.work > self.max_work:
            raise MdStop("more Markdown than Triforge reads in time")

    def step(self):
        self.steps += 1
        if self.steps > self.max_steps:
            raise MdStop("more Markdown blocks than Triforge reads in time")

    def block(self, src, tokens, clipped=False):
        # depth: the top level, then one per quote or list item around src
        self.depth += 1
        if self.depth > 41:
            raise MdStop("Markdown nested more than 40 quotes and lists deep")
        self.charge(len(src))
        pos, n = 0, len(src)
        while pos < n:
            self.step()
            at, last = pos, tokens[-1] if tokens else None
            e = blank_end(src, pos, True)
            if e > pos:
                pos = e
                if pos - at == 1 and last is not None:
                    grow(last.rp, "\n")
                else:
                    tokens.append(MdTok("space", at, src[at:pos]))
                continue
            e = code_end(src, pos)
            if e >= 0:
                pos, raw = e, src[at:e]
                text = by_lines(code_text, raw).rstrip("\n")
                if last is not None and last.type in ("paragraph", "text"):
                    grow(last.rp, "\n", raw)
                    grow(last.tp, "\n", text)
                else:
                    tokens.append(MdTok("code", at, raw, text))
                continue
            m = MK_FENCES.match(src, pos)
            if m:
                # open: the match ended at the end of src, not at a closing
                # fence (group 4), as marked reads it; a second search for a
                # close would retry every shorter opening run, which is
                # quadratic in a long one
                pos = m.end()
                tokens.append(MdTok("code", at, m.group()))
                tokens[-1].open = m.group(4) is None
                continue
            m = MK_HEADING.match(src, pos)
            if m:
                pos, text = m.end(), m.group(2).strip(JS_TRIM)
                if text.endswith("#"):
                    trimmed = text.rstrip("#")
                    if not trimmed or trimmed.endswith(" "):
                        text = trimmed.strip(JS_TRIM)
                tokens.append(MdTok("heading", at, m.group(), text))
                continue
            m = MK_HR.match(src, pos)
            if m:
                raw = m.group().rstrip("\n")
                pos += len(raw)
                tokens.append(MdTok("hr", at, raw))
                continue
            t = self.blockquote(src, pos)
            if t is None:
                t = self.list(src, pos)
            if t is not None:
                pos += len(t.raw)
                tokens.append(t)
                continue
            e = html_end(src, pos)
            if e >= 0:
                pos = e
                tokens.append(MdTok("html", at, src[at:e]))
                continue
            e = def_end(src, pos)
            if e >= 0:
                pos, raw = e, src[at:e]
                if last is not None and last.type in ("paragraph", "text"):
                    grow(last.rp, "\n", raw)
                    grow(last.tp, "\n", raw)
                continue
            end = self.lheading(src, pos)
            if end:
                pos = end[0]
                tokens.append(MdTok("heading", at, src[at:pos], end[1]))
                continue
            e = para_end(src, pos) if self.top else -1
            if e >= 0:
                pos, raw = e, src[at:e]
                text = raw[:-1] if raw.endswith("\n") else raw
                if clipped and last is not None and last.type == "paragraph":
                    grow(last.rp, "\n", raw)
                    grow(last.tp, "\n", text)
                else:
                    tokens.append(MdTok("paragraph", at, raw, text))
                clipped = False
                continue
            m = MK_TEXT.match(src, pos)
            if not m:
                raise MdStop("Markdown marked cannot lex")
            pos, raw = m.end(), m.group()
            if last is not None and last.type == "text":
                grow(last.rp, "\n", raw)
                grow(last.tp, "\n", raw)
            else:
                tokens.append(MdTok("text", at, raw, raw))
        # no source is lexed twice, so its lheading table goes with it
        tab = self.lh.pop(id(src), None)
        if tab is not None and tab[0] is not src:
            self.lh[id(src)] = tab
        self.top = True
        self.depth -= 1
        return tokens

    def lheading(self, src, pos):
        # (end, text) where the lheading rule matches at pos, else None. Its
        # lazy scan reads up to the first line that ends it (MK_LH_EVENT) at
        # every attempt, which is quadratic; the same outcome from a table of
        # those lines, made once per source and bisected
        if MK_LH_FIRST.match(src, pos):
            return None
        eol = src.find("\n", pos)
        if eol < 0 or MK_LH_STOP.search(src, pos, eol):
            return None
        tab = self.lh.get(id(src))
        if tab is None or tab[0] is not src:
            self.charge(len(src))
            # the table as an array of offsets and a bytearray of flags, five
            # bytes a line; block drops it once src is lexed
            starts, under = array.array("i"), bytearray()
            for e in MK_LH_EVENT.finditer(src):
                starts.append(e.start())
                under.append(e.group(1) is not None)
            tab = self.lh[id(src)] = (src, starts, under)
        k = bisect.bisect_left(tab[1], eol + 1)
        if k == len(tab[1]) or not tab[2][k]:
            return None
        return MK_LH_UNDER.match(src, tab[1][k]).end(), src[pos:tab[1][k] - 1]

    def blockquote(self, src, pos):
        # Tokenizer.blockquote: the lines MK_QUOTE takes, lexed in groups (a
        # run of lazy lines, then the > lines after it, their markers
        # stripped), a nested quote or list token at a group end lexed again
        # with the lines left, a code block ending it
        e = quote_end(src, pos)
        if e < 0:
            return None
        self.charge(e - pos)
        # the lines marked splits the quote into, as offsets in s up to b (the
        # newline that ends the quote dropped, as marked trims it): k the
        # start of the next one, past b once the last one is read
        s, k, b = src, pos, e - 1 if src[e - 1:e] == "\n" else e
        raw, size, tokens = [], 0, self.tokens()
        while k <= b:
            self.step()
            inside, i = False, k
            while k <= b:
                le = s.find("\n", k, b)
                le = b if le < 0 else le
                if MK_QUOTE_START.match(s, k, le):
                    inside = True
                elif inside:
                    break
                k = le + 1
            craw = s[i:k - 1]
            # raw, kept as parts: the groups joined by newlines (the first
            # group is never empty, so neither is raw after it). The text
            # marked keeps beside it feeds no token, so it is not kept
            grow(raw, *(["\n", craw] if size else [craw]))
            size += len(craw) + (1 if size else 0)
            top, self.top = self.top, True
            self.block(by_lines(quote_text, craw), tokens, True)
            self.top = top
            last = tokens[-1] if tokens else None
            if k > b or last is not None and last.type == "code":
                break
            if last is not None and last.type in ("blockquote", "list"):
                # the nested token lexed again with every line left, which
                # marked rebuilds at each such group: charged, so a quote of
                # many of them stops at the work bound
                again = last.raw + "\n" + s[k:b]
                self.charge(len(again) + size)
                new = self.blockquote(again, 0) if last.type == "blockquote" else self.list(again, 0)
                if new is None:
                    raise MdStop("Markdown marked cannot lex")
                tokens[-1] = new
                # raw cut to its first size - len(last.raw) characters, then
                # new.raw, without joining it again
                cut(raw, size, max(0, size - len(last.raw)))
                size = max(0, size - len(last.raw))
                grow(raw, new.raw)
                size += len(new.raw)
                if last.type == "blockquote":
                    break
                s, k, b = again, len(new.raw), len(again)
        return MdTok("blockquote", pos, "".join(raw), None, tokens)

    def item_rules(self, indent):
        # the lines that end a list item of that content indent (list)
        r = self.rules.get(indent)
        if r is None:
            k = " {0," + str(min(3, indent - 1)) + "}"
            r = self.rules[indent] = (re.compile(k + "(?:[*+-]|[0-9]{1,9}[.)])(?:(?:[ \t][^\n]*)?(?:\n|\\Z))"),
                                      re.compile(k + "(?:- *- *-[- ]*|_ *_ *_[_ ]*|\\* *\\* *\\*[* ]*)(?:\n+|\\Z)"),
                                      re.compile(k + "(?:```|~~~)"), re.compile(k + "#"),
                                      re.compile(k + "<(?:[a-z]" + JS_DOT + "*>|!--)", re.I | re.A))
        return r

    def list(self, src, pos):
        # Tokenizer.list: items of the first bullet type, each line of an item
        # tested as marked tests it (tabs read as 4 spaces, the first line
        # with its own indent), the last item and the list trimmed at the
        # end, then each item text lexed with state.top off
        m = MK_LIST.match(src, pos)
        if not m:
            return None
        bull = m.group(1).strip(JS_TRIM)
        item = re.compile("( {0,3}" + ("[0-9]{1,9}\\" + bull[-1] if len(bull) > 1 else "\\" + bull) + ")((?:[\t ][^\n]*)?(?:\n|\\Z))")
        raws, texts, p, n, tail = [], [], pos, len(src), ""
        while p < n:
            self.step()
            cap = item.match(src, p)
            if not cap or MK_HR.match(src, p):
                break
            # raw: from start to p, and a newline after the last line when src
            # ends without one (marked appends each line with a newline)
            start, p, c2, tail = p, cap.end(), cap.group(2), ""
            line = MK_TABS.sub(lambda t: "   " * len(t.group()), c2.split("\n", 1)[0])
            e = src.find("\n", p)
            nxt = src[p:e if e >= 0 else n]
            blank, body = not line.strip(JS_TRIM), []
            if blank:
                indent = len(cap.group(1)) + 1
            else:
                indent = js_search(c2, MK_NONSPACE)
                indent = 1 if indent > 4 else indent
                body.append(line[indent:])
                indent += len(cap.group(1))
            if blank and MK_BLANK.match(nxt):
                tail = "" if e >= 0 else "\n"
                p = min(n, p + len(nxt) + 1)
            else:
                bullet, hr, fence, heading, html = self.item_rules(indent)
                while p < n:
                    self.step()
                    e = src.find("\n", p)
                    nxt = src[p:e if e >= 0 else n]
                    wide = nxt.replace("\t", "    ")
                    if fence.match(nxt) or heading.match(nxt) or html.match(nxt) or bullet.match(nxt) or hr.match(nxt):
                        break
                    if js_search(wide, MK_NONSPACE) >= indent or not nxt.strip(JS_TRIM):
                        grow(body, "\n" + wide[indent:])
                    elif blank or js_search(line.replace("\t", "    "), MK_NONSPACE) >= 4 or fence.match(line) or heading.match(line) or hr.match(line):
                        break
                    else:
                        grow(body, "\n" + nxt)
                    blank = blank or not nxt.strip(JS_TRIM)
                    tail = "" if e >= 0 else "\n"
                    p = min(n, p + len(nxt) + 1)
                    line = wide[indent:]
            self.charge(p - start + len(tail))
            if self.keep:
                raws.append(src[start:p] + tail)
            texts.append("".join(body))
        if not texts:
            return None
        # the items lie end to end from pos, and only the last can end with
        # the newline src lacks, so their raws joined are src[pos:p] + tail
        t = MdTok("list", pos, (src[pos:p] + tail).rstrip(JS_TRIM))
        texts[-1] = texts[-1].rstrip(JS_TRIM)
        if self.keep:
            raws[-1] = raws[-1].rstrip(JS_TRIM)
            t.items = [[r, x, None] for r, x in zip(raws, texts)]
            for i in t.items:
                self.top = False
                i[2] = self.block(i[1], [])
            return t
        # a scan: each item taken into later (walk on) and dropped once the
        # next one is lexed, the last one kept, with no raw or text
        t.later, toks = [], None
        for k in range(len(texts)):
            self.top = False
            if toks is not None and self.walk:
                md_later(toks, t.later)
            toks, texts[k] = self.block(texts[k], self.tokens()), None
        t.items = [[None, None, toks]]
        return t


def link_ends(text):
    # end(h): where marked ends a link whose label closes at the ]( just
    # before h, as its link rule matches: ANGLE first, else the longest RUN
    # that a title or ")" can follow (it backtracks from the end of the run,
    # so a ")" in the run stays in it), and a title read greedily, to its
    # first closer no backslash escapes, else to the last escaped one a ")"
    # follows. A destination that does not start with < then ends at its
    # first ")" that closes no "(" (findClosingBracket: escaped ones never
    # count), and the link with it. The end of text + 1 when the rule
    # places none (the opening then holds up to the last ")"). marked may
    # drop the link, and a paragraph of fewer lines ends it no later, so no
    # reading ends it past end(h). The calls come in the order of h: a run
    # is walked once for all of its openings, closers are found by bisecting
    # their positions, and each ")" test is kept, so this stays linear
    # Positions are kept in arrays ("i", -1 for none), and each ")" test in
    # one array over text (0 not made yet, 1 none, else its end + 2)
    big = len(text) + 1
    marks = array.array("i", (m.start() for m in re.finditer(rb"[\"\x27()]", text)))
    # cur: the run the last opening fell in: its end, the last place in it
    # a link ends (None: none) and that end, then unbalanced() of it
    plain, good, after, cur = {}, {}, array.array("i", [0]) * (len(text) + 2), [-1, None, big, array.array("i"), array.array("i", [-1])]

    def paren(k):
        # the end of \s* and ")" at k, None without one
        if not after[k]:
            p = runs(WS, text, k)
            after[k] = p + 3 if text[p:p + 1] == b")" else 1
        return after[k] - 2 if after[k] > 1 else None

    def title(t):
        # the end of the ")" after the title that opens at t, None without one
        c = TITLE[text[t:t + 1]]
        if c not in plain:
            plain[c] = array.array("i", (m.start() for m in re.finditer(rb"(?<!\\)" + re.escape(c), text)))
            good[c] = array.array("i", (m.start() for m in re.finditer(rb"(?<=\\)" + re.escape(c), text) if paren(m.end())))
        k = bisect.bisect_left(plain[c], t + 1)
        first = plain[c][k] if k < len(plain[c]) else big
        j = bisect.bisect_left(good[c], first) - 1
        e = paren(first + 1) if first < big else None
        return e or (paren(good[c][j] + 1) if j >= 0 and good[c][j] > t + 1 else None)

    def rest(q):
        # the end of the title and ")" after a destination that ends at q
        t = SEP.match(text, q).end()
        return (title(t) if text[t:t + 1] in TITLE else None) or paren(q)

    def unbalanced(lo, hi):
        # the parentheses in text[lo:hi] no backslash escapes, and from each
        # the first ")" that closes no "(" after it (-1: none)
        at = array.array("i", (m.end() - 1 for m in PAREN.finditer(text, lo, hi) if len(m.group(1)) % 2 == 0))
        pair, stack = array.array("i", [-1]) * len(at), array.array("i")
        for k, p in enumerate(at):
            if text[p] == 40:
                stack.append(k)
            elif stack:
                pair[stack.pop()] = k
        first = array.array("i", [-1]) * (len(at) + 1)
        for k in range(len(at) - 1, -1, -1):
            first[k] = at[k] if text[at[k]] == 41 else first[pair[k] + 1] if pair[k] >= 0 else -1
        return at, first

    def end(h):
        w = runs(WS, text, h)
        a = angle_end(text, w) if text[w:w + 1] == b"<" else -1
        e = rest(a) if a >= 0 else None
        if e:
            return e
        if w >= cur[0]:
            # a new run: from its end down to w, the first place a title or
            # ")" follows, which holds for every opening up to it
            q = RUN.match(text, w).end()
            cur[:] = [q, None, big, array.array("i"), array.array("i", [-1])]
            i = bisect.bisect_left(marks, q)
            while q >= w:
                e = rest(q)
                if e:
                    cur[1:] = [q, e] + list(unbalanced(w, q))
                    break
                i -= 1
                q = marks[i] if i >= 0 else -1
        if cur[1] is None or w > cur[1]:
            return big
        p = cur[4][bisect.bisect_left(cur[3], w)] if text[w:w + 1] != b"<" else -1
        return p + 1 if p >= 0 else cur[2]
    return end


def angle_end(text, w):
    # the end of ANGLE, <...>, at w (a <), -1 for none: its characters REP
    # at a time, the only run a > can follow being the longest
    p = runs(ANGLE, text, w + 1)
    return p + 1 if p > w + 1 and text[p:p + 1] == b">" else -1


def tag_end(text, p):
    # the end of the HTML tag at p (its attributes REP at a time: none fits
    # where \s*/?> does, so the end is the one the lazy repeat finds), -1 for
    # none
    m = TAG.match(text, p)
    m = TAG_SHUT.match(text, runs(TAG_ATTRS, text, m.end())) if m else None
    return m.end() if m else -1


def inline_held(text, refs):
    # held(pos): True when an inline construct whose words marked never
    # scans may hold pos in text, lines marked may read as one paragraph:
    # an image description (an ![ before pos and a ] after it), the
    # reference of a full reference link (one of refs, from labels), an
    # HTML tag, comment, processing instruction, declaration or CDATA
    # section, an email autolink (its backticks, * and _ taken in), or a
    # link destination or title. One opening before pos holds it unless its
    # end (link_ends for a link) comes before pos, or nothing after pos can
    # end it. Linear: a closing marker is found by bisecting its positions,
    # and an opening that ends no later than one before it adds nothing (so
    # none is read once one of its kind runs to the end)
    image, bracket, big = text.find(b"!["), text.rfind(b"]"), len(text) + 1
    link = link_ends(text) if b"](" in text else None
    in_ref = cover(*refs)
    places, by = {}, {}
    for m in INLINE.finditer(text):
        # an email autolink ends at the first > after its <, as a
        # declaration does (CLOSE "@")
        kind = b"@" if m.group(2) is not None else m.group(1)
        close = b")" if kind is None else CLOSE.get(kind, b">")
        heads, ends = by.setdefault(close, (array.array("i"), array.array("i")))
        if ends and ends[-1] == big:
            continue
        if kind is None:
            end = link(m.end())
        elif kind in CLOSE:
            if close not in places:
                places[close] = array.array("i", (x.start() for x in re.finditer(b"(?=" + re.escape(close) + b")", text)))
            k = bisect.bisect_left(places[close], m.end())
            end = places[close][k] + len(close) if k < len(places[close]) else big
        else:
            end = tag_end(text, m.start())
            end = big if end < 0 else end
        if not ends or end > ends[-1]:
            heads.append(m.end())
            ends.append(end)
    tables = [(text.rfind(close), heads, ends) for close, (heads, ends) in by.items()]

    def held(pos):
        if 0 <= image <= pos - 2 and bracket >= pos or in_ref(pos):
            return True
        for last, heads, ends in tables:
            k = bisect.bisect_right(heads, pos)
            if k and ends[k - 1] > pos and last >= pos:
                return True
        return False
    return held


def cover(*pairs):
    # inside(pos): True when a < pos < b for one of the pairs (a, b), given
    # as sets of two arrays, their a in order and their b: in a set, the
    # largest b of those whose a comes before pos, found by bisecting
    sets = []
    for heads, ends in pairs:
        peak, top = ints(len(heads)), -1
        for k, b in enumerate(ends):
            top = max(top, b)
            peak[k] = top
        sets.append((heads, peak))

    def inside(pos):
        for heads, peak in sets:
            k = bisect.bisect_left(heads, pos)
            if k > 0 and peak[k - 1] > pos:
                return True
        return False
    return inside


def labels(text):
    # (regions, refs): the (start, end) of each [ and ] in text that marked
    # may read as the label of a link, an image or a reference link, which
    # it lexes apart from the text around it (regions), or as the reference
    # of a full reference link [label][ref], which it never lexes (refs).
    # From every [, whether marked reaches it or not: the label of a link or
    # a full reference link runs over the atoms of its rule to the first ]
    # between two of them (a [...] with no [ in it, a backslash and a
    # character that ends no line, a backtick and all up to the next one,
    # any other character), and an ( or a [ follows that ]; the label of a
    # shortcut reference link, and a reference, runs to the first [ or ] no
    # backslash escapes, which must be a ]. Only labels with something in
    # them are kept. One pass from the end over what a label is read over
    # (LABEL_AT), from the first [ to the last ], each step from the ones
    # after it. marked lexes the text of a label again with each \[ and \]
    # in it read as a bracket, which no pass over the raw text places: a
    # label with one in it is held whole, as a reference is (one of refs).
    # Each set of pairs is two arrays, the starts in order and the ends:
    # regions in the order of their [, the references by the ] that ends
    # their label (one end each, the largest, all cover reads), the regions
    # held whole in the order of their [, so none needs a sort
    f, z = text.find(b"["), text.rfind(b"]")
    none = array.array("i")
    if f < 0 or z < f:
        return (none, none), ((none, none), (none, none))
    n = sum(text.count(c, f, z + 1) for c in (b"[", b"]", b"\\", b"`"))
    at = ints(n)
    for k, m in enumerate(LABEL_AT.finditer(text, f, z + 1)):
        at[k] = m.start()
    # inner[k], label[k]: the index in at of the bracket where a shortcut
    # label and a link label read from at[k] stop (-1: they fail there)
    inner, label, tick = ints(n + 1, -1), ints(n + 1, -1), n
    for k in range(n - 1, -1, -1):
        p, c = at[k], text[at[k]]
        if c == 91 or c == 93:
            inner[k] = k
            q = inner[k + 1]
            label[k] = k if c == 93 else label[q + 1] if q >= 0 and text[at[q]] == 93 else -1
        elif c == 92:
            if text[p + 1:p + 2] in (b"", b"\n", b"\r") or text[p + 1:p + 4] in (b"\xe2\x80\xa8", b"\xe2\x80\xa9"):
                inner[k] = label[k] = -1
            else:
                j = k + 2 if k + 1 < n and at[k + 1] == p + 1 else k + 1
                inner[k], label[k] = inner[j], label[j]
        else:
            inner[k], label[k], tick = inner[k + 1], label[tick + 1] if tick < n else -1, k
    # the regions are kept only when text holds a backtick (code_spans
    # reads them then alone), those with an escaped bracket in them as they
    # come; a reference is marked at the ] that ends its label (ref), its
    # end being that of the [ after it (inner), the same each time
    ticks, ref = b"`" in text, ints(n + 1, 0, "B")
    esc = array.array("i", (m.start() for m in re.finditer(rb"\\[\[\]]", text)))
    ra, rb, ea, eb = array.array("i"), array.array("i"), array.array("i"), array.array("i")
    for k in range(n):
        if text[at[k]] != 91:
            continue
        q = label[k + 1]
        if q >= 0 and text[at[q] + 1:at[q] + 2] in (b"(", b"["):
            if at[q] > at[k] + 1:
                region(ra, rb, ea, eb, ticks, esc, at[k], at[q])
            r = inner[q + 2] if q + 1 < n and at[q + 1] == at[q] + 1 else -1
            if r >= 0 and text[at[r]] == 93 and at[r] > at[q] + 2:
                ref[q] = 1
        q = inner[k + 1]
        if q >= 0 and text[at[q]] == 93 and at[q] > at[k] + 1:
            region(ra, rb, ea, eb, ticks, esc, at[k], at[q])
    del label
    fa, fb = array.array("i"), array.array("i")
    for q in range(n):
        if ref[q]:
            fa.append(at[q] + 1)
            fb.append(at[inner[q + 2]])
    return (ra, rb), ((fa, fb), (ea, eb))


def region(ra, rb, ea, eb, ticks, esc, a, b):
    # a label region (a, b) of labels: kept when ticks, and held whole when
    # an escaped bracket (esc) lies in it
    if ticks:
        ra.append(a)
        rb.append(b)
    if bisect.bisect_right(esc, b - 2) > bisect.bisect_left(esc, a + 1):
        ea.append(a)
        eb.append(b)


def tick_run(text, h):
    # (the length a backtick run at h opens with, its length): one shorter
    # after an odd number of backslashes, the last of which escapes its first
    n = TICKS.match(text, h).end() - h
    b = h
    while b > 0 and text[b - 1] == 92:
        b -= 1
    return n - (h - b) % 2, n


def tick_walk(text, starts):
    # the backtick runs of text and the walks code_spans reads (it says
    # how): their starts (heads), the next run each pairs with (nxt), the
    # runs a walk from one of starts reaches (done), the first run of each
    # length a run opens with and the last of each length (wide)
    heads, nr = ints(text.count(b"`")), 0
    for m in re.finditer(rb"(?<!\\)(\\*)(`+)", text):
        heads[nr] = m.start(2)
        nr += 1
    heads = heads[:nr]
    nxt, seen, open_at, close_at = ints(nr, -1), {}, {}, {}
    for i in range(nr - 1, -1, -1):
        opens, size = tick_run(text, heads[i])
        nxt[i] = seen.get(opens, -1) if opens else -1
        seen[size] = i
        open_at[opens] = heads[i]
        close_at.setdefault(size, heads[i])
    done = ints(nr, 0, "B")
    for s in starts:
        i = bisect.bisect_left(heads, s)
        while i < nr and not done[i]:
            done[i] = 1
            j = nxt[i]
            i = i + 1 if j < 0 else j + 1
    return heads, nxt, done, open_at, close_at


def code_spans(text, walk, held, regions, delims):
    # spanned(pos): True when pos may sit in a code span of text, lines
    # marked may read as one paragraph that begins at any line start.
    # CommonMark pairs each backtick run with the next run of its length
    # (after an odd number of backslashes its first backtick is escaped, so
    # it opens one shorter) and leaves an unpaired run literal; the pairing
    # from every start counts (their walks merge, so this stays linear).
    # Past a run an inline construct may hold (held), or one emphasis may
    # take into its token (a * or _ run that may open it before the run, a
    # run of that character after it, of delims), or past the first run of
    # a label (regions, from labels) when a walk reaches that run outside
    # every span and one of its spans runs past the end of the label (marked
    # lexes the label apart: the run pairs inside the token only, which
    # frees a later run to pair across pos), any run before pos with a run
    # of its length after pos counts. A backslash run is matched from its
    # start only, and the tests bisect (cover). The runs are an array of
    # their starts (heads), the lengths of each read again where needed
    # (tick_run); a walk spans from each run it reaches (done) to the next
    # one it pairs with (nxt), so the spans need no array of their own
    # (walk, from tick_walk)
    heads, nxt, done, open_at, close_at = walk
    nr = len(heads)
    # a label (a, b) of regions: a walk that reaches its first run i0 is
    # outside every span at a, and it pairs a run inside the label past b
    # when it never reaches i1, the first run after b. Each walk steps from
    # run i to up[i] > i, so the steps form a tree rooted past the last run,
    # and the walk from i reaches k when i is under k: the size[k] runs
    # under k, k with them, are numbered from order[k] on (the runs from the
    # last back, each taking the next free number under the run it steps to)
    big = len(text) + 1
    cross = big
    ra, rb = regions
    if ra and nr:
        # up[i], the run a walk at i steps to: nxt[i] + 1 when it pairs, else i + 1
        size, order, free = ints(nr + 1, 1), ints(nr + 1), ints(nr + 1)
        free[nr] = 1
        for i in range(nr):
            size[i + 1 if nxt[i] < 0 else nxt[i] + 1] += size[i]
        for i in range(nr - 1, -1, -1):
            u = i + 1 if nxt[i] < 0 else nxt[i] + 1
            order[i], free[u] = free[u], free[u] + size[i]
            free[i] = order[i] + 1
        del free
        for a, b in zip(ra, rb):
            i0, i1 = bisect.bisect_right(heads, a), bisect.bisect_right(heads, b)
            if i0 < i1 and done[i0] and not order[i1] <= order[i0] < order[i1] + size[i1]:
                cross = min(cross, heads[i0])
        del size, order
    within = cover((heads, (heads[nxt[i]] if done[i] and nxt[i] >= 0 else -1 for i in range(nr))))
    del nxt
    _, first, last = delims
    owned = next((h for h in heads if h >= cross or held(h) or any(first[ch] < h < last[ch] for ch in first)), big)
    pairs = sorted((open_at[n], close_at[n]) for n in open_at if n and n in close_at)
    wide = cover((array.array("i", (a for a, _ in pairs)), array.array("i", (b for _, b in pairs))))

    def spanned(pos):
        return wide(pos) if owned < pos else within(pos)
    return spanned


def path_ok(d):
    # True when Claude Code reads the import path d + AGENTS.md whole (d is
    # the <path> part of IMPORT, "" for none): none of PATH_CUT in it, a
    # PATH_HEAD start, and no special absolute path. A * or _ in d is held
    # against its paragraph (emphasis)
    if not d:
        return True
    if PATH_CUT.search(d) or not PATH_HEAD.match(d):
        return False
    if d[:1] != b"/":
        return True
    if d[:2] == b"//" or b"??" in d:
        return False
    # Claude Code tests the first directory at each step of its walk down
    # the path, so /.vol/../x is dropped although it ends outside /.vol
    parts = []
    for c in d.split(b"/"):
        if c == b"..":
            parts[-1:] = []
        elif c not in (b"", b"."):
            parts.append(c)
            if ZERO_WIDTH.sub(b"", parts[0]).lower() in PATH_ROOTS:
                return False
    return True


def joined(text, ls, s):
    # True when the word at s in text, on the line that starts at ls, may sit
    # in the path of an earlier import: Claude Code takes a backslash and a
    # space into a path, so @x\ @AGENTS.md is the one path "x @AGENTS.md",
    # and it starts a path after whitespace or where a text token of marked
    # may begin. Back from the "\ " before s, over what a path holds (no
    # other whitespace or backslash; every byte past ASCII, which may be a
    # JavaScript space, held as path, and a backslash before [ or ], which
    # marked drops from a link label), an @ at the start of the line, after
    # whitespace, after TOKEN_EDGE or after a backslash and one of PUNCT
    # joins it
    k = s - 2
    if k < ls or text[k:s] != b"\\ ":
        return False
    while k > ls:
        c, prev = text[k - 1:k], text[max(k - 2, ls):k - 1]
        if c == b"@" and (not prev or prev.isspace() or prev >= b"\x80" or prev in TOKEN_EDGE or PUNCT.fullmatch(prev) and text[max(k - 3, ls):k - 2] == b"\\"):
            return True
        if c == b" " and prev == b"\\":
            k -= 2
        elif c.isspace() or c == b"\\" and text[k:k + 1] not in (b"[", b"]"):
            return False
        else:
            k -= 1
    return False


def delim_runs(text):
    # (runs, first, last): the * and _ runs of text as emphasis and
    # code_spans read them, each as its start and character, and per
    # character the start of the first run that may open emphasis and of
    # the last run. Wider than marked: a run opens unless a space, tab or
    # line end follows it, any run closes, and only an _ between two ASCII
    # letters or digits does neither (it is no run here)
    # The runs are two arrays, the starts and the characters
    first, last, starts, chars = {}, {}, array.array("i"), bytearray()
    for m in re.finditer(rb"\*+|_+", text):
        s, e, ch = m.start(), m.end(), text[m.start():m.start() + 1]
        if ch == b"_" and ALNUM.fullmatch(text[s - 1:s]) and ALNUM.fullmatch(text[e:e + 1]):
            continue
        starts.append(s)
        chars += ch
        if text[e:e + 1] not in SPACE:
            first.setdefault(ch, s)
        last[ch] = s
    return (starts, chars), first, last


def emphasis(text, delims):
    # paired(a, b): True when a * or _ run in text[a:b] may pair with another
    # run of its character in text, lines marked may read as one paragraph,
    # as emphasis that splits the import word there (delims, from
    # delim_runs). The runs in text[a:b] are found by bisecting their starts
    (heads, chars), first, last = delims

    def paired(a, b):
        return any(first.get(ch, len(text)) < s or last[ch] > s for s, ch in ((heads[i], b"*" if chars[i] == 42 else b"_") for i in range(bisect.bisect_left(heads, a), bisect.bisect_left(heads, b))))
    return paired


def text_words(text):
    # the IMPORT matches in text, the inline source of a paragraph, a heading
    # or the text of a list item (bytes), that are text for certain: an
    # import word with no backtick in it, a path Claude Code reads whole
    # (path_ok, emphasis) and no earlier path that takes it in (joined),
    # outside every inline construct and code span. A code span is paired
    # from every line start, which is wider than the one start marked uses.
    # Only a word holding AGENTS.md can be an import, so the words are those
    # around each AGENTS.md, in order, each with the start of its line
    if b"AGENTS.md" not in text:
        return []
    at, words, ls, end = array.array("i"), [], 0, 0
    i = text.find(b"AGENTS.md")
    while i >= 0:
        s = max(end, max(text.rfind(c, end, i) for c in SPACE[1:]) + 1)
        ls = max(ls, text.rfind(b"\n", end, s) + 1)
        end = WORD.match(text, i).end()
        m = IMPORT.fullmatch(text, s, end)
        if m and b"`" not in text[s:end] and path_ok(m.group(1)) and not joined(text, ls, s):
            at.append(s)
            words.append(found_word(m))
        i = text.find(b"AGENTS.md", end)
    if not words or not INLINE_ANY.search(text):
        # with no [, ], <, backtick, * or _ in text, no construct holds a
        # word (held needs a bracket or a <), no code span, no emphasis
        return words
    regions, refs = labels(text)
    held = inline_held(text, refs)
    # with no backtick no code span, with no * or _ (and none) no emphasis
    ticks = b"`" in text
    delims = delim_runs(text) if ticks or b"*" in text or b"_" in text else None
    spanned = code_spans(text, tick_walk(text, line_starts(text)), held, regions, delims) if ticks else None
    paired = emphasis(text, delims) if delims else None
    return [w for p, w in zip(at, words) if not held(p) and not (spanned and spanned(p)) and not (paired and paired(p + 1, p + 1 + len(w.group(1))))]


def line_starts(text):
    # the offset of each line of text, in order
    yield 0
    for m in re.finditer(b"\n", text):
        yield m.end()


def uncomment(raw):
    # raw with its comments dropped, as Claude Code replaces <!--[\s\S]*?-->
    # throughout: each <!-- to the first --> after it. A <!-- with no -->
    # after it ends the search, since no later one has one either (the
    # regex would scan to the end again from each of them)
    parts, at = [], 0
    while True:
        s = raw.find("<!--", at)
        e = raw.find("-->", s + 4) if s >= 0 else -1
        if e < 0:
            parts.append(raw[at:])
            return "".join(parts)
        grow(parts, raw[at:s])
        at = e + 3


def html_words(raw):
    # the IMPORT matches Claude Code reads in an HTML block (raw, its marked
    # source): only in one that opens with a comment and closes one, outside
    # its comments (uncomment), each path after an @ at the start or after a
    # JavaScript space (at_paths), read whole (path_ok), no backslash in it
    lead = raw.lstrip(JS_TRIM)
    if not lead.startswith("<!--") or "-->" not in lead:
        return []
    rest = uncomment(raw)
    found = []
    for w in at_paths(rest):
        m = None if "\\" in w else IMPORT.fullmatch(b"@" + js_bytes(w))
        if m and path_ok(m.group(1)):
            found.append(found_word(m))
    return found


def at_paths(rest):
    # the path of each MK_AT match in rest, as finditer gives them: an @ at
    # the start or after a JavaScript space (MK_AT_OPEN, at least one path
    # character after it), then the path, MK_AT_PATH again while it moves
    p = 0
    while True:
        m = MK_AT_OPEN.search(rest, p)
        if not m:
            return
        p = runs(MK_AT_PATH, rest, m.end())
        yield rest[m.end():p]


def md_walk(tokens, found):
    # the imports in marked block tokens, as Claude Code walks them: what
    # each holds that may have one (md_later), then read
    later = []
    md_later(tokens, later)
    for x in later:
        found.extend(text_words(js_bytes(x)) if isinstance(x, str) else html_words(x[0]))


def md_later(tokens, later):
    # what md_walk reads from tokens, in order: what an MdList took from the
    # tokens it dropped, then from each token the inline source of a
    # paragraph, heading or list item text, and an HTML block (as a 1-tuple),
    # when it holds AGENTS.md (no import is read from one without), the
    # tokens of a quote and of each list item (what a scan took from the
    # items it dropped first); from a code block nothing
    if isinstance(tokens, MdList):
        later.extend(tokens.later)
    for t in tokens:
        if t.type in ("paragraph", "heading", "text"):
            if "AGENTS.md" in t.text:
                later.append(t.text)
        elif t.type == "html":
            if "AGENTS.md" in t.raw:
                later.append((t.raw,))
        elif t.type == "blockquote":
            md_later(t.tokens, later)
        elif t.type == "list":
            later.extend(t.later or ())
            for item in t.items:
                md_later(item[2], later)


def md_stop(e):
    # the MdBound for what stopped MdLexer
    return MdBound(str(e) if isinstance(e, MdStop) else "Markdown nested deeper than Triforge reads")


# what md_read made of the bytes of the last two calls: imports, add_import
# and import_bound read the same bytes of a file more than once
SCANS = []


def md_read(data, src):
    # (found, stop) for data, its text src: the imports md_walk reads from
    # the tokens MdLexer reads, or none and the MdBound of what stopped it.
    # A scan (keep off): every token read as soon as it can no longer
    # change, then dropped
    for d, got in SCANS:
        if d is data:
            return got
    found, stop = [], None
    try:
        md_walk(MdLexer(len(src), False, True).block(src, MdList(True)), found)
    except (MdStop, RecursionError) as e:
        found, stop = [], md_stop(e)
    SCANS[:] = SCANS[-1:] + [(data, (found, stop))]
    return found, stop


def md_scan(data, where=False):
    # (found, open): the IMPORT matches Claude Code reads as text in data
    # (md_read, none when MdLexer stops), and with where the construct a
    # line appended to data lands in when it is no text there ("" for none
    # or without where): the top-level block that takes the line @AGENTS.md
    # appended, read the same way, or an MdBound when a bound stops the
    # reading of data, or of data with that line
    if len(data) > MD_MAX:
        return [], MdBound("more than " + str(MD_MAX) + " bytes") if where else ""
    prefix, body = md_body(data)
    src = js_text(body)
    del body
    found, stop = md_read(data, src)
    if stop is not None:
        return [], stop if where else ""
    if not where:
        return found, ""
    # the line appended read with nothing kept but what the where below
    # reads: the last token of each list, and at the top level the last
    # that starts at the line or before it (MdList upto)
    tail = src + ("\n" if src and not src.endswith("\n") else "") + "@AGENTS.md\n"
    del src
    at = len(tail) - len("@AGENTS.md\n")
    try:
        tokens = MdLexer(len(tail), False, False).block(tail, MdList(False, at))
    except (MdStop, RecursionError) as e:
        return found, md_stop(e)
    t = ([None] + [t for t in tokens if t.at <= at])[-1]
    if t is None or t.at + len(t.raw) <= at:
        # no token reaches the line: a link reference definition, the one
        # block marked keeps no token for, took it in
        return found, "a link reference definition, which takes the line in as its destination or title"
    line = "line " + str(prefix.count(b"\n") + 1 + tail.count("\n", 0, t.at))
    if t.type == "code" and t.open:
        return found, "the fenced code block opened on " + line + ", which is never closed"
    if t.type == "html":
        return found, "the HTML block that starts on " + line
    if t.type in ("blockquote", "list"):
        # the line joins the last block of the quote or list item: named
        # when it is a fenced code block or HTML block left open there
        kind, inner = "quote" if t.type == "blockquote" else "list", t
        while inner.type in ("blockquote", "list"):
            sub = inner.tokens if inner.type == "blockquote" else inner.items[-1][2]
            if not sub:
                break
            inner = sub[-1]
        what = "the fenced code block in " if inner.type == "code" and inner.open else "the HTML block in " if inner.type == "html" else ""
        return found, what + "the " + kind + " that starts on " + line + ", which may take the line in"
    return found, ""


def imports(path, data, targets):
    # True when the file at path imports AGENTS.md from one of targets
    # (physical directories) by an import Claude Code reads as text there
    # (md_scan). The path of an import is relative to the directory of the
    # file holding it, ~/ is HOME, an absolute path stands, ".." collapses
    # lexically (as cd does) before symlinks resolve.
    base = os.path.dirname(path)
    for m in dict.fromkeys(md_scan(data)[0]):
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


def reads_back(path, line, target):
    # True when this reader (imports) takes line, written into the file at
    # path, as an import of <target>/AGENTS.md. A line that does not read
    # back would be written but never seen as that import, so every approved
    # run would append it again: a path that holds whitespace ends the
    # import there, one that starts with ~/ is read from HOME (a directory
    # named ~ on the way down), and one holding a character Claude Code
    # does not read whole (path_ok, emphasis) is none. No writer writes such
    # a line, and neither a fix nor the import column of detect offers one;
    # a line with no path (@AGENTS.md, @../AGENTS.md) always reads back. The
    # line is judged alone here; add_import also reads back the whole file
    # with the line appended, which a file ending inside a code block fails
    return imports(path, os.fsencode(line), {os.path.realpath(target)})


def user_tiers(project):
    # the user tier of each reader for project (tier_home), present or not
    return [os.path.join(tier_home(r, project), r["user_tier"]) for r in READERS.values() if r["user_tier"] and tier_home(r, project)]


def is_user_tier(path, project):
    return lexists(path) and any(lexists(u) and same_file(path, u) for u in user_tiers(project))


def user_files(project):
    # (path, label) of every file a reader takes from the directories of the
    # user, from READERS: its user tier under HOME, which stays theirs when
    # $<home_env> moves it, and the one there that tier_home takes for
    # project; then its user-level file and override in its reader home
    # ($<home_env> honored, as reader_home does)
    files = []
    for r in READERS.values():
        if r["user_tier"] and home():
            files.append((os.path.join(home(), r["home_default"], r["user_tier"]), "user-tier ~/" + r["home_default"] + "/" + r["user_tier"]))
        if r["user_tier"] and r["home_env"] in os.environ and tier_home(r, project):
            files.append((os.path.join(tier_home(r, project), r["user_tier"]), "user-tier $" + r["home_env"] + "/" + r["user_tier"]))
        rh = reader_home(r)
        if not rh:
            continue
        shown = "$" + r["home_env"] if r["home_env"] and os.environ.get(r["home_env"], "") else "~/" + r["home_default"]
        files += [(os.path.join(rh, n), "user-level " + shown + "/" + n) for n in (r["user_level"], r["override"]) if n]
    return files


def user_owned(path, project):
    # why no writer may write path ("" when one may): it is, or would be, one
    # of user_files for project, or it sits in the directory of one. same_file
    # compares by identity where both exist (a hard link; a link to the file
    # or to its directory) and by physical path where one does not, so an
    # absent target is caught too
    files = user_files(project)
    for u, label in files:
        if same_file(path, u):
            return path + " is your " + label + ", which Triforge reads and never writes; edit it yourself"
    for u, label in files:
        if same_file(os.path.dirname(path), os.path.dirname(u)):
            return path + " is in the directory of your " + label + ", which Triforge reads and never writes; edit it yourself"
    return ""


def home_or_above(level):
    # True when level is HOME or a directory above it: same_file against the
    # physical HOME and each directory above it, the identity test
    # _tb_home_anchor (bootstrap.sh) makes, so a link or another spelling of
    # HOME is caught. HOME unset or no directory: nothing to protect
    h = home()
    if not h or not os.path.isdir(h):
        return False
    return any(same_file(level, d) for d in levels_up(os.path.realpath(h)))


def here():
    # the working directory, physical ("" when it is gone)
    try:
        return os.path.realpath(os.getcwd())
    except OSError:
        return ""


def home_why(path, level):
    # why no writer may write path ("" when one may): its level is HOME or a
    # directory above it, where every project under it reads the file. Run
    # from there, the way out is a project directory, never a file there
    if not home_or_above(level):
        return ""
    why = path + " is in your home directory or a directory above it, where an instruction file is read for every project under it, so Triforge never writes one there; "
    if here() and home_or_above(here()):
        return why + "the working directory is no project: start in a project directory instead"
    own = CLAUDE_KINDS[0]
    return why + "scope it to the project instead: the pointer block in the AGENTS.md of the project itself, and a " + own + " beside it holding the line " + import_line(own, "/", "/") + ", which loads that AGENTS.md for that project only"


def kind_names(kinds):
    return ", ".join(kinds[:-1]) + " or " + kinds[-1] if len(kinds) > 1 else "".join(kinds)


def row(kind, where, path, level, project):
    data = load_md(path) if kind in CLAUDE_KINDS else load(path)[0]
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
    imp = imp if reads_back(path, imp, project) else "-"
    if imp != "-" and states[0] == "no-import" and import_bound(path, data, imp, project):
        # a line a reading bound stops (import_bound): no line can import
        # AGENTS.md from this file as Triforge reads it, so the column is -
        # and the state says why (past-bound); visibility and
        # instruction_add_import name the bound. Session start reads both.
        imp = "-"
        states.append("past-bound")
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
            if not lexists(path) or is_user_tier(path, project):
                continue
            out(row(kind, where, path, level, project))
    for r in READERS.values():
        th = tier_home(r, project) if r["user_tier"] else ""
        if th and lexists(os.path.join(th, r["user_tier"])):
            # named as the walk names it: ~/.claude/CLAUDE.md is the kind
            # .claude/CLAUDE.md at HOME, $CLAUDE_CONFIG_DIR/CLAUDE.md the kind
            # CLAUDE.md there unless that directory is a .claude too
            sub = os.path.basename(th.rstrip("/")) + "/" + r["user_tier"]
            kind, level = (sub, os.path.dirname(th.rstrip("/"))) if sub in CLAUDE_KINDS else (r["user_tier"], th)
            out(row(kind, "user", os.path.join(th, r["user_tier"]), level, project))
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
    # (settings, path, state) of <reader home>/<config>; state absent | read |
    # unreadable | cut (more than FILE_MAX bytes: nothing past them known)
    rh = reader_home(r)
    path = os.path.join(rh, r["config"]) if rh and r["config"] else ""
    empty = {"max": None, "trust": {}}
    if not path or not lexists(path):
        return empty, path, "absent"
    data, size = load(path)
    if data is not None and size > FILE_MAX:
        return empty, path, "cut"
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
    # (path, bytes, size) of the file the reader takes from its home first
    rh = reader_home(r) if r["user_level"] else ""
    return level_file(r, rh, r["user_level"]) if rh else (None, None, 0)


def too_long(path, what):
    # the clause that names the FILE_MAX bound a file passes
    return path + " is more than the " + str(FILE_MAX) + " bytes Triforge reads from " + what


def visibility(fn, lead, reader, start):
    # an unknown reader fails closed: the pointer is not known to reach the lead
    if not os.path.isdir(start):
        err(fn + ": REFUSED — " + clean(start) + " is not a directory (rc 2)")
        return 2
    if home_or_above(start):
        # no project, so no fix: every file there is one the writers refuse
        return say(lead, "hidden", "not a project: " + os.path.realpath(start) + " is your home directory or a directory above it, and an instruction file there is read for every project under it; start in a project directory")
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
    if cfg_state == "cut":
        # a trust entry past the bytes read may mark this project untrusted
        return say(lead, "hidden", too_long(cfg_path, "the reader config") + ", so whether it marks this project " + r["untrusted"] + " or sets " + r["budget_key"] + " is not known, nor whether AGENTS.md reaches this reader; shorten it")
    for key, value in cfg["trust"].items():
        if r["untrusted"] and value == r["untrusted"] and isinstance(key, str) and os.path.realpath(key) in (levels[0], cwd):
            return say(lead, "hidden", "the project " + key + " is marked " + value + " in " + cfg_path + " (" + r["trust_key"] + " = \"" + value + "\"), so this reader takes no project AGENTS.md")
    budget, source = budget_of(r, cfg, cfg_path)
    note = " (" + cfg_path + " is unreadable, so the default applies)" if cfg_state == "unreadable" else ""
    # each file counts at its size (load), its pointer block found in the
    # bytes read; one in the working directory longer than them and with no
    # block in them is cut, which instruction_merge_pointer does not write
    up, ud, user = user_level(r)
    used, pointers, cut = user, [], ""
    for level in levels:
        p, d, size = level_file(r, level)
        if d is None:
            continue
        if has_block(d):
            pointers.append((p, level, used + block_end(d)))
        elif size > FILE_MAX and level == cwd:
            cut = p
        used += size
    if not pointers:
        for level in levels:
            a, o = os.path.join(level, "AGENTS.md"), os.path.join(level, r["override"] or "AGENTS.md")
            d = load(a)[0] if r["override"] and lexists(a) else None
            if d is not None and has_block(d) and readable(o):
                return say(lead, "hidden", "shadowed by " + o + ": this reader takes it instead of " + a + " at that level; merge the pointer block into it by hand, or remove it")
        if cut:
            return say(lead, "hidden", "no AGENTS.md between " + levels[0] + " and " + cwd + " holds the Triforge pointer block in the bytes Triforge reads; " + too_long(cut, "an AGENTS.md") + ", so instruction_merge_pointer does not write it: shorten it, or add the block yourself")
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
                if lexists(p) and not is_user_tier(p, cwd):
                    shadows.append((p, kind, level))
        if not shadows:
            tail += ": no " + kind_names(r["shadow"]) + " at " + cwd + " or above"
        else:
            loaded = {}
            for p in [s[0] for s in shadows] + [u for u in user_tiers(cwd) if lexists(u)]:
                d = loaded[p] = load_md(p)
                if d is not None and imports(p, d, set(l for _, l, _ in pointers)):
                    return say(lead, "visible", p + " imports " + pointer + ", so it is loaded with that file" + note)
            p, kind, level = shadows[0]
            # a fix builds only on a pointer block below HOME: one in HOME or
            # above it is read for every project, and the writers refuse it
            mine = [x for x in pointers if not home_or_above(x[1])]
            if not mine:
                fix = pointer + " is in your home directory or a directory above it, which every project under it reads: put the pointer block in the AGENTS.md of this project instead (instruction_merge_pointer " + cwd + ")"
            else:
                pointer, plevel = mine[0][0], mine[0][1]
                line = import_line(kind, level, plevel)
                fix = "add the line " + line + " to " + p + " (instruction_add_import " + p + (", run from " + plevel if plevel != cwd else "") + ")"
                # an import a reading bound would stop (import_bound) is
                # never offered: the bound is named instead, in the words
                # instruction_add_import refuses it with
                bound = import_bound(p, loaded.get(p), line, plevel)
                if level != plevel and plevel.startswith(level.rstrip("/") + "/"):
                    # a file above the project: a file in the project first; an
                    # import there reaches every project under it, and none is
                    # offered at HOME or above (the writers refuse those), nor
                    # one that would not read back (reads_back)
                    own = "add a " + CLAUDE_KINDS[0] + " holding the line " + import_line(CLAUDE_KINDS[0], plevel, plevel) + " to " + plevel + ", which loads it for that project only"
                    if home_or_above(level) or not reads_back(p, line, plevel):
                        fix = own
                    elif bound:
                        fix = own + "; " + bound
                    else:
                        fix = own + "; or " + fix + ", which loads it for every project under " + level
                elif bound:
                    own = CLAUDE_KINDS[0]
                    fix = bound + ("" if same_file(p, os.path.join(plevel, own)) else "; or put the line " + import_line(own, plevel, plevel) + " in " + os.path.join(plevel, own) + " instead, which loads it for this project only")
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
    why = user_owned(path, here()) or home_why(path, level)
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
                # one byte past old at most: a longer file differs from old
                # all the same, and a huge one is never read whole
                cur, mode = f.read(0 if old is None else len(old) + 1), stat.S_IMODE(st.st_mode)
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


def appended(path, data, line, project):
    # (new, why) for the line appended to the CLAUDE.md-family file at path
    # (data, as load_md read it): new, its bytes then; why, None when this
    # reader reads new back as an import of <project>/AGENTS.md, an MdBound
    # when a reading bound stops it there (the bytes Claude Code reads an
    # import from, the work, steps or nesting md_scan reads), the sentence
    # instruction_add_import refuses with and visibility and detect name,
    # else where md_scan says the line lands ("" for no block)
    new = data + (b"\n" if data and not data.endswith(b"\n") else b"") + os.fsencode(line) + b"\n"
    if imports(path, new, {project}):
        return new, None
    agents = os.path.join(project, "AGENTS.md")
    if len(new) > MD_MAX:
        # a size bound: Claude Code reads no import from the file, and data
        # may be only its first MD_MAX + 1 bytes (load_md)
        size = "is more than" if len(data) > MD_MAX else "would be " + str(len(new)) + " bytes with the line " + line + " appended, more than"
        return new, MdBound(path + " " + size + " the " + str(MD_MAX) + " bytes Claude Code reads an import from, and Triforge reads no import from such a file either, so the line " + line + " would not read back as an import of " + agents + " there; shorten the file, or add the line yourself where Claude Code reads it")
    where = md_scan(data, True)[1]
    if isinstance(where, MdBound):
        # another bound: the file holds more, or deeper, Markdown than
        # MdLexer reads, so no import is read from it, the line included
        return new, MdBound(path + " with the line " + line + " appended holds " + where + ", and Triforge reads no import from such a file, so the line would not read back as an import of " + agents + " there; add the line yourself where Claude Code reads it")
    return new, where


def import_bound(path, data, line, project):
    # the sentence of appended that names a reading bound, when it stops the
    # line in the CLAUDE.md-family file at path (data, as load_md read it)
    # from reading back as an import of <project>/AGENTS.md; "" when the
    # file imports it already, the line reads back, or something else keeps
    # it from that (instruction_add_import names that itself)
    if data is None or imports(path, data, {project}):
        return ""
    why = appended(path, data, line, project)[1]
    return why if isinstance(why, MdBound) else ""


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
    data = load_md(path)
    if data is None:
        return refuse(fn, path + " is not a regular file")
    if imports(path, data, {project}):
        out("unchanged: " + path + " already imports " + os.path.join(project, "AGENTS.md"))
        return 0
    line = import_line(kind, lev, project)
    own = CLAUDE_KINDS[0]
    if not reads_back(path, line, project):
        # the line would never be seen as this import (reads_back), so it is
        # refused before any plan, also with --yes
        return refuse(fn, path + " would need the line " + line + ", which would not read back as an import of " + os.path.join(project, "AGENTS.md") + " (an import path ends at whitespace or a #, one that starts with ~/ is read from your home directory, one that starts with any character but a letter, a digit, . _ or - loads nothing, and Markdown reads a backslash, <, [, ], or a * or _ that pairs, in it as markup); put the line " + import_line(own, project, project) + " in " + os.path.join(project, own) + " instead, which loads it for this project only")
    new, why = appended(path, data, line, project)
    if why is not None:
        # the line reads back alone, but appended it lands where Claude Code
        # reads no import (md_scan: the file ends inside a fenced code block
        # never closed, say), so every approved run would append it again:
        # refused before any plan, also with --yes, naming where, or the
        # reading bound that stops Triforge there
        alt = "" if same_file(path, os.path.join(project, own)) else "; or put the line " + import_line(own, project, project) + " in " + os.path.join(project, own) + " instead, which loads it for this project only"
        agents = os.path.join(project, "AGENTS.md")
        if isinstance(why, MdBound):
            return refuse(fn, why + alt)
        if why:
            return refuse(fn, path + " ends inside " + why + ", so the line " + line + " appended there would not read back as an import of " + agents + " (Claude Code reads an import from Markdown text only); close it first, or add the line yourself outside it" + alt)
        return refuse(fn, path + " would not read back the line " + line + ", appended at its end, as an import of " + agents + " (Claude Code reads an import from Markdown text only, never from front matter, a code span or inline HTML, nor one whose * or _ pairs with another in its paragraph); add the line yourself where Claude Code reads it" + alt)
    plan = "add the line " + line + " to " + path + ", so Claude Code loads " + os.path.join(project, "AGENTS.md") + " with it"
    if lev != project:
        # a file above the project: every project under it loads the import
        plan += ", and so does every project under " + lev + ", not only this one; for this project alone, put the line " + import_line(own, project, project) + " in " + os.path.join(project, own) + " instead"
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
    why = user_owned(path, here()) or home_why(path, target)
    if why:
        return refuse(fn, why), None
    tmpl, size = load(template) if template else (None, 0)
    if tmpl is not None and size > FILE_MAX:
        return refuse(fn, too_long(template, "the pointer block template"), 69), None
    if tmpl is None or not has_block(tmpl) or tmpl.count(START) != 1:
        return refuse(fn, "the pointer block template " + (template or "(no plugin root)") + " is missing or has no single marked block", 69), None
    block = tmpl[tmpl.find(START):block_end(tmpl)]
    if islink(path):
        return refuse(fn, path + " is a symlink: Triforge replaces a regular file in place and never writes through a link; merge the block into the link target yourself"), None
    old = None
    if lexists(path):
        old, size = load(path)
        if old is None:
            return refuse(fn, path + " is not a regular file"), None
        if size > FILE_MAX:
            # what follows the bytes read would be lost, or the block put
            # in twice: no writer writes a file it has not read whole
            return refuse(fn, too_long(path, "an AGENTS.md") + ", and Triforge writes no file it has not read whole, so the pointer block is not merged into it; shorten it, or merge the block yourself"), None
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
    # (each at its size, load), checked against the budget the reader config
    # sets, which a config longer than the bytes read leaves unknown
    r = READERS[BUDGETED]
    cfg, cfg_path, cfg_state = reader_config(r)
    if cfg_state == "cut":
        return refuse(fn, too_long(cfg_path, "the reader config") + ", so the " + r["budget_key"] + " it sets is not known and the budget of the files the " + BUDGETED + " reader combines cannot be checked; nothing written. Shorten it"), None
    budget, source = budget_of(r, cfg, cfg_path)
    up, ud, user = user_level(r)
    above = 0
    for level in read_levels(r, target)[:-1]:
        above += level_file(r, level)[2]
    total = user + above + len(new)
    override = os.path.join(target, r["override"]) if r["override"] else ""
    return 0, {"path": path, "target": target, "old": old, "new": new, "action": action,
               "budget": budget, "source": source, "key": r["budget_key"], "user": user, "above": above,
               "total": total, "override": override if override and readable(override) else ""}


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
    data = load_md(path)
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
    project, lev = here(), os.path.realpath(level)
    if project.startswith(lev.rstrip("/") + "/"):
        # a copy above the project: every project under it reads the change
        own = CLAUDE_KINDS[0]
        then += "; that changes what every project under " + lev + " reads, not only this one; for this project alone, put the line " + import_line(own, project, project) + " in " + os.path.join(project, own) + " instead"
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
                # one byte past data at most, as write_file reads
                cur = f.read(len(data) + 1) if stat.S_ISREG(os.fstat(f.fileno()).st_mode) else None
        except OSError:
            cur = None
        if cur != data:
            return refuse(fn, path + " not removed: it changed while the change was planned", 80)
        os.unlink(name, dir_fd=dfd)
    finally:
        os.close(dfd)
    out("changed: " + path + ": removed (an unmodified copy of the Triforge " + version + " template)")
    for k in CLAUDE_KINDS:
        p = os.path.join(lev, k)
        d = load_md(p) if lexists(p) else None
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

# _INSTR_READ_SECS — the bound a read-only run gets when its caller sets no
# _INSTR_SECS (at-setup's detect, visibility and plan calls): 30 s. An
# ordinary project's pass takes well under a second (this checkout's detect
# 0.04 s, a project whose CLAUDE.md is 4 MiB of prose 0.4 s), so only a file
# built to slow the reader, or a python3 that hangs, reaches it; and setup's
# detect block, three such calls (detect, then visibility for each CLI that
# can lead), stays inside the 2 minutes Claude Code gives a shell call by
# default even when every one is given up on (3 x 32 s).
_INSTR_READ_SECS=30

# _instr_tmp_ok <dir> — 0 when no other user can rename entries in <dir>: it
# is owned by this user or root, and has no group or other write unless the
# sticky bit is set (the rule _ss_tmp_ok applies in session-start.sh, B5).
_instr_tmp_ok() {
  local W
  [ -d "$1" ] || return 1
  if [ ! -O "$1" ]; then
    W=$(find -H "$1" -maxdepth 0 -user 0 2>/dev/null) || return 1
    [ -n "$W" ] || return 1
  fi
  W=$(find -H "$1" -maxdepth 0 \( -perm -020 -o -perm -002 \) ! -perm -1000 2>/dev/null) || return 1
  [ -z "$W" ]
}

# _instr_watchdog <dir> <seconds> <program> <op> <helper> <args...> — python3
# -c <program> <op> <helper> <args...> where neither timeout nor gtimeout is
# on PATH, given up on after <seconds>: a SIGTERM, then a SIGKILL 2 s later.
# _ss_bounded in hooks/handlers/session-start.sh does the same for the hook's
# own calls (a hook function, which this library cannot call). A subshell, so
# its fds, traps and PATH stay its own. <dir> is the private temp dir
# _instr_py made for this call and removes once it returns, so the dir is gone
# even when this subshell is SIGKILLed (a SIGKILL of _instr_py's own shell can
# still leave it). python3's stdout and stderr go to two files there; each is
# opened for writing and for reading before the dir is removed, so nothing is
# on disk while python3 runs, and the two are printed (stdout, then stderr)
# only once python3 is gone. A python3 launcher that forks instead of
# exec'ing, and leaves a child holding what it was handed, so holds no pipe
# of the caller's open. perl, when there is one (a stock macOS has
# /usr/bin/perl), starts python3 as the leader of a process group of its own
# (setpgrp, then exec), so the bound stops what python3 forks too; without
# perl it stops python3 alone. PERL_BADLANG=0, in that call's environment
# only, keeps perl from adding a "perl: warning" about a locale the system
# lacks to the caller's stderr. The watchdog is a background subshell whose
# stdio is /dev/null. Killed as soon as python3 returns before the bound, it
# first SIGKILLs its own sleep, so none outlives the call (a TERM could land
# before the sleep's exec, where the forked copy of the trap would swallow
# it); its TERM trap starts as a flag, so a TERM before the sleep exists is
# not lost, and a sleep that fails signals nothing. At the bound it TERMs the
# group, checks every 0.1 s whether a member is left, and KILLs the group
# after 2 s if one is; the call waits for it, so nothing of python3's group
# outlives the call either. A group signal goes out only right after a check
# that a member still carries the group's id (members keep the id from being
# reused), and python3's pid alone is signalled only until the call has
# reaped it (the call's TERM tells the watchdog so). Each `wait` swallows
# bash's "Terminated" or "Killed" line. rm, cat, perl and sleep are looked up
# on PATH, then in /usr/bin and /bin. rc 69, nothing run, with _instr_py's
# no-private-temp-dir line, when the two files cannot be opened in <dir>.
_instr_watchdog() (
  D=$1
  SECS=$2
  P=$3
  shift 3
  PATH="${PATH:+$PATH:}/usr/bin:/bin"
  if ! { exec 4>"$D/out" 5<"$D/out" 6>"$D/err" 7<"$D/err"; } 2>/dev/null; then
    printf '%s: neither timeout nor gtimeout is on PATH, and the watchdog that bounds python3 without them has no private temp dir (TMPDIR and /tmp are shared without the sticky bit, or mktemp failed); nothing was run (rc 69)\n' "$2" >&2
    exit 69
  fi
  rm -rf "$D"
  PL=$(command -v perl 2>/dev/null || true)
  PG='setpgrp(0, 0); exec { $ARGV[0] } @ARGV; exit 127'
  PERL_BADLANG=0 ${PL:+"$PL"} ${PL:+-e} ${PL:+"$PG"} ${PL:+--} python3 -c "$P" "$@" </dev/null >&4 2>&6 4>&- 5<&- 6>&- 7<&- &
  PID=$!
  ( R=""
    trap 'R=1' TERM
    sleep "$SECS" &
    trap 'kill -9 "$!" 2>/dev/null || true; exit 0' TERM
    if [ -n "$R" ]; then
      kill -9 "$!" 2>/dev/null || true
      exit 0
    fi
    wait "$!" || exit 0
    trap 'R=1' TERM
    kill -- -"$PID" 2>/dev/null || kill "$PID" 2>/dev/null || exit 0
    N=0
    while { kill -0 -- -"$PID" || { [ -z "$R" ] && kill -0 "$PID"; }; } 2>/dev/null; do
      if [ "$N" -ge 20 ]; then
        kill -9 -- -"$PID" 2>/dev/null || { [ -z "$R" ] && kill -9 "$PID" 2>/dev/null; } || true
        exit 0
      fi
      sleep 0.1
      N=$((N + 1))
    done
    exit 0
  ) </dev/null >/dev/null 2>&1 4>&- 5<&- 6>&- 7<&- &
  DOG=$!
  RC=0
  wait "$PID" 2>/dev/null || RC=$?
  kill "$DOG" 2>/dev/null || true
  wait "$DOG" 2>/dev/null || true
  cat <&5
  cat <&7 >&2
  exit "$RC"
)

# _instr_py <read|write> <op> <helper> <args...> — run _INSTR_PY (rc 69
# without python3). A read run (detect, visibility, a writer without --yes,
# which only plans) is given up on after _INSTR_SECS seconds when the caller
# sets it (session start: 10 s for its detect pass, and its own WARNING),
# else after _INSTR_READ_SECS, with a "gave up" line on stderr: a SIGTERM,
# then a SIGKILL 2 s later, under timeout or gtimeout (-k 2s) when one is on
# PATH, else under _instr_watchdog, in a private temp dir made here (mktemp
# -d, mode 0700, under TMPDIR, else /tmp, whichever passes _instr_tmp_ok;
# mktemp, find and rm looked up on PATH, then in /usr/bin and /bin) and
# removed here once the watchdog returns, whatever ended it (rc 69, nothing
# run, with no such dir). A run given up on returns 124 or 137
# under the timeout binary, 143 or 137 under the watchdog. A write run (a
# writer with --yes) is never bounded, _INSTR_SECS or not: write_file puts
# the change in a temp file beside the target before it renames it over the
# target, and a SIGTERM or SIGKILL landing after that would leave the temp
# file behind (python runs no cleanup for either); its reading is the plan
# run's, linear in the files' size. The timeout binary runs in the
# background, stdin /dev/null, so its pid is known: GNU timeout makes a
# process group of its own, that pid, and runs python3 in it. It never KILLs
# a child that ignores SIGTERM once the SIGTERM has ended python3, and such a
# child would hold the caller's stdout; so once timeout has given up (rc 124
# or 137), what is left of its group gets a TERM, then a KILL 2 s later, each
# right after a check that a member still holds the group's id, as
# _instr_watchdog does; the call returns once the group is empty. `wait`
# swallows the line bash prints when the SIGKILL ends timeout too.
_instr_py() {
  local MODE=$1 P SECS="" TELL="" T D TP RC=0
  shift
  if ! command -v python3 >/dev/null 2>&1; then
    printf '%s: python3 not found — the instruction-file helpers need it (rc 69)\n' "$2" >&2
    return 69
  fi
  P="${_READ_REGULAR_PY:-$_INSTR_READ_PY}
${_INSTR_PY}"
  if [ "$MODE" = read ]; then
    SECS=${_INSTR_SECS:-}
    if [ -z "$SECS" ]; then
      SECS=$_INSTR_READ_SECS
      TELL=yes
    fi
  fi
  if [ -z "$SECS" ]; then
    python3 -c "$P" "$@"
    return $?
  fi
  T=$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)
  if [ -n "$T" ]; then
    "$T" -k 2s "${SECS}s" python3 -c "$P" "$@" </dev/null &
    TP=$!
    wait "$TP" 2>/dev/null || RC=$?
    case "$RC" in
      124|137)
        ( PATH="${PATH:+$PATH:}/usr/bin:/bin"
          N=0
          while kill -0 -- -"$TP" 2>/dev/null; do
            case "$N" in
              0) kill -- -"$TP" 2>/dev/null || true ;;
              20) kill -9 -- -"$TP" 2>/dev/null || true; exit 0 ;;
            esac
            sleep 0.1
            N=$((N + 1))
          done )
        ;;
    esac
  else
    D=$(PATH="${PATH:+$PATH:}/usr/bin:/bin"
      for T in "${TMPDIR:-/tmp}" /tmp; do
        if _instr_tmp_ok "$T" && mktemp -d "${T%/}/triforge-instr.XXXXXX" 2>/dev/null; then
          break
        fi
      done) || D=""
    if [ -z "$D" ]; then
      printf '%s: neither timeout nor gtimeout is on PATH, and the watchdog that bounds python3 without them has no private temp dir (TMPDIR and /tmp are shared without the sticky bit, or mktemp failed); nothing was run (rc 69)\n' "$2" >&2
      return 69
    fi
    _instr_watchdog "$D" "$SECS" "$P" "$@" || RC=$?
    PATH="${PATH:+$PATH:}/usr/bin:/bin" rm -rf "$D"
  fi
  case "${TELL},${RC}" in
    yes,124|yes,137|yes,143)
      printf '%s: gave up after %s s (rc %s): an ordinary project'"'"'s instruction files are read in well under a second, so a file this reads (a CLAUDE.md, .claude/CLAUDE.md, CLAUDE.local.md or AGENTS.md in the project, above it or at the user level) may be built to slow the reader, or python3 hung or was killed (an out-of-memory kill also returns rc 137); nothing was written\n' "$2" "$SECS" "$RC" >&2
      ;;
  esac
  return "$RC"
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
# order into _INSTR_ARG and _INSTR_YES (0|1), and _INSTR_RUN for _instr_py
# (read without --yes: the writer only plans; write with it); rc 64 with the
# usage line.
_instr_args() {
  local FN=$1 USAGE=$2 A
  shift 2
  _INSTR_ARG=""
  _INSTR_YES=0
  _INSTR_RUN=read
  for A in "$@"; do
    case "$A" in
      --yes)
        _INSTR_YES=1
        _INSTR_RUN=write
        ;;
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
#        directory above it, nearest first, up to /) | user (the user tier,
#        then ${CODEX_HOME:-~/.codex}/AGENTS.md and AGENTS.override.md). The
#        user tier, ~/.claude/CLAUDE.md, or CLAUDE.md in $CLAUDE_CONFIG_DIR
#        when that is set to an absolute path outside <dir> (kind CLAUDE.md),
#        is a user line wherever the walk meets it (compared by identity); an
#        empty or relative CLAUDE_CONFIG_DIR, or one in <dir>, leaves no user
#        tier, and ~/.claude/CLAUDE.md is then an above line like any other.
# state  comma-separated: for a CLAUDE.md-family file "imports" (it imports
#        <dir>'s AGENTS.md, in Markdown text Claude Code reads imports from:
#        an @AGENTS.md in a code block, a code span or HTML is none) or
#        "no-import", then "stale-3x-exact" (an unmodified copy of the 3.x
#        templates/CLAUDE.md), "stale-3x-edited" (a copy with
#        edits) or "user-owned"; for AGENTS.md "pointer" (it holds the marked
#        block) or "no-pointer", AGENTS.override.md "override" first; "unreadable"
#        alone for anything that is not a readable regular file (a FIFO, a
#        directory, a dangling link); "symlink" last when the file or its .claude
#        directory is a link.
# import the line that would import <dir>'s AGENTS.md from that file (relative
#        to it: @AGENTS.md, @../AGENTS.md, @proj/AGENTS.md), "-" otherwise,
#        and "-" when that line would not read back as <dir>'s import
#        (reads_back: its path holds whitespace, starts with ~/, or holds a
#        character Claude Code does not read whole there, such as a #), so
#        no import line there can name <dir>'s AGENTS.md.
# Control characters in a path print as "?". rc 0; 2 <dir> is not a
# directory; 69 no python3; 124, 137 or 143 given up on (_instr_py).
instruction_files_detect() {
  _instr_py read detect instruction_files_detect "${1:-.}"
}

# instruction_pointer_visibility <lead> [<dir>] — whether Triforge's AGENTS.md
# (the one holding the pointer block) reaches <lead> started in <dir> (default
# the working directory), and why: one line "<lead> TAB visible|hidden TAB
# <why>", the why naming the fix. rc 0 visible, 1 hidden, 2 <dir> is not a
# directory, 64 usage, 69 no python3, 124, 137 or 143 given up on
# (_instr_py). The lead's reader is registry data
# (KTD1, `cli_field <lead> instructions`), one of READERS: claude-md-shadow
# (the CLAUDE.md family shadows AGENTS.md unless one imports it) or
# agents-chain (an untrusted project, an AGENTS.override.md at the block's
# level, the byte budget). An empty or unknown reader fails closed: "hidden",
# rc 1, the why starting "unknown reader:". From HOME or a directory above it,
# which is no project, the line is "hidden", rc 1, the why starting "not a
# project:" and naming no fix; elsewhere a fix never builds on a pointer block
# in HOME or above it, and never offers an import line that would not read
# back as the project's import (a path that holds whitespace, starts with ~/
# or holds a character Claude Code does not read whole there; the project's
# own CLAUDE.md is the fix then).
instruction_pointer_visibility() {
  local LEAD=${1:-} READER=""
  if [ -z "$LEAD" ] || [ "$#" -gt 2 ]; then
    echo "instruction_pointer_visibility: usage: instruction_pointer_visibility <lead> [<dir>]" >&2
    return 64
  fi
  READER=$(_instr_reader "$LEAD") || READER=""
  _instr_py read visibility instruction_pointer_visibility "$LEAD" "$READER" "${2:-.}"
}

# instruction_add_import <file> [--yes] — add the line that imports this
# project's AGENTS.md (the working directory's) to a CLAUDE.md, .claude/CLAUDE.md
# or CLAUDE.local.md in the project or above it. Without --yes: the planned
# line ("needs-ask: …") and rc 20; for a file above the project the plan says
# every project under that directory loads the import too, and names the
# project's own CLAUDE.md instead. A file that already imports it is left
# alone ("unchanged: …", rc 0). Refused (rc 2): another kind of file, a
# user-level file or one in its directory (~/.claude/CLAUDE.md, ~/.claude/,
# $CLAUDE_CONFIG_DIR/ when it is an absolute path outside the working
# directory, ${CODEX_HOME:-~/.codex}/), a file in HOME or a directory above
# it, a file outside the project's directory chain, a missing or non-regular
# file, a symlink or a symlinked directory, and, before any plan and also with --yes,
# a file above the project whose import line would not read back as this
# project's import (a directory on the way down to the project named ~, or
# with a space or a character Claude Code does not read whole in an import
# path, such as a #): the refusal names the project's own CLAUDE.md
# holding @AGENTS.md instead; and, the same way, a file that would not read
# the line back once it is appended at its end (the file ends inside a
# fenced code block never closed, an HTML block, or another place Claude
# Code reads no import from): the refusal names that block and its line,
# and the project's own CLAUDE.md for any other file.
instruction_add_import() {
  _instr_args instruction_add_import "instruction_add_import <file> [--yes]" "$@" || return $?
  if [ -z "$_INSTR_ARG" ]; then
    echo "instruction_add_import: usage: instruction_add_import <file> [--yes]" >&2
    return 64
  fi
  _instr_writer_ok instruction_add_import || return $?
  _instr_py "$_INSTR_RUN" add-import instruction_add_import "$_INSTR_ARG" "$_INSTR_YES"
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
# directory of a user-level file (${CODEX_HOME:-~/.codex}, ~/.claude, and
# $CLAUDE_CONFIG_DIR when it is an absolute path outside the working
# directory; through a link or another spelling too), a <dir> that is HOME or
# a directory above it (the same way), an AGENTS.md that is a user-level one
# (a hard link), a symlinked or non-regular AGENTS.md, markers not in one
# ordered pair.
instruction_merge_pointer() {
  _instr_args instruction_merge_pointer "instruction_merge_pointer [<dir>] [--yes]" "$@" || return $?
  _instr_writer_ok instruction_merge_pointer || return $?
  _instr_py "$_INSTR_RUN" merge instruction_merge_pointer "${_INSTR_ARG:-.}" "$(_instr_template)" "$_INSTR_YES"
}

# instruction_convert_stale <file> [--yes] — for a CLAUDE.md or .claude/CLAUDE.md
# that is byte for byte a 3.x templates/CLAUDE.md (EXACT_3X): merge the pointer
# block into that project directory's AGENTS.md (instruction_merge_pointer's
# plan and budget check, rc 3 over it), then remove the copy, so Claude Code
# reads AGENTS.md natively; a "note:" line names any CLAUDE.md-family file
# that still shadows it there. A copy with edits, a file that is no 3.x
# copy, one in the directory of a user-level file, or one in HOME or a
# directory above it, is refused (rc 2) and never removed. Without --yes: the
# plan and rc 20; for a copy above the project the plan says that changes what
# every project under that directory reads, and names the project's own
# CLAUDE.md instead. A file already gone: "unchanged: …", rc 0.
instruction_convert_stale() {
  _instr_args instruction_convert_stale "instruction_convert_stale <file> [--yes]" "$@" || return $?
  if [ -z "$_INSTR_ARG" ]; then
    echo "instruction_convert_stale: usage: instruction_convert_stale <file> [--yes]" >&2
    return 64
  fi
  _instr_writer_ok instruction_convert_stale || return $?
  _instr_py "$_INSTR_RUN" convert instruction_convert_stale "$_INSTR_ARG" "$(_instr_template)" "$_INSTR_YES"
}
