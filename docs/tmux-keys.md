# tmux keybindings - cheatsheet

Open this any time with `prefix ?`, or `tmx help keys` from a shell.

## The one idea you need first

tmux keys are never pressed alone. You press a **prefix** first, let go, then
press the actual key. Written `prefix c`, that means: press `Ctrl+b`, release,
press `c`. Two separate presses, not a chord.

The prefix is `C-b` (Control+b) - the tmux default, on **both** machines. One
set of keys to learn, and every tmux tutorial on the internet applies as
written.

You do have two tmux servers, one per machine, and the status bar tells you
which one you are looking at:

| Where | Status bar |
|---|---|
| client, local sessions | **purple**, says CLIENT |
| remote machine, your work | **blue**, says REMOTE |

Why the prefix is not "eaten" by the shell: `Ctrl+b` normally means "move back
one character" in zsh. tmux takes it, so to type a real `Ctrl+b` at a prompt you
press it twice. That same double-tap is what reaches the remote when sessions
are nested - see below.

## Vocabulary

- **server** - the background tmux process. One per machine.
- **session** - a named workspace. You get one per work directory.
- **window** - like a tab inside a session. Numbered from 1.
- **pane** - a split inside a window.
- **detach** - leave a session running and go back to your shell. Nothing is
  killed. This is what happens automatically when your ssh drops.
- **attach** - reconnect to a running session.

Closing your laptop, losing wifi, or quitting iTerm2 all just detach you. The
remote keeps everything running. A **reboot** of the remote wipes all sessions -
that is deliberate; there is no session persistence.

## Sessions

| Keys | Does |
|---|---|
| `prefix f` | fuzzy picker over sessions and work dirs - the main way in |
| `prefix S` | visual tree of every session and window, `Enter` to jump |
| `prefix d` | detach - leave everything running, back to your shell |
| `prefix $` | rename the current session |
| `prefix X` | kill the current session, after a confirmation |
| `prefix (` / `prefix )` | previous / next session |

## Windows (tabs)

| Keys | Does |
|---|---|
| `prefix c` | new window, in the same directory you were in |
| `prefix 1` … `prefix 9` | jump to window by number |
| `prefix Tab` | back to the window you were in before |
| `prefix n` / `prefix p` | next / previous window |
| `prefix ,` | rename the current window |
| `prefix &` | kill the current window, after a confirmation |
| `prefix w` | pick a window from a list |

Every new session starts with one window:

1. `shell` - a plain zsh in the work directory. You land here.

If you started it with `tmx --ai`, there is a second window named after the AI
agent, running that agent in the same directory. Quitting the agent closes its
window; nothing recreates it for you. `tmx --ai <session>` adds it back, and you
can also just open a window yourself with `prefix c`.

## Panes (splits)

| Keys | Does |
|---|---|
| `prefix \|` | split left/right - the key looks like the divider you get |
| `prefix -` | split top/bottom |
| `prefix ←↓↑→` | move to the pane in that direction |
| `prefix Shift+←↓↑→` | resize the current pane by 5 cells, repeatable |
| `prefix ;` | back to the pane you were in before |
| `prefix z` | zoom the current pane to fill the window; press again to undo |
| `prefix x` | kill the current pane, after a confirmation |
| `prefix !` | pop the current pane out into its own window |
| `prefix Space` | cycle through the built-in layouts |
| `prefix q` | flash pane numbers; press a number to jump there |

New panes and windows always open in the current pane's directory, so a split
inside `~/code/globex/mono` starts there too.

## Copy and paste

The mouse works: scroll to look back through history, click a pane to focus it,
drag a border to resize.

| Keys | Does |
|---|---|
| drag with the mouse | select, and copy on release |
| `prefix [` | enter copy mode to select with the keyboard |
| `v` then movement | start a selection (copy mode, vi keys) |
| `y` | copy the selection and leave copy mode |
| `q` or `Escape` | leave copy mode without copying |
| `prefix ]` | paste the last thing tmux copied |
| `prefix =` | list previous copy buffers and paste one |
| `Y` | save a big selection to a file - see below (copy mode, remote) |
| `prefix P` | paste what `tmx clip push` sent from the laptop (remote) |
| `/` then text | search backwards through the scrollback (copy mode) |
| `n` / `N` | next / previous search hit |

Copies made in the **remote** tmux land in the **client's** clipboard, over ssh,
via an escape sequence called OSC 52. If ⌘V pastes something stale, check iTerm2
→ Settings → General → Selection → "Applications in terminal may access
clipboard".

Pasting the other way - ⌘V into a remote pane - always works and needs no setup,
because iTerm2 is just typing the characters in. Two things follow from that:
multiple lines pasted at a shell prompt will *run*, and a big paste is slow.

### Big selections

OSC 52 is an escape sequence, and escape sequences get truncated once the
payload is large - twice over when a local tmux sits in the middle. So there is
a file bridge for anything sizeable:

| Step | Where | Keys / command |
|---|---|---|
| remote → laptop | remote, in copy mode | select, then `Y` |
| | client, any shell | `tmx clip` |
| laptop → remote | client, any shell | `tmx clip push` |
| | remote | `prefix P` |

`Y` writes the selection to `~/.cache/tmx/clip.txt` on the remote and tells you
how big it was. `tmx clip` on the laptop fetches that over ssh straight onto
your clipboard. `tmx clip scp` prints the raw `scp` line if you want the file
itself rather than the clipboard.

Use plain `y` for ordinary copies - it is one keystroke and needs nothing on the
other end. Reach for `Y` when `y` gives you a truncated paste.

Both machines are Macs, so **Universal Clipboard** is also there if Handoff is
on: `pbcopy < file` on the remote, ⌘V on the laptop, no size ceiling at all.

## Popups

| Keys | Does |
|---|---|
| `prefix ?` | this page |
| `prefix /` | the `tmx` command cheatsheet |
| `prefix g` | a throwaway shell in the current directory |
| `prefix f` | the session / work dir picker |

Popups float over your session. `q` closes the doc pages; `exit` or `C-d` closes
the shell.

## Housekeeping

| Keys | Does |
|---|---|
| `prefix r` | reload `~/.config/tmux/tmux.conf` |
| `prefix :` | tmux command prompt, for anything not bound to a key |
| `prefix t` | big clock, for no good reason |
| `F12` (client only) | turn the local server's keys off - see nesting, below |

## Nested sessions: local tmux wrapping a remote one

If you attach to a remote session from inside a session on the laptop, you have
two tmux servers stacked, both answering to `C-b`. The **outer** one - the
laptop's - sees it first. So a plain `prefix c` makes a window on the *laptop*,
not on the remote.

Two ways through:

| Keys | Goes to |
|---|---|
| `C-b c` | the laptop (outer) |
| `C-b C-b c` | the remote (inner) - the second `C-b` is forwarded |
| `F12` then `C-b c` | the remote, until you press `F12` again |

`C-b C-b` is the one to learn: double-tap the prefix, then the key. It works for
every binding, so `C-b C-b d` detaches the remote session, `C-b C-b |` splits
the remote pane.

`F12` is the alternative if you are about to do a lot of remote work and would
rather not count keypresses. Press it and the laptop's tmux stops reacting to
`C-b` altogether, goes grey and says "keys off", so plain `C-b` lands on the
remote. Press `F12` again to take the laptop back. It only exists on the client
- there is nothing to disable on the remote.

`prefix f` on the laptop opens each remote session in its own local window, so
one local window is one remote session and it stays obvious what is nested in
what.

## Both screens at once

The remote's own display and your client can be attached to the same session at
the same time, showing the same window, sharing the keyboard. Whatever you type
on one appears on the other.

While both are attached, the window is sized to the **smaller** of the two
terminals. Nothing is hidden or cut off; the bigger display just shows unused
space around the edge. Detach the smaller client and the window grows back.

## When something looks stuck

- **Frozen after a scroll** - you are in copy mode. Press `q`.
- **A key acted on the wrong machine** - you are nested. The purple bar took it.
  Use `C-b C-b <key>`, or press `F12` to hand the keyboard to the remote.
- **Keys doing nothing** - check whether the status bar says "keys off" (press
  `F12`), and check which bar you are actually looking at.
- **`sessions should be nested with care`** - you tried to attach to a tmux from
  inside *the same* server. Use `prefix f` or `tmx <name>`, which switch rather
  than nest. Attaching to the *remote's* server from a laptop session is fine
  and does not produce this.
- **Status bar looks like boxes and question marks** - the terminal is not using
  a Nerd Font. Fix the font, or set `TMX_GLYPHS=0` for plain-text labels.
- **Right side of the status bar briefly says `not ready`** - normal. tmux is
  waiting for the first run of the script that fills it in. It settles by
  itself.
- **Really stuck** - `prefix d` to detach, then `tmx <name>` to come back. The
  session and everything in it survives.
