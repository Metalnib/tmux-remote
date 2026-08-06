# Gotchas

Things that cost real debugging time while building this. All of them were
measured on the machines, with a pain. Versions where it matters: zsh
5.9, tmux 3.6a and 3.7b, macOS 15.

Most of these are the *reason* some piece of `bin/tmx` looks odd. If you are
about to tidy something up, check here first.

## zsh

**1. zsh applies history modifiers to an unbraced `$var:`.**

```zsh
tmux select-window -t "=$name:shell"     # "bad substitution", the ":s" fires
tmux select-window -t "=${name}:shell"   # correct
tmux select-window -t "=$name:2"         # fine, no modifier is named "2"
```

`:s` is the loud case. `:h :t :r :e :a :A :c :l :u :q :Q :P :&` all rewrite the
text *silently*. Brace anything followed by a colon.

Invisible to `zsh -n`, because the expansion is only attempted at runtime.
`bin/lint-shell-structure.py` has a rule for it.

**2. zsh word-splits command substitution, but not parameter expansion.**

```zsh
for d in $(list_dirs); do ...            # a path with a space becomes two words
while IFS= read -r d; do ... done < <(list_dirs)   # correct
for d in ${(f)"$(list_dirs)"}; do ...             # also correct, splits on newlines
```

Any directory whose name contains a space fails to resolve, and lists as
fragments. Process substitution has the added advantage of keeping the loop in
the current shell, so `return` and variable assignment work.

Also invisible to `zsh -n`, and also covered by the linter.

**3. A one-line `do … done` swallows its terminator.**

```zsh
for x in $l; do print -- "$x" done       # `done` is an ARGUMENT to print
for x in $l; do print -- "$x"; done      # correct
```

The loop is then unterminated and the error surfaces many lines later. After a
bare *assignment* it happens to work, because `done` is still in command
position, which is why only some instances break. Covered by the linter.

**4. A `local` value cannot refer to another name in the same statement.**

```zsh
local name=$1 var="TMX_AI_${name}"      # var becomes "TMX_AI_" -- silently
local name=$1; local var="TMX_AI_$name" # correct
```

Every right-hand side is expanded before any is assigned, so `$name` is still
empty when `var` is built. bash 5.3.15 behaves identically, so there is no
portable version of this; the pattern is simply wrong. It produces a wrong value
rather than an error, so nothing complains.

Covered by the linter, including the `${(P)x}` form.

**5. `zsh -n` is the authority, but it is not enough.** It catches syntax and
nothing else. The items above all pass it. Run both:

```sh
zsh -n bin/tmx && zsh -n bin/tmx-status
python3 bin/lint-shell-structure.py bin/tmx bin/tmx-status
python3 bin/lint-shell-structure.py --self-test
```

## tmux

**6. Session names: tmux silently rewrites `.` and `:` to `_`.**

`new-session -s a.b` stores `a_b`. Every later `has-session -t=a.b`, `new-window
-t "=a.b:2"` and `select-window` then fails, because the name you asked for is
not the name that exists. Any tool deriving session names from paths has to
replace those two characters itself, or its naming stops being predictable.
Spaces, parens, `/`, `$` and non-ASCII letters are all kept verbatim and work
with every target form.

**7. The `=` exact-match target prefix is not accepted everywhere.** Measured on
3.6a:

| target form | `has-session` `kill-session` `attach-session` `switch-client` `new-window` `select-window` `list-windows` | `set-option` `show-options` `display-message` |
|---|---|---|
| `-t "=name"` | works | **fails** - silently empty, or "no such session" |
| `-t "=name:"` | works | works |
| `-t "name"` | works | works, but **prefix-matches** when the exact name is absent |

The silent-empty case is the dangerous one. The prefix-matching case is worse:
with only `probe-alpha` alive, `tmux set-option -t probe-a @who HIJACKED` writes
onto `probe-alpha`. tmux prefers an exact match only when one actually exists,
so any bare-name call must first establish that the session is really there.

**8. tmux panes are already interactive login shells.** `$0` in a pane is
`-zsh`, with the leading dash. This depends on `default-command` being left
**empty**. Setting it at all silently downgrades panes to non-login, and they
stop reading your profile. Do not set it.

**9. A running tmux server does not re-read its config.** After editing
`~/.config/tmux/tmux.conf`, run `tmux source-file ~/.config/tmux/tmux.conf`, or
you will judge the old status line and conclude your change did not work.

**10. `new-window -t "=name:2"` fails when index 2 is in use** ("index 2 in
use"), rather than shifting. `new-window -a -t "=name:1"` inserts after window 1
and renumbers; `new-window -t "=name"` with no index appends at the next free
one. Which you want depends on whether disturbing the user's window numbering is
acceptable.

## ssh

**11. `ssh host command` gets a non-interactive, non-login shell.** It reads
only `~/.zshenv`, not `~/.zprofile` or `~/.zshrc`, so whatever exports your
package manager's PATH is skipped and `tmux`, `fzf` and `git` all look
uninstalled.

`bin/tmx` forwards through `$SHELL -lc` for exactly this reason, with two
deliberate layers of quoting: `${(q)@}` per argument for the shell that `-lc`
parses, and `${(qq)…}` around the whole string for the shell ssh itself runs.
Both are load-bearing; collapsing them breaks any argument containing a space.

`tmx-status` cannot use that trick, because tmux runs `#()` status commands
itself with no shell in between, so it sets its own PATH.

**12. `UseKeychain` is Apple-only and is a fatal parse error under other OpenSSH
builds.** If a third-party `ssh` shadows Apple's on PATH - MacPorts installs to
`/opt/local/bin/ssh`, which comes first - this single option breaks `ssh` and
`scp` **machine-wide, for every host**, not just the block it appears in.

`IgnoreUnknown UseKeychain` is not a sufficient guard: it only applies to
connections matching the block it sits in, so a raw-IP or unrelated-host
connection still aborts. Persist a passphrase once by hand instead:

```sh
/usr/bin/ssh-add --apple-use-keychain ~/.ssh/your_key
```

**13. A reserved LAN address is network-specific.** An mDNS name like
`remote.local` follows the machine between networks; a DHCP reservation exists
only on the router that granted it. Keep both, prefer the name, and expect the
address to go stale exactly when you need the fallback.

## Files and transport

**14. Neither `scp` nor `cp` gives you the executable bit.** `scp` copies the
*source* mode, and `cp` over an existing file keeps the *destination's* mode. A
non-executable `tmx-status` makes the `#(exec …)` in the status line fail
silently, and the result just looks unfinished rather than broken. Check with
`ls -la` after any install.

**15. Do not trust a viewer that renders glyphs as blank.** Nerd Font icons live
in the Unicode private use area, and plenty of editors, pipes and clipboards
drop PUA codepoints without complaining. Verify bytes, not appearance:

```sh
python3 -c 'print([hex(ord(c)) for c in open("bin/tmx-status").read() if ord(c)>126])'
```

Expect `e0b2 e0b3 f179 f07b e0a0 f126 f017 f1da`. A tmux config cannot use
`$'\u…'` escapes, so `.conf` files have to carry literal glyphs; zsh scripts can
use either.

**16. A format substituted into a `#()` status command is code, not data.**

tmux expands `#{...}` *into* the command string and hands the result to
`/bin/sh`, so any value interpolated there is shell syntax:

```tmux
# unsafe: a work dir containing an apostrophe kills the whole segment
set -g status-right "#(exec .../tmx-status right '#{@tmx_dir}' '#{session_path}')"
# safe: the only interpolated value has a controlled character set
set -g status-right "#(exec .../tmx-status right '#{session_name}')"
```

With a real attached client, `@tmx_dir=/tmp/it's` produces `sh: unexpected EOF
while looking for matching`, and the whole right-hand segment vanishes with no
error reported anywhere. Quote characters shift the arguments, so the wrong
values are displayed. A `'; command; echo '` payload does **not** execute, but
only because `exec` replaces the shell before the injected command is reached -
without the `exec` it is code execution in the tmux server every
`status-interval`.

Pass an identifier whose characters you control (here a session name, restricted
to letters, digits, `-` and `_`) and have the helper look everything else up
itself. A `#()` command inherits `$TMUX`, including the socket path, so it can
call `tmux display-message -p` back and reach the right server.

**17. `${#var}` counts characters, so it depends on the locale.**

A glyph check written as `(( ${#SEP} != 1 ))` reports 3 for an intact 3-byte
glyph whenever the tmux server has no UTF-8 locale: a login item, plain `ssh
host tmux`, `LANG` not forwarded. The status line then drops to plain text and
you go looking at a font that was never the problem. Test for what actually goes
wrong - empty, or a literal `\u` escape - instead of measuring width.

**18. Sanitising a name into a *path* can collide two different things.**

A worktree directory named from a sanitised branch name means `feat/1234` and
`feat-1234` map to one path. Adopting whatever is there puts you on the other
branch's working tree with no warning, and commits land on it. A path derived
from a lossy transform has to be verified, not trusted: check that what is there
is really a worktree, and really on the branch that was asked for.

**19. Powerline separator direction is not interchangeable.** `status-left` and
the window list are drawn left to right and need **U+E0B0** (solid, pointing
right). `status-right` is built the other way and needs **U+E0B2** / **U+E0B3**.
Using the wrong one points the chevrons backwards.
