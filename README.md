# tmx

**Remote tmux you don't have to learn.**

Your work runs on the machine with the CPU, the RAM and the repos. You drive it
from whatever you happen to be sitting at. Close the lid mid-build, walk off, open
it somewhere else and everything is still going, because none of it was ever
running on your laptop.

You need two machines and ssh between them. Everything else is one command:

```sh
tmx code-api          # start or resume work on ~/code/api, over there
```

---

## Quick start

Two machines. The **remote** is the one with your repos; the **client** is whatever
you sit at. [INSTALL.md](INSTALL.md) is the same thing with the reasons attached.

**1. On the remote:**

```sh
git clone https://github.com/Metalnib/tmux-remote ~/tmux-remote
mkdir -p ~/.local/bin ~/.config/tmx/docs ~/.config/tmux

cp ~/tmux-remote/bin/tmx ~/tmux-remote/bin/tmx-status ~/.local/bin/
chmod +x ~/.local/bin/tmx ~/.local/bin/tmx-status

cp ~/tmux-remote/tmux/remote.tmux.conf ~/.config/tmux/tmux.conf
cp ~/tmux-remote/config/config.example ~/.config/tmx/config
cp ~/tmux-remote/config/projects       ~/.config/tmx/projects
cp ~/tmux-remote/docs/*.md             ~/.config/tmx/docs/

touch ~/.config/tmx/remote     # says "this machine does the work"
```

**2. On the client**, three things. No `tmx-status`, no docs, no projects file:
this machine only forwards over ssh, so the remote answers everything.

```sh
git clone https://github.com/Metalnib/tmux-remote ~/tmux-remote
mkdir -p ~/.local/bin ~/.config/tmux

cp ~/tmux-remote/bin/tmx ~/.local/bin/ && chmod +x ~/.local/bin/tmx
cp ~/tmux-remote/tmux/client.tmux.conf ~/.config/tmux/tmux.conf
cp ~/tmux-remote/config/config.example ~/.config/tmx/config
```

**3. On both**, edit one line in `~/.config/tmx/config`:

```
TMX_REMOTE_HOST=my-remote     # the ssh host alias for the remote machine
```

**4. Check it:**

```sh
tmx version     # prints both machines and says "in sync"
```

Two ways it usually goes wrong. If it cannot reach the remote, ssh is the problem
rather than `tmx`, so get `ssh my-remote` working first. If it says `tmux not
found` even though tmux is installed, set `TMX_PATH_PREPEND` in your config file:
`ssh host command` gets a shell that reads almost none of your profile, so tools
on your normal `PATH` can be invisible to it.

An install script that does all of this is the top item on
[ROADMAP.md](ROADMAP.md).

---

## Your first five minutes

**Start working on a directory.** The remote has `~/code/api`, so:

```sh
tmx code-api
```

You are now in a shell on the remote, in that directory, with a status bar along
the bottom. Nothing else happened: no window layout to learn, no menu.

**Step away on purpose.** Press `Ctrl-b` then `d` (for detach). You are back on
your own machine. Everything you left running keeps running.

**Come back.** Same command as before:

```sh
tmx code-api
```

That is the whole loop. `tmx <name>` starts it if it is not running and resumes it
if it is, so you never have to remember which.

**Now close your laptop mid-command and open it later.** Run `tmx code-api` again.
Your command finished while you were away. That is the point of the whole thing.

**See what you have running:**

```sh
tmx ls
```

**Forgotten the name?** Run `tmx` with no arguments and pick from the list.

### Four tmux words you will meet

You do not need to learn tmux, but these four words appear on screen:

| word | means |
|---|---|
| session | one running workspace, one per directory here |
| window | a tab inside a session. `Ctrl-b c` makes one, `Ctrl-b n` next |
| detach | step away and leave it running. `Ctrl-b d` |
| prefix | the `Ctrl-b` you press before a tmux key |

`Ctrl-b ?` shows the keys, `Ctrl-b /` shows the `tmx` commands. Both open inside
tmux, so you never have to leave to look something up.
[docs/tmux-keys.md](docs/tmux-keys.md) is the same thing written for someone who
has never used tmux.

---

## The three commands you actually use

| command | does |
|---|---|
| `tmx <name>` | start or resume work on that directory |
| `tmx` | pick from a list, if you forgot the name |
| `tmx ls` | what is running, where, and on which branch |

Everything below is optional.

---

## How names work

**Session names come from the directory.** `~/code/api` is always `code-api`, so
one command creates it or resumes it and there is nothing to remember:

```
~/code/api          ->  code-api
~/code/acme/api     ->  acme-api
~/dotfiles          ->  dotfiles          (straight off $HOME, no prefix)
~/code/my project   ->  code-my-project   (typeable, never needs quoting)
```

A name is always the last two path components, so a deep path does not get a long
name. **Any path works, at any depth:**

```sh
tmx ~/code/acme/services/billing/api      # opens as billing-api
```

The working title of all this was "tmux for idiots". The idiot was me: `api` on
Monday, `work-api` on Thursday, then ten minutes on Friday typing into the wrong
session wondering why my changes kept vanishing. Deriving the name from the
directory fixed that, which also made the title inaccurate.

## Making the list your own

One file, `~/.config/tmx/projects`, decides what the picker offers and what things
are called. Two kinds of line:

```
~/code                        a ROOT.  Its children are offered, one level deep.

webapi = ~/code/acme/webapi   an ALIAS. Gives one directory a name you choose.
```

An alias becomes the session name, so `tmx webapi` opens a session called
`webapi`. There is **one session per directory whatever it is called**, so an
alias, the derived name and a bare path all land in the same place.

The file documents itself, and [docs/tmx-commands.md](docs/tmx-commands.md) has
worked examples for three common layouts.

## What else it does

**An AI agent in its own window**, if you ask for one:

```sh
tmx --ai code-api          # your default agent alongside the shell
tmx --ai=codex code-api    # a specific one
```

The agent's command defaults to its own name, so `--ai=codex` needs no
configuration if `codex` is on your `PATH`. The window is named after the agent,
so `tmx ls` shows which is running, and `--ai` also works on a session that has
been going for days.

**A session per branch**, using git worktrees:

```sh
cd ~/code/acme/api && tmx wt fix/91     # session acme-api--fix-91
```

**Big copy-paste between the machines.** Ordinary copies cross by themselves over
OSC 52. When a selection is too big for that, `Y` in copy mode writes it to a file
on the remote and `tmx clip` pulls it onto your local clipboard.

**A status line** showing host, directory, git branch, a worktree marker, when it
was last attached and how long it has been alive:

```
$ tmx ls
SESSION      DIR              BRANCH  WT  LAST ATTACHED  UP    WINDOWS
code-api     ~/code/api       main    -   attached       3d4h  1:shell* 2:claude
acme-api     ~/code/acme/api  develop -   45m ago        6h    1:shell*
api--fix-91  ~/code/.wor...   fix/91  wt  2h ago         2d1h  1:shell* 2:codex
```

The client and the remote use different colour palettes on purpose, so when one
tmux is running inside another you always know which machine your keystrokes are
going to. `F12` on the client hands the whole keyboard to the remote, and again
takes it back.

## Two machines

| | client | remote |
|---|---|---|
| what it is | a laptop, or anything you sit at | the machine with the repos |
| runs the sessions | no | yes |
| what `tmx` does | forwards itself over ssh | the actual work |
| tmux config | `tmux/client.tmux.conf` | `tmux/remote.tmux.conf` |

`tmx` is installed on both and works out which one it is, so `tmx code-api` typed
on the laptop drops you inside the remote session in one step. No `ssh` first.

## All commands

| command | does |
|---|---|
| `tmx` | picker over live sessions and work dirs |
| `tmx <name>` | start or resume that session |
| `tmx <dir>` | the same, for a path |
| `tmx wt <branch> [repo]` | session for a git worktree, creating it if needed |
| `tmx ls` | sessions with dir, branch, worktree flag, times, windows |
| `tmx ls -w` | expanded into a per-session window tree |
| `tmx kill <name>` \| `--all` | kill, after a confirmation |
| `tmx clip` \| `push` \| `scp` | move a large selection between machines |
| `tmx help keys` \| `cmds` | the cheatsheets, also on `Ctrl-b ?` and `Ctrl-b /` |
| `tmx version` | this copy and the remote's, and whether they match |
| `--ai` \| `--ai=<agent>` | add an agent window, anywhere in the arguments |

## Requirements

- Two machines, and key-based ssh from the client to the remote. Anywhere ssh
  reaches, this reaches: a LAN, a VPN, a public address, through a jump host. The
  shipped `ssh/config.client` is written for a LAN because that is what it was
  tested on, so edit it for your route.
- `tmux` 3.2 or newer, plus `fzf`, `git` and `zsh` on both machines. Built and
  tested against tmux 3.6a and 3.7b, zsh 5.9, macOS 15.
- A Nerd Font in your terminal if you want the status line icons. Without one,
  `TMX_GLYPHS=0` gives plain text labels instead.

Nothing is installed for you and nothing runs as a daemon. `tmx` is one zsh
script, `tmx-status` is another, and the rest is tmux config you can read.

## Docs

**Using it**

- [docs/tmux-keys.md](docs/tmux-keys.md), tmux keys for someone new to tmux. Also
  on `Ctrl-b ?`.
- [docs/tmx-commands.md](docs/tmx-commands.md), every command in detail, plus
  troubleshooting. Also on `Ctrl-b /`.
- [INSTALL.md](INSTALL.md), the long-form install with the reasons.

**Working on it**

- [SPEC.md](SPEC.md), the design and why it is that way.
- [docs/gotchas.md](docs/gotchas.md), measured behaviour in zsh, tmux and ssh that
  the code depends on. Worth reading before simplifying anything.
- [CHANGELOG.md](CHANGELOG.md), what changed.
- [ROADMAP.md](ROADMAP.md), what is planned. An install script is near the top.

Working on it also wants `python3`, for `bin/lint-shell-structure.py`. Running
`tmx` never does.

## Deliberately out of scope

Surviving a reboot, starting on login, and mosh. Durability here means surviving a
dropped connection, not a restart. A reboot clearing every session is intended,
not a gap.

## License

MIT, see [LICENSE](LICENSE).
