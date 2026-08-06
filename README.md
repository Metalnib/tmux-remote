# tmx

**Remote tmux you don't have to learn.**

Your work runs on the machine with the CPU, the RAM and the repos. You drive it
from whatever you happen to be sitting at. Close the lid mid-build, walk off,
open it somewhere else and everything is still going, because none of it was ever
running on your laptop.

```sh
tmx code-api             # create or attach, on the remote, one command
tmx                      # or fuzzy-pick from a list
tmx --ai code-api        # ...with an AI agent in its own window
tmx ls -w                # what is running, per window
```

## One idea

**Session names come from the directory.** `~/code/api` is always `code-api`, and
the same command creates it or attaches to it:

```
~/code/api          ->  code-api
~/code/acme/api     ->  acme-api
~/dotfiles          ->  dotfiles          (straight off $HOME, no prefix)
~/code/my project   ->  code-my-project   (typeable, never needs quoting)
```

Everything else follows from that. Nothing to name, nothing to remember, no list
to keep tidy, and running `tmx` twice is never a mistake.

The working title was "tmux for idiots". The idiot was me: `api` on Monday,
`work-api` on Thursday, then ten minutes on Friday typing into the wrong session
wondering why my changes kept vanishing. Deriving the name from the directory
fixed that, which also made the title inaccurate.

## Which directories it offers

One file, `~/.config/tmx/projects`, says where your work is and what to call it.
A line without `=` is a **root**: its children are offered, one level deep, and the
root itself is not.

```
~            ->  dotfiles, notes         (things sitting in $HOME)
~/code       ->  code-api, code-web      (~/code itself is not offered)
```

That controls the menu, not what you may open. **Any path works, however deep,
whether or not a root covers it:**

```sh
tmx ~/code/web/frontend/admin      # fine, opens as frontend-admin
```

A name is always the last two path components, so depth never makes it longer.
Full rules, three example layouts and the one surprising rule are in
[docs/tmx-commands.md](docs/tmx-commands.md#the-roots-file).

A line **with** `=` is an **alias**, for when a derived name is not what you call
the thing:

```
webapi          = ~/code/acme/webapi
current-project = ~/code/acme/webapi
```

The alias becomes the session name. Both of those point at one directory, which is
fine: there is **one session per directory, whatever it is called**, so the alias,
the derived name and the bare path all land in the same place.

## What you get

```
$ tmx ls
SESSION      DIR              BRANCH  WT  LAST ATTACHED  UP    WINDOWS
code-api     ~/code/api       main    -   attached       3d4h  1:shell* 2:claude
acme-api     ~/code/acme/api  develop -   45m ago        6h    1:shell*
api--fix-91  ~/code/.wor...   fix/91  wt  2h ago         2d1h  1:shell* 2:codex
```

`WT` marks a git worktree session. `WINDOWS` names the agent, so you can see
which sessions have one and which agent it is.

The remote's status line carries the same information for the session you are in:
host, directory, git branch, a worktree marker, when it was last attached, and
how long it has been alive. The client and the remote use different colour
palettes on purpose, so a nested session never leaves you guessing which machine
your keystrokes are going to.

## Two machines

| | client | remote |
|---|---|---|
| what it is | a laptop, or anything you sit at | the machine with the repos |
| runs the sessions | no | yes |
| what `tmx` does | forwards itself over ssh | the actual work |
| tmux config | `tmux/client.tmux.conf` | `tmux/remote.tmux.conf` |

`tmx` is installed on both and works out which one it is, so `tmx code-api` typed
on the laptop drops you inside the remote session in a single step. No `ssh`
first.

Both ends use the standard `C-b` prefix, so nesting works and every piece of tmux
documentation you find applies as written. `C-b c` opens a window locally,
`C-b C-b c` opens one on the remote, and `F12` switches the local bindings off so
plain `C-b` goes straight through.

## Sessions and agents

| window | what is in it | when |
|---|---|---|
| 1 `shell` | a login shell in the work directory, where you land | always |
| 2 *agent* | an AI agent, same directory, window named after it | with `--ai` |

That is the whole layout. Anything else you open yourself; `tmx` has no list of
tools it starts on your behalf.

**Which agent is up to you.** An agent's command defaults to its own name, so
`tmx --ai=codex` already works if `codex` is on your `PATH`. A config line is only
needed to add arguments:

```
TMX_AI_DEFAULT=claude
TMX_AI_opencode=opencode --model local
```

Because the window is named after the agent, two different agents can share a
session, asking for the same one twice does nothing, and `--ai` works on a session
that has been running for days.

## Worktrees

One session per branch, on top of one session per repo:

```sh
cd ~/code/acme/api
tmx wt fix/91
```

You get session `acme-api--fix-91`, a worktree at
`~/code/.worktrees/api--fix-91`, and a marker in the status line so you always
know you are not in the main checkout. Run it again later and you just attach. It
works from inside another worktree too.

## Clipboard

Ordinary copies cross on their own over OSC 52. That holds until the selection
gets big, at which point escape sequences start getting truncated (twice over,
with a nested tmux in the middle). For those, `Y` in copy mode writes the
selection to a file on the remote, and `tmx clip` pulls it onto your local
clipboard. `tmx clip push` goes the other way.

## Commands

| command | does |
|---|---|
| `tmx` | fuzzy picker over live sessions and work dirs |
| `tmx <name>` | attach to that session, creating it if needed |
| `tmx <dir>` | the same, for a path |
| `tmx wt <branch> [repo]` | session for a git worktree, creating it if needed |
| `tmx ls` | sessions with dir, branch, worktree flag, times, windows |
| `tmx ls -w` | the same, expanded into a per-session window tree |
| `tmx kill <name>` \| `--all` | kill, after a confirmation |
| `tmx clip` \| `push` \| `scp` | move a large selection between machines |
| `tmx help keys` \| `cmds` | the cheatsheets, also on `prefix ?` and `prefix /` |
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
Nothing outside that list is needed to run it.

## Install

[INSTALL.md](INSTALL.md) has the steps. The shape of it: `bin/tmx` on both
machines, `bin/tmx-status` and a marker file on the remote, one tmux config each,
and `ssh/config.client` merged into the client's `~/.ssh/config`.

Then copy `config/config.example` to `~/.config/tmx/config` on both and set
`TMX_REMOTE_HOST` to your ssh host alias. For most people that is the only line
they ever touch.

If your `tmux`, `fzf` and `git` are not in `/opt/local/bin`, set
`TMX_PATH_PREPEND` as well. This matters more than it looks: `ssh host command`
gets a shell that reads only `~/.zshenv`, and tmux runs status commands with no
profile at all, so tools that are obviously on your `PATH` when you are typing can
be invisible to both.

An install script is planned, see [ROADMAP.md](ROADMAP.md).

## Docs

**Using it**

- [docs/tmux-keys.md](docs/tmux-keys.md), keybindings, written for someone new to
  tmux. Also on `prefix ?`.
- [docs/tmx-commands.md](docs/tmx-commands.md), the CLI in detail, with
  troubleshooting. Also on `prefix /`.
- [INSTALL.md](INSTALL.md), setting up both machines.

**Working on it**

- [SPEC.md](SPEC.md), the design and why it is that way.
- [docs/gotchas.md](docs/gotchas.md), measured behaviour in zsh, tmux and ssh that
  the code depends on. Worth reading before simplifying anything.
- [CHANGELOG.md](CHANGELOG.md), what changed.
- [ROADMAP.md](ROADMAP.md), what is planned.

Working on it also wants `python3`, for `bin/lint-shell-structure.py`. Running
`tmx` never does.

## Deliberately out of scope

Surviving a reboot, starting on login, and mosh. Durability here means surviving a
dropped connection, not a restart. A reboot clearing every session is intended,
not a gap.

## License

MIT, see [LICENSE](LICENSE).
