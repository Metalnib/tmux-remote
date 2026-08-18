#!/usr/bin/env python3
"""Structural lint for zsh scripts.

`zsh -n` is the authority, but it needs zsh and it only catches syntax. This
catches four classes it cannot see, all of which fail at runtime or silently:

    for n in $list; do print -- "$n" done   # `done` is an ARGUMENT to print
    tmux select-window -t "=$name:shell"    # ':s' of ':shell' is a modifier
    for d in $(list_dirs)                   # splits on IFS, breaks paths
    local a=$1 b=$a                         # b is empty; all values expand first

It also balances reserved words and quotes across a file, so an unterminated
block or string is reported with a line number rather than surfacing as a parse
error twenty lines later.

Not a shell parser. Deliberately conservative: it skips comments and quoted text,
and only reasons about reserved words in command position.

Usage:
    lint-shell-structure.py FILE...     check files
    lint-shell-structure.py --self-test check that the rules still fire
"""
import re
import sys

OPENERS = {"if": "fi", "for": "done", "while": "done", "until": "done", "case": "esac"}
CLOSERS = {"fi": "if", "done": ("for", "while", "until"), "esac": "case"}
TERMINATORS = ("done", "fi", "esac")

# Modifiers that fire on an UNBRACED $var followed by ':'. Most rewrite the text
# silently; ':s' aborts with "bad substitution". Invisible to `zsh -n`, because
# the expansion is only attempted at runtime.
MODIFIER_CHARS = "htreaAcluqQPs&"
UNBRACED_MODIFIER = re.compile(r"\$(?:[A-Za-z_]\w*|[0-9@*?$!#-]):[" + MODIFIER_CHARS + "]")

# zsh word-splits COMMAND SUBSTITUTION on IFS, though not plain parameter
# expansion, so `for d in $(cmd)` breaks a path containing a space. Safe forms:
# `while IFS= read -r d; do ... done < <(cmd)`, or `${(f)"$(cmd)"}`.
SPLIT_LOOP = re.compile(r"\bfor\s+[A-Za-z_]\w*\s+in\s+(?:\$\(|`)")

# A tmux #{...} field and a tab on the same line: tmux escapes control bytes in
# format output, so a tab delimiter arrives as "_".
TMUX_FMT_TAB = re.compile(r"(?:\$\{TAB\}|\t)[^\n]*#\{|#\{[^\n]*(?:\$\{TAB\}|\t)")

# A declaration's right-hand sides are all expanded before any is assigned, so a
# later value cannot refer to an earlier one. bash behaves the same way.
#
#     local name=$1 var="TMX_AI_${name}"       # var becomes "TMX_AI_"
#     local name=$1; local var="TMX_AI_$name"  # correct

# `<<WORD`, but not `<<<` (here-string) or `<< n` (arithmetic shift).
HEREDOC = re.compile(r"<<-?(?!<)\s*'?([A-Za-z_][A-Za-z0-9_]*)'?\s*$|<<-?(?!<)\s*'?([A-Za-z_][A-Za-z0-9_]*)'?\s")

DECL = re.compile(r"(?:^|;|\||&|\bthen\b|\bdo\b|\belse\b)\s*(?:local|typeset|declare|readonly)\b")
ASSIGN = re.compile(r"(?:^|\s)([A-Za-z_]\w*)=")


def self_referencing_decl(segment):
    """Names in `segment` whose value refers to a name assigned earlier in it.

    Needs two views of the raw segment: targets from a copy with all quoted spans
    blanked, so an `=` inside a string is not read as an assignment; references
    from a copy with only single-quoted spans blanked, since double-quoted text is
    where expansions live.
    """
    bare, _ = strip_quotes_and_comments(segment)
    if not DECL.search(bare):
        return []
    real_targets = {m.group(1) for m in ASSIGN.finditer(bare)}
    if len(real_targets) < 2:
        return []

    expandable, _ = blank_single_quotes(segment, False)
    spots = [m for m in ASSIGN.finditer(expandable) if m.group(1) in real_targets]
    hits = []
    for i, m in enumerate(spots[1:], start=1):
        rhs_end = spots[i + 1].start() if i + 1 < len(spots) else len(expandable)
        rhs = expandable[m.end():rhs_end]
        for earlier in (s.group(1) for s in spots[:i]):
            # $x, ${x}, and flag forms such as ${(P)x} / ${(U)x}.
            if re.search(r"\$\{?(?:\([^)]*\))?" + re.escape(earlier) + r"\b", rhs):
                hits.append((m.group(1), earlier))
                break
    return hits


def strip_quotes_and_comments(line, state=None):
    """Blank out quoted spans and trailing comments.

    `state` carries the open quote and command-substitution nesting across
    lines, since shell strings may legitimately span them. It is a stack rather
    than a single character because quotes restart inside $( ): otherwise the
    opening quote of a nested string reads as closing the outer one, and every
    "#" after it looks like a comment. Returns (code, state).
    """
    state = list(state or [])
    out = []
    i = 0
    while i < len(line):
        c = line[i]
        cur = state[-1] if state else None
        quoted = any(s in "'\"" for s in state)

        if cur == "'":
            if c == "'":
                state.pop()
            out.append(" ")
            i += 1
            continue

        if cur == '"':
            if c == "\\":
                out.append("  ")
                i += 2
                continue
            if c == '"':
                state.pop()
            elif c == "$" and line[i + 1 : i + 2] == "(":
                state.append("(")
                out.append("  ")
                i += 2
                continue
            out.append(" ")
            i += 1
            continue

        # Unquoted, or inside a $( ) which may itself sit inside a string.
        if c == "\\":
            out.append("  ")
            i += 2
            continue
        if c == "$" and line[i + 1 : i + 2] == "(":
            state.append("(")
            out.append("  " if quoted else "$(")
            i += 2
            continue
        if c in "'\"":
            state.append(c)
            out.append(" ")
            i += 1
            continue
        if c == ")" and cur == "(":
            state.pop()
            out.append(" " if quoted else c)
            i += 1
            continue
        if c == "#":
            # A comment only starts at the beginning of a word.
            if i == 0 or line[i - 1].isspace() or line[i - 1] in ";&|(":
                # Inside a string, breaking here would throw away the real
                # closing quote further along the line.
                if not quoted:
                    break
        out.append(" " if quoted else c)
        i += 1
    return "".join(out), state


def blank_single_quotes(line, sq_open):
    """Blank single-quoted spans and comments, but KEEP double-quoted text.

    The opposite of strip_quotes_and_comments: parameter expansion happens
    inside double quotes, so that is the only place this bug can hide.
    Returns (text, still_open_single_quote).
    """
    out = []
    i = 0
    dq = False
    while i < len(line):
        c = line[i]
        if sq_open:
            if c == "'":
                sq_open = False
            out.append(" ")
            i += 1
            continue
        if c == "\\":
            out.append(" " * len(line[i : i + 2]))
            i += 2
            continue
        if c == "'":
            sq_open = True
            out.append(" ")
            i += 1
            continue
        if c == '"':
            dq = not dq
            out.append(" ")
            i += 1
            continue
        if c == "#" and not dq:
            if i == 0 or line[i - 1].isspace() or line[i - 1] in ";&|(":
                break
        out.append(c)
        i += 1
    return "".join(out), sq_open


def check(path):
    with open(path, encoding="utf-8") as fh:
        return check_lines(fh.readlines())


def check_lines(lines):
    errors = []
    stack = []  # (reserved_word, lineno)
    in_heredoc = None
    open_quote = None  # carried across lines
    quote_state = []  # quote + $( ) nesting, carried across lines
    quote_started = 0
    sq_open = False  # single-quote state, tracked separately for the modifier rule

    for n, raw in enumerate(lines, 1):
        line = raw.rstrip("\n")

        if in_heredoc is not None:
            if line.strip() == in_heredoc:
                in_heredoc = None
            continue
        # Comments and `<<<` / arithmetic shifts must not look like a heredoc, or
        # one stray line silently disables every check below it.
        hd_code, _ = strip_quotes_and_comments(line)
        m = HEREDOC.search(hd_code)
        if m:
            in_heredoc = m.group(1) or m.group(2)
            continue

        # --- unbraced $var before a zsh modifier ---------------------------
        expandable, sq_open = blank_single_quotes(line, sq_open)
        for m in UNBRACED_MODIFIER.finditer(expandable):
            errors.append(
                (
                    n,
                    f"`{m.group(0)}` -- unbraced $var before ':' takes a zsh "
                    f"modifier. Use ${{var}}:... to keep the text literal, or "
                    f"${{var:...}} if the modifier is intended",
                    line.strip(),
                )
            )

        # `;` separates statements, and each one gets its own assignment pass.
        # The RAW line is passed on purpose: the check needs to see the quotes.
        for segment in line.split(";"):
            for target, earlier in self_referencing_decl(segment):
                errors.append(
                    (
                        n,
                        f"`{target}=` refers to `${earlier}` assigned in the SAME "
                        f"declaration. zsh expands all values before assigning any, "
                        f"so ${earlier} is still empty here. Split into two statements",
                        line.strip(),
                    )
                )

        if TMUX_FMT_TAB.search(expandable):
            errors.append(
                (
                    n,
                    "a tab is not a usable delimiter in a tmux `-F` format: tmux "
                    "escapes control bytes in format output, so the tab arrives "
                    "as `_`. Use a printable delimiter, and make the one field "
                    "that may contain it the last one",
                    line.strip(),
                )
            )

        for m in SPLIT_LOOP.finditer(expandable):
            errors.append(
                (
                    n,
                    "`for ... in $(...)` splits on IFS in zsh, so a path with a "
                    "space becomes two words. Use "
                    "`while IFS= read -r x; do ... done < <(cmd)` or "
                    '`${(f)"$(cmd)"}`',
                    line.strip(),
                )
            )

        was_open = open_quote
        code, quote_state = strip_quotes_and_comments(line, quote_state)
        open_quote = next((c for c in reversed(quote_state) if c in "'\""), None)
        if open_quote and not was_open:
            quote_started = n
        if was_open:
            # Continuation of a multi-line string: no code on this line to judge.
            continue

        # --- a block terminator in argument position ------------------------
        for term in TERMINATORS:
            for m in re.finditer(r"(?<![\w-])" + term + r"(?![\w-])", code):
                before = code[: m.start()].rstrip()
                if not before:
                    continue  # terminator starts the statement: fine
                # Fine if preceded by a separator, or by the matching opener
                # keyword (e.g. `do` on the same line with nothing between).
                if before[-1] in ";&|(":
                    continue
                if re.search(r"(?<![\w-])(do|then|in|else|elif|;;)$", before):
                    continue
                errors.append(
                    (
                        n,
                        f"`{term}` is in argument position -- needs a `;` or newline "
                        f"before it, or it will be swallowed as an argument",
                        line.strip(),
                    )
                )

        # --- balance reserved words ----------------------------------------
        words = re.findall(r"[\w\[\]{}:.,=<>/$-]+|;;|;|\|\||&&|\||&|\(|\)", code)
        cmd_position = True
        for w in words:
            if w in (";", "&", "|", "&&", "||", ";;", "("):
                cmd_position = True
                continue
            if cmd_position:
                if w in OPENERS:
                    # `case` inside a case-pattern list is not an opener; close
                    # enough to ignore, since this repo does not nest cases.
                    stack.append((w, n))
                elif w in CLOSERS:
                    if not stack:
                        errors.append((n, f"`{w}` with no matching opener", line.strip()))
                    else:
                        opener, oline = stack.pop()
                        want = CLOSERS[w]
                        ok = opener == want if isinstance(want, str) else opener in want
                        if not ok:
                            errors.append(
                                (
                                    n,
                                    f"`{w}` closes `{opener}` opened on line {oline}",
                                    line.strip(),
                                )
                            )
                elif w in ("do", "then", "else", "elif"):
                    pass
                cmd_position = False
            else:
                cmd_position = False

    if open_quote:
        errors.append(
            (quote_started, f"quote {open_quote!r} opened here is never closed", "")
        )

    for opener, oline in stack:
        errors.append((oline, f"`{opener}` is never closed (expected `{OPENERS[opener]}`)", ""))

    return errors


# (source line, substring expected in the message, or None for "must be clean")
SELF_TEST = [
    ('tmux select-window -t "=$name:shell"', "modifier"),
    ('tmux select-window -t "=${name}:shell"', None),
    ('tmux new-window -t "=$name:2"', None),
    ('d=$(tmux display-message -p -t "=$1:" \'#{session_path}\')', None),
    ("print -r -- '=$name:shell'", None),
    ('# tmux select-window -t "=$name:shell"', None),
    ('print -r -- "$dir:h"', "modifier"),
    ('print -r -- "${dir:h}"', None),
    ('print -- "Roots in $TMX_ROOTS_FILE:"', None),
    ('for n in $l; do print -- "$n" done', "argument position"),
    ('for n in $l; do print -- "$n"; done', None),
    # complete constructs, so the reserved-word balance check stays quiet and
    # only the rule under test can speak
    ("for d in $(list_dirs); do print -- $d; done", "splits on IFS"),
    ("for d in `list_dirs`; do print -- $d; done", "splits on IFS"),
    ("while IFS= read -r d; do print -- $d; done < <(list_dirs)", None),
    ("for d in $dirs; do print -- $d; done", None),
    ("for r in $TMX_ROOTS; do print -- $r; done", None),
    ('for d in ${(f)"$(list_dirs)"}; do print -- $d; done', None),
    ('print -- "for d in $(list_dirs)"', "splits on IFS"),
    # tmux escapes control bytes in format output, so a tab delimiter arrives
    # as "_" and every field after the first collapses into one
    ('tmux list-sessions -F "#{session_name}${TAB}#{session_path}"', "tmux `-F`"),
    ('tmux list-windows -a -F "#{window_index}\t#{window_name}"', "tmux `-F`"),
    ('tmux list-sessions -F "#{session_created}|#{session_name}"', None),
    ('print -- "SESSION${TAB}DIR${TAB}BRANCH"', None),
    ('# name TAB dir TAB attached', None),
    # quotes restart inside $( ), so a nested string must not close the outer
    # one -- and a "#" after the nested quote is not a comment
    ('IFS=\'|\' read -r a b <<<"$(cmd -p \\\n  "#{x}|#{y}" \\\n  2>/dev/null)"', None),
    ('x="$(cmd "a|b")"\nprint -- ok', None),
    ("# for d in $(list_dirs); do", None),
    # zsh assigns a whole declaration at once
    ('local name=$1 var="TMX_AI_${name}"', "SAME declaration"),
    ("typeset -g x=1 y=$x", "SAME declaration"),
    ('local name=$1; local var="TMX_AI_${name}"', None),
    ("local name=$1 dir=$2 is_wt=${3:-0}", None),
    ("local dir=${1:A} home=${HOME:A}", None),
    ("local base=${dir:t} parent=${dir:h}", None),
    ("local a=1 b=2", None),
    # an assignment inside a quoted string is not a declaration target
    ('local hint="use n=1 to set it" y=$n', None),
    ('local msg="pass flag=x" out=$flag', None),
    # flag-prefixed expansion of an earlier name in the same declaration
    ("local a=$1 b=${(P)a}", "SAME declaration"),
    ("local a=$1 b=${(U)a}", "SAME declaration"),
    # declarations that are not first in the segment
    ("if true; then local a=$1 b=$a; fi", "SAME declaration"),
    ("true && local a=$1 b=$a", "SAME declaration"),
    # heredoc detection must not be fooled by comments or shifts
    ("# the old version used a <<EOF heredoc here", None),
    ("(( x = y << 2 ))", None),
    ('print -- $(( 1 << 3 ))', None),
]


def self_test():
    failures = 0
    for src, want in SELF_TEST:
        errors = check_lines([l + "\n" for l in src.split("\n")])
        msgs = " ".join(m for _, m, _ in errors)
        if want is None:
            ok = not errors
        else:
            ok = want in msgs
        if not ok:
            failures += 1
            print(f"SELF-TEST FAIL: {src}")
            print(f"    wanted: {want!r}   got: {msgs or '(clean)'}")
    print(f"self-test: {len(SELF_TEST) - failures}/{len(SELF_TEST)} passed")
    return 1 if failures else 0


def main():
    if "--self-test" in sys.argv[1:]:
        return self_test()

    bad = 0
    for path in sys.argv[1:]:
        errors = check(path)
        if errors:
            bad = 1
            for n, msg, ctx in sorted(errors):
                print(f"{path}:{n}: {msg}")
                if ctx:
                    print(f"    {ctx}")
        else:
            print(f"{path}: structure ok")
    return bad


if __name__ == "__main__":
    sys.exit(main())
