# `tmx` - cheatsheet

Open this any time with `prefix /`, or `tmx help cmds` from a shell.

## What it is

`tmx` gives you one tmux session per work directory on the remote machine. The
session name comes from the directory, and the same directory always produces
the same name. So you never have to remember whether a session exists: `tmx`
creates it or attaches to it as needed.

Installed on **both** machines. On the client it forwards itself over ssh, so
`tmx code-api` typed on the laptop lands you inside the remote session in one
step - no separate `ssh remote-box` first.

## Commands

| Command | Does |
|---|---|
| `tmx` | fuzzy picker over live sessions and work dirs |
| `tmx <name>` | attach to that session, creating it if needed |
| `tmx <dir>` | same, for a path - `tmx ~/code/api`, `tmx .` |
| `tmx wt <branch>` | session for a git worktree, creating the worktree if needed |
| `tmx wt <branch> <repo>` | same, naming the repo explicitly |
| `tmx ls` | table of sessions: dir, branch, worktree flag, times, windows |
| `tmx ls -w` | same, expanded into a tree with what each window is running |
| `tmx kill <name>` | kill one session, after a confirmation |
| `tmx kill --all` | kill the whole tmux server, after a confirmation |
| `tmx clip` | pull a big selection saved on the remote onto this clipboard |
| `tmx clip push` | push this clipboard to the remote |
| `tmx clip scp` | print the `scp` line for the saved selection |
| `tmx help keys` | the tmux keybindings cheatsheet |
| `tmx help cmds` | this page |
| `--ai` \| `--ai=<agent>` | add a window running an AI agent (see below) |

## Session names

The rule: **parent directory name, dash, directory name.** Case is kept as it is
on disk. Spaces and punctuation become dashes, so the name is always something
you can type without quoting. `-` and `_` are kept, and letters are kept in any
alphabet.

| Directory | Session |
|---|---|
| `~/code/api` | `code-api` |
| `~/oss/api` | `oss-api` |
| `~/code/acme/api` | `acme-api` |
| `~/code/globex/mono` | `globex-mono` |
| `~/dotfiles` | `dotfiles` |
| `~/code/my project` | `code-my-project` |
| `~/archive (2024)` | `archive-2024` |
| `~/code/my_repo` | `code-my_repo` |

The parent prefix is what keeps `~/code/api` and `~/oss/api` apart. Directories
sitting directly in your home folder skip the prefix, since `youruser-dotfiles`
would just be noise.

If a name is already taken by a session pointing at a *different* directory,
`tmx` stops and prints both paths rather than dropping you into the wrong place.

## Worktree sessions

One session per branch, on top of one session per repo.

```
cd ~/code/globex/mono
tmx wt feat/1234
```

That gives you:

- session `globex-mono--feat-1234`
- worktree at `~/code/.worktrees/mono--feat-1234`
- a `shell` window rooted in the worktree, plus an agent window if you passed
  `--ai`
- a worktree marker in the status line, so you can tell at a glance that you are
  not in the main checkout

If the branch already exists, `tmx` checks it out. If it does not, `tmx` creates it.
Run the same command again later and you just attach - the worktree is reused.
Works from inside another worktree too; `tmx` finds the main repo either way.

Removing a worktree is still a git job: `tmx kill <name>` then `git worktree
remove <path>`.

## What a new session contains

| Window | Contents | When |
|---|---|---|
| 1 `shell` | plain zsh in the work directory - you land here | always |
| 2 *agent* | an AI agent, same directory, window named after it | only with `--ai` |

Anything that is not an agent - a database client, a log tail, a bare ssh - you
open by hand with `prefix c` or a split. New windows and panes inherit the
current directory.

## `--ai`: an AI agent in its own window

Sessions are shell-only by default. `--ai` adds a window running an agent:

```sh
tmx --ai code-api           # new session: window 1 shell, window 2 your default agent
tmx --ai=codex code-api     # ...a specific agent instead
tmx code-api                # no agent, just a shell
```

The flag goes anywhere, so `tmx code-api --ai` is the same thing. It works with
the picker (`tmx --ai`, then choose) and with worktrees (`tmx wt --ai
feat/1234`). Typed on the client it is forwarded to the remote like everything
else.

### Choosing the agent

**An agent's command defaults to its own name.** So `tmx --ai=codex` already
works if `codex` is on your PATH - there is nothing to configure. You only need
a line in `~/.config/tmx/config` to add arguments or point at a different
binary:

```
TMX_AI_DEFAULT=claude                     # what plain --ai runs
TMX_AI_opencode=opencode --model local    # arguments are preserved
TMX_AI_aider=aider --no-auto-commits
```

Agent names are letters, digits and underscore, because the name is also used as
the tmux window name.

If the agent is not found, `tmx` warns but still opens the window. The window runs
through a login shell, and its PATH is wider than `tmx`'s own, so the agent may
work anyway. If the window vanishes immediately, that warning was right.

### Adding one later

On a session that is **already running**, `--ai` adds the window rather than
doing nothing:

```sh
tmx code-api                # working away, shell only
tmx --ai code-api           # decided you want an agent; the window appears
tmx --ai=codex code-api     # and a second, different agent alongside
```

Details worth knowing:

- **The window is named after the agent**, so `tmx ls` tells you which one is in
  there, and two different agents can share a session.
- Asking for the **same** agent twice never gives you two windows.
- You stay on your shell window. Adding an agent does not move you.
- The window goes to index 2 when that index is free. If you already made a
  window 2 yourself, the agent window goes to the end instead, so your windows
  keep their numbers.
- The shell and the agent always share one working directory. There is no way
  for them to end up in different places.
- Quitting the agent closes its window and `tmx` does not bring it back. Run
  `tmx --ai <name>` again if you want it.

Apart from adding an agent window on request, `tmx` never restructures a
session, so it is safe to run on a session you have rearranged.

## The picker

Run `tmx` with no arguments, or press `prefix f`.

```
  globex-mono                 ~/code/globex/mono           attached
  acme-api                    ~/code/acme/api              2h14m ago
  code-scripts                ~/code/scripts               3d1h ago
  code-notes                  ~/code/notes
```

Live sessions come first, each with its last-attached time; then work dirs that
have no session yet. Type to filter, `Enter` to open, `Esc` to cancel. The
preview pane on the right shows the session's windows, or the directory's git
status and recent commits.

The first two lines above are live sessions that were opened by path. That is why
they appear even though they sit two levels below a root. Only the bottom group is
limited by your roots.

## The projects file

`~/.config/tmx/projects` answers two questions: which directories the picker
offers, and what you want them called. It is the one file you will keep coming
back to, so it is worth understanding properly.

There are exactly two kinds of line:

```
~/code                       a ROOT.  No "=".  Its children are offered.
webapi = ~/code/acme/webapi  an ALIAS. Has "=". Names one directory.
```

Blank lines and `#` comments are ignored. A leading `~` is expanded. If the text
before the `=` looks like a path, the line is read as a root, so a directory whose
name contains `=` still works.

### What a root is

**A root is a container. Its children are offered; the root itself is not, and
nothing deeper than one level is.**

Given this on disk:

```
~/code
  api
  web
    frontend
```

then a projects file containing just `~/code` offers:

```
code-api     ->  ~/code/api
code-web     ->  ~/code/web
```

`~/code` itself is not on the menu, and `frontend` is a level too deep to appear.
That is not a restriction on what you can open, only on what you are shown:

```sh
tmx ~/code/web/frontend      # works, opens as web-frontend
```

So roots shape the menu. Typing a path always wins.

### Two rules that keep the list short

**Blocklist.** `Library`, `Applications`, `Desktop`, `Downloads`, `Documents`,
`Music`, `Movies`, `Pictures`, `Public`, `Sites`, and anything starting with a
dot, are never offered. This is what makes a bare `~` usable as a root.

**Deeper root wins.** A directory that is itself listed as a root disappears from
its parent's listing. This is the rule that surprises people:

| projects file | offered |
|---|---|
| `~` | `code`, `dotfiles`, `notes`, ... |
| `~`<br>`~/code` | `dotfiles`, `notes`, then `code-api`, `code-web`. **`code` is gone** |

It applies at every level. Adding `~/code/acme` as a root gains you `acme-api` and
`acme-web`, and costs you `code-acme`, because `acme` is no longer offered by
`~/code`. That is a trade, not an improvement. Add a container as a root only when you work
inside its children, not in the container itself.

### Three layouts

Everything loose in one folder:

```
~/src              ->  src-api, src-web, src-notes
```

Grouped by client or org, and you work in the groups:

```
~/code             ->  code-acme, code-globex
```

Grouped, but you always work one level deeper:

```
~/code             ->  acme-api, acme-web, globex-mono
~/code/acme            (note: code-acme and code-globex are no longer offered)
~/code/globex
```

Repos sitting directly in your home directory:

```
~                  ->  dotfiles, notes      (no prefix, straight off $HOME)
```

### Checking a change

Nothing needs restarting, the file is read on every run. To see the effect, open
the picker with `tmx` and look at the lower group, which is work dirs with no
session yet. `tmx a-name-that-does-not-exist` also prints the names it knows,
although that list is truncated.

Paths that do not exist are skipped silently, so it is safe to keep lines for a
machine you are not on right now.

## Short names, and how deep you can go

**Any path works, at any depth, root or no root:**

```sh
tmx ~/code/acme/services/billing/api     # opens, as session billing-api
```

A session name is always **the last two path components**, so a deep path does not
give you a long name. The downside: two directories sharing their last two
components want the same name. `tmx` notices and refuses, as above.

There are four ways to open a session:

| you type | works when | you get |
|---|---|---|
| `tmx code-api` | always | the session name itself |
| `tmx api` | the directory is one level under a root | session `code-api` |
| `tmx ~/deep/path` | always | session from the last two components |
| `tmx current-project` | an alias is defined for it | a session named `current-project` |

`tmx api` is the useful one day to day: **the bare directory name is enough** as
long as a root covers it. It finds `~/code/api` and opens `code-api`.

For anything a root does not cover, give it a name of your own; see below.

### Aliases: your own short name

For anything a root does not reach, or when the derived name is just not what you
call the thing, add an alias line to the same file:

```
webapi          = ~/code/acme/webapi
current-project = ~/code/acme/webapi
```

**The alias becomes the session name.** `tmx current-project` opens a session
called `current-project`, not `acme-webapi`, so that is what you see in `tmx ls`.

Two aliases pointing at one directory is fine, and so is mixing them with the path:

```
tmx current-project        # creates it
tmx webapi                 # tmx: ~/code/acme/webapi is already open as 'current-project'
tmx ~/code/acme/webapi      # same, attaches to current-project
```

That is the rule underneath: **one session per directory, whatever it is called.**
Whichever name you use first wins, and every other route attaches to it and tells
you the name it found.

Names may use letters, digits, `-` and `_` only, since a name has to work as a
tmux session name. Anything else is skipped with a warning. An alias also beats a
same-named live session, so an alias always means its directory.

### Renaming a session by hand

`tmux rename-session` works, and reopening the directory finds the renamed session
rather than making a second one. But the new name lives only as long as the
session: kill it and you are back to the derived name. An alias is the durable
version of the same idea, so prefer that.

## Reading `tmx ls`

```
SESSION                 DIR                  BRANCH     WT  LAST ATTACHED  UP     WINDOWS
globex-mono             ~/code/globex/mono   main       -   attached       3d4h   1:shell* 2:claude 3:logs
globex-mono--feat-1234  ~/code/.worktrees/…  feat/1234  wt  2h14m ago      2d1h   1:shell* 2:codex
acme-api                ~/code/acme/api      develop    -   45m ago        6h30m  1:shell*
```

`tmx kill --all` kills the tmux **server**, not just the sessions listed above
it. Anything created between the listing and your `y`, and any session not made
by `tmx`, goes with it.

`WT` marks a worktree session. `UP` is how long the session has existed, which
is effectively how long since the remote last rebooted, if you never kill
anything.

`WINDOWS` lists every window as `index:name`, with `*` on the one that is
currently selected. Since agent windows are named after the agent, it is also
the quick way to see which sessions have one running, and which agent it is.

### `tmx ls -w`

For what is actually running in each window, `tmx ls -w` (or `--windows`) turns
each session into a small block:

```
SESSION      DIR                  BRANCH   WT  LAST ATTACHED  UP
globex-mono  ~/code/globex/mono   main     -   attached       3d4h
  1 shell *  zsh
  2 claude   claude
  3 logs     journalctl

acme-api     ~/code/acme/api      develop  -   45m ago        6h30m
  1 shell *  zsh
```

The third column on a window line is the foreground command in that window's
pane.

Note that quitting an agent does not leave its window sitting there with a shell
in it. The window runs `zsh -lc <agent>`, so when the agent exits the shell
exits too and the window closes. It simply disappears from the list.

## Moving big text between the machines

Ordinary copies cross by themselves: select in the remote tmux and it lands on
the client's clipboard over ssh, via OSC 52. That stops working for large
selections: escape sequences get truncated, and a local tmux in the middle adds a
second limit.

`tmx clip` is the file bridge for those cases.

**remote → client.** In copy mode on the remote, select and press `Y` instead of
`y`. That writes the selection to `~/.cache/tmx/clip.txt` and flashes the size.
Then on the laptop:

```sh
tmx clip                 # fetches it over ssh, straight onto your clipboard
tmx clip scp             # or print the scp line, to get the file itself
```

**client → remote.** For pasting something large into a remote pane, where ⌘V
would type it in character by character:

```sh
tmx clip push            # sends this clipboard to the remote
```

Then `prefix P` on the remote pastes it into the current pane.

`tmx clip` with no argument on the remote itself just reports what is currently
in the file and how big it is.

Both machines are Macs, so **Universal Clipboard** is a third route if Handoff
is on: `pbcopy < file` on the remote, ⌘V on the laptop, no size limit. And for
real files, `scp` or `rsync` rather than any of this.

## Attaching from two places

The remote's own screen and your client can both be attached to the same session
at once - same window, shared keyboard. `tmx` never passes tmux's `-d` flag, so
attaching from the laptop will not kick the remote's display off.

## Durability

Sessions survive: closing the laptop, wifi dropping, quitting iTerm2, `prefix
d`.

Sessions do not survive: rebooting the remote. There is no resurrect plugin and
nothing starts at login - by design. After a reboot you rebuild with a few `tmx`
calls, or one pass through the picker.

## Environment variables

Nothing needs setting; these exist for when something is wrong.

| Variable | Default | Purpose |
|---|---|---|
| `TMX_REMOTE_HOST` | `remote-box` | ssh host alias to forward to |
| `TMX_REMOTE_NAME` | `remote-box` | the remote's own hostname, not the ssh alias above |
| `TMX_ROLE` | - | set to `remote` to force remote behaviour |
| `TMX_AI_DEFAULT` | `claude` | which agent plain `--ai` runs |
| `TMX_AI_<agent>` | the agent's own name | command line for that agent |
| `TMX_PROJECTS_FILE` | `~/.config/tmx/projects` | roots and aliases |
| `TMX_WORKTREE_DIRNAME` | `.worktrees` | where worktrees are created |
| `TMX_GLYPHS` | `1` | set to `0` for a plain-text status line |
| `TMX_CLIP_FILE` | `~/.cache/tmx/clip.txt` | where `Y` saves a big selection |

If mDNS is unreliable, `TMX_REMOTE_HOST=remote-box-ip tmx …` goes straight
to the remote's reserved IP. Note that address is per-network - if you have
changed location, `~/.ssh/config` may need updating before the fallback works.

## Troubleshooting

### The status line shows boxes or question marks

The glyphs are sent correctly; the font in **this** terminal has no Nerd
Font coverage. Check it:

```sh
printf '\ue0b0 \ue0b2 \ue0b3 \ue0a0 \uf179 \uf07b \uf126 \uf017 \uf1da\n'
```

You should see nine icons: two solid arrows, a thin arrow, a branch, an apple, a
folder, a fork, a clock and a history arrow. Boxes, question marks or blank
space mean that font has no Nerd Font glyphs, and the status line shows the same
boxes. Run the check **in the terminal you actually use**, and on **both**
machines, since the remote's own screen renders the same status line.

Fix it by selecting a Nerd Font in the terminal's profile, or set `TMX_GLYPHS=0`
in `~/.config/tmx/config` for plain-text labels. Installing the font on the other
machine does not help: the terminal you are looking at has to render it.

**`tmx` on the laptop hangs, then times out.** The remote is not reachable by
name. Try `TMX_REMOTE_HOST=remote-box-ip tmx ls`.

**`tmx` on the remote tries to ssh to itself.** Role detection failed. Check
that `~/.config/tmx/remote` exists; `touch` it if not.

**`tmux not found` / `git not found` even though they are installed.** A `PATH`
problem, not a missing package. Plain `ssh host command` runs a non-interactive,
non-login zsh that reads only `~/.zshenv`. So MacPorts' `/opt/local/bin` (usually
exported from `~/.zprofile` or `~/.zshrc`) is absent. `tmx` forwards
itself through `$SHELL -lc` to avoid this, so if you still see it, the copy on
the remote is out of date. Compare:

```sh
ssh remote-box 'echo $PATH'                  # the thin one
ssh remote-box '$SHELL -lc "echo \$PATH"'    # what tmx actually uses now
```

Not strictly needed, but worth doing anyway, since `~/.zshenv` is the only zsh
startup file read by *every* shell:

```sh
echo 'export PATH="/opt/local/bin:/opt/local/sbin:$HOME/.local/bin:$PATH"' >> ~/.zshenv
```

Your panes are unaffected either way - tmux starts them as interactive login
shells, so they read `~/.zprofile` and `~/.zshrc` and have your full
environment.

**`nothing to pick`.** `~/.config/tmx/projects` is missing, empty, or lists paths
that do not exist.

**`session name '…' is already taken`.** Two directories produced the same
session name. The message prints both paths. Attach to the existing one by name,
or rename a directory.

**The status bar's right side says `not ready` for a moment after attaching.**
Expected. tmux prints that placeholder until `tmx-status` has run once. If it
never resolves, run the command by hand to see the error:
`~/.local/bin/tmx-status right <a-live-session-name>` (it asks tmux for the
rest)

**`sessions should be nested with care`.** Something tried to attach to tmux
from inside tmux. `tmx` switches the client instead of nesting, so use `tmx
<name>` or `prefix f` rather than a raw `tmux attach`.
