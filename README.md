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

## Install

Two machines. The **remote** holds your repos and runs everything; the **client**
is the one you sit at. `tmx` goes on both and detects which is which.

### Step 1: teach ssh how to reach the remote

Everything else depends on this, so get it working first. All of it on the
**client**:

```sh
git clone https://github.com/Metalnib/tmux-remote ~/tmux-remote
cd ~/tmux-remote

# a key just for this hop, kept apart from your other keys.
# press enter twice for no passphrase, or set one, either is fine.
ssh-keygen -t ed25519 -f ~/.ssh/client_to_remote_ed25519

# ssh reuses one connection for speed and keeps the socket here.
# it will not create this directory itself.
mkdir -p ~/.ssh/cm && chmod 700 ~/.ssh ~/.ssh/cm

# gives your remote machine the nickname "remote-box"
cat ssh/config.client >> ~/.ssh/config && chmod 600 ~/.ssh/config
```

You now have a nickname: **`remote-box`**. It lives in `~/.ssh/config` and it
means "that machine over there". It is not a folder, and not the machine's real
hostname. It is the word you hand to `ssh`, and later to `tmx`, so it is worth
knowing what it is before you type it ten times.

Two lines in it are still wrong. Both are marked `# EDIT ME` in the part you just
appended, so open `~/.ssh/config` and fix them:

| line | put |
|---|---|
| `User`, in block 1 | your username on the remote |
| `HostName`, in block 2 | the remote's address, like `bigbox.local` or `192.168.1.10` |

Now put your new key on the remote. The first connection asks you to confirm the
remote's fingerprint (answer `yes`). Then it asks for the remote's **password**
(this is the last time it will ask):

```sh
ssh-copy-id -i ~/.ssh/client_to_remote_ed25519.pub remote-box
```

No `ssh-copy-id` on your machine? Append the contents of
`~/.ssh/client_to_remote_ed25519.pub` to `~/.ssh/authorized_keys` on the remote by
hand. Use `>>` and not `>`, or you throw away any key already trusted there.

The test that matters:

```sh
ssh remote-box     # must log you in WITHOUT asking for a password
```

Still asking? Fix that before going on, nothing below works without it. On the
remote, `~/.ssh` must be `chmod 700` and `~/.ssh/authorized_keys` `chmod 600`,
and on macOS the remote needs System Settings > General > Sharing >
**Remote Login** switched on.

You will type `remote-box` in every command below. Keep the name and there is
nothing more to configure. Rename it in `~/.ssh/config` if you prefer, and type your own word
wherever you see `remote-box`.

### Step 2: put tmx on both machines

Two routes to the identical result. Pick one, you do not need both:

- **the installer**, one command, and it checks the things you would forget
- **by hand**, a dozen `cp` lines, and you see exactly what lands where

#### Option 1: let the installer do it

```sh
./install.sh --both --remote-host=remote-box
```

`--remote-host` wants the nickname from Step 1: the exact word that makes
`ssh remote-box` work. Anything ssh understands is fine, so if you skipped the
config file, `--remote-host=youruser@192.168.1.10` works just as well.

That is the whole install. It sets up the client here and copies the repo over.
It installs the remote half through ssh, records the nickname so plain `tmx` knows
where to go, and proves the round trip at the end. It names anything missing
instead of failing halfway, backs up what it replaces, and does not touch a config
you have edited. The only file it touches outside its own config directory is
`~/.zshenv`, for the `PATH` line that makes `tmx` findable.

`./install.sh` on its own does one machine and asks which role it plays.
`--dry-run` shows the plan, `--uninstall` takes it all away.

Now go to *Check it* and skip Option 2.

#### Option 2: the same install, by hand

First get the repo onto the remote as well, since so far it only exists on the
client:

```sh
scp -r ~/tmux-remote remote-box:~/tmux-remote
#      ^ this repo     ^ that machine
```

**On the remote.** Log in with `ssh remote-box`, then run:

```sh
mkdir -p ~/.local/bin ~/.config/tmx/docs ~/.config/tmux

cp ~/tmux-remote/bin/tmx ~/tmux-remote/bin/tmx-status ~/.local/bin/
chmod +x ~/.local/bin/tmx ~/.local/bin/tmx-status

cp ~/tmux-remote/tmux/remote.tmux.conf ~/.config/tmux/tmux.conf
cp ~/tmux-remote/config/config.example ~/.config/tmx/config
cp ~/tmux-remote/config/projects       ~/.config/tmx/projects
cp ~/tmux-remote/docs/*.md             ~/.config/tmx/docs/

touch ~/.config/tmx/remote     # says "this machine does the work"

grep -q '.local/bin' ~/.zshenv 2>/dev/null || \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshenv
```

**Back on the client** (`exit` first, or open another terminal), three files,
because the client only forwards over ssh:

```sh
mkdir -p ~/.local/bin ~/.config/tmx ~/.config/tmux

cp ~/tmux-remote/bin/tmx ~/.local/bin/ && chmod +x ~/.local/bin/tmx
cp ~/tmux-remote/tmux/client.tmux.conf ~/.config/tmux/tmux.conf
cp ~/tmux-remote/config/config.example ~/.config/tmx/config

grep -q '.local/bin' ~/.zshenv 2>/dev/null || \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshenv
```

That last line on both machines matters: it puts `tmx` where your shell will find
it.

Kept the `remote-box` nickname? You are done. Renamed it? Tell the client's
`~/.config/tmx/config`:

```
TMX_REMOTE_HOST=your-nickname
```

[INSTALL.md](INSTALL.md) explains every step above, and why.

### Check it

```sh
tmx version      # prints both machines and says "in sync"
```

Three things that go wrong, and what they mean:

- **`tmx: command not found`** - `~/.local/bin` is not on your `PATH` yet. Both
  options put that line in `~/.zshenv`; open a new terminal so it takes effect,
  or run `source ~/.zshenv`.
- **It cannot reach the remote** - go back and get `ssh remote-box` working.
- **`tmux not found`, but tmux is installed** - set `TMX_PATH_PREPEND` in
  `~/.config/tmx/config` to the directory holding it. Shells started by ssh skip
  most of your profile, so tools on your everyday `PATH` can be invisible to them.

---

## Your first five minutes

**Start working on a directory.** The install looked for `~/code`, `~/work`,
`~/src`, `~/dev`, `~/projects` and `~/repos` on the remote, and added the ones it
found. So `tmx ls` has names in it already. Say one of them is `code-api`, which
is the remote's `~/code/api`:

```sh
tmx code-api
```

You are now in a shell on the remote, in that directory, with a status bar along
the bottom. Nothing else happened: no window layout to learn, no menu. Guess a
name wrong and `tmx` prints the ones it knows, so you cannot get stuck either.

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

**Forgotten a name?** Plain `tmx` opens a picker: live sessions first, then
directories without one, with a preview of the highlighted entry.

### Four tmux words you will meet

You do not need to learn tmux, but these four words appear on screen:

| word | means |
|---|---|
| session | one running workspace, one per directory here |
| window | a tab inside a session. `Ctrl-b c` makes one, `Ctrl-b n` next |
| detach | step away and leave it running. `Ctrl-b d` |
| prefix | the `Ctrl-b` you press before a tmux key |

### When tmux runs inside tmux

If you also run tmux on your own machine, both ends answer to `Ctrl-b` and the
local one gets the key first:

| keys | acts on |
|---|---|
| `Ctrl-b c` | your laptop |
| `Ctrl-b Ctrl-b c` | the remote (press the prefix twice) |
| `F12` | hands the whole keyboard to the remote until you press it again |

My first version gave the remote its own prefix so a keypress could only ever mean
one machine. That was technically better and practically worse: I had to think
before every key, and no tmux documentation I found matched what I had. One prefix
everywhere.

`Ctrl-b ?` shows the keys, `Ctrl-b /` shows the `tmx` commands. Both open inside
tmux, so you never have to leave to look something up.

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

**Session names come from the directory.** `~/code/api` is always `code-api`:

```
~/code/api          ->  code-api
~/code/acme/api     ->  acme-api
~/dotfiles          ->  dotfiles          (straight off $HOME, no prefix)
~/code/my project   ->  code-my-project   (typeable, never needs quoting)
```

A name is always the last two path components, so a deep path does not get a long
name. And **any path works at any depth**: `tmx ~/code/acme/services/billing/api`
opens as `billing-api`.

The working title of all this was "tmux for idiots". The idiot was me: `api` on
Monday, `work-api` on Thursday, then ten minutes on Friday typing into the wrong
session wondering why my changes kept vanishing. Deriving the name from the
directory fixed that, which also made the title inaccurate.

I keep the rule strict because the alternative is a list of sessions I have to
maintain, and I already know how that goes: I stop maintaining it, then I stop
trusting it, then I go back to plain ssh.

## Making the list your own

One file, `~/.config/tmx/projects`, decides what the picker offers and what things
are called. The install seeded it from the directories you already had, so you may
never need to open it. Two kinds of line:

```
~/code                        a ROOT.  Its children are offered, one level deep.

webapi = ~/code/acme/webapi   an ALIAS. Gives one directory a name you choose.
```

An alias becomes the session name, so `tmx webapi` opens a session called
`webapi`. There is **one session per directory, whatever it is called**: an alias,
the derived name and a bare path all land in the same place. Roots and aliases
used to be two files; they are one now because I could never remember which of
them I needed to edit. The file documents itself, and
[docs/tmx-commands.md](docs/tmx-commands.md) has worked examples.

## What else it does

**An AI agent in its own window**, if you ask for one:

```sh
tmx --ai code-api          # your default agent alongside the shell
tmx --ai=codex code-api    # a specific one
```

An agent's command defaults to its own name, so `--ai=codex` needs no
configuration if `codex` is on your `PATH`. The window is named after the agent.
`--ai` also works on a session that has been going for days. This started out
always-on, one agent in every session. I turned it into a flag after noticing how
many sessions I opened just to read a log.

**A session per branch**, using git worktrees:

```sh
cd ~/code/acme/api && tmx wt fix/91     # session acme-api--fix-91
```

The worktree goes to `~/code/.worktrees/api--fix-91` (`tmx` creates it if it is
not there). The status line flags it, so you never forget you are not in the main
checkout. Run the same command later and you just attach.

**Big copy-paste between the machines.** Ordinary copies cross between the
machines by themselves, over OSC 52. When a selection is too big for that, `Y` in copy mode writes it to a file
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

`WT` marks a worktree session, `WINDOWS` names each window (so you can see which
agent runs where), and `tmx ls -w` expands every session into a window tree.

The two colour palettes are not decoration. With one tmux inside another I kept
typing into the wrong machine, so now the bar is blue over there and purple here
and I stopped having to wonder.

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

- Key-based ssh from the client to the remote. Anywhere ssh reaches, this
  reaches: LAN, VPN, public address, jump host.
- On the **remote**: `zsh`, `tmux` 3.2 or newer, `fzf` and `git`. `column` is
  optional: without it `tmx ls` still works, the columns just do not line up.
- On the **client**: just `zsh` and `ssh`. tmux there is only for optional local
  sessions and the `F12` nesting setup, `pbcopy`/`pbpaste` only for `tmx clip`.
- A Nerd Font if you want the status line icons; `TMX_GLYPHS=0` gives plain
  labels without one.

Built and tested against tmux 3.5a, 3.6a and 3.7b, zsh 5.9, macOS 15. Nothing
runs as a daemon: two zsh scripts and some tmux config you can read.

## Docs

**Using it**

- [docs/tmux-keys.md](docs/tmux-keys.md), tmux keys for someone new to tmux.
- [docs/tmx-commands.md](docs/tmx-commands.md), every command in detail, plus
  troubleshooting.
- [INSTALL.md](INSTALL.md), the long-form install with the reasons.

**Working on it**

- [SPEC.md](SPEC.md), the design and why it is that way.
- [docs/gotchas.md](docs/gotchas.md), measured behaviour in zsh, tmux and ssh that
  the code depends on. Worth reading before simplifying anything.
- [CHANGELOG.md](CHANGELOG.md), what changed.
- [ROADMAP.md](ROADMAP.md), what is planned.

Working on it also wants `python3` for `bin/lint-shell-structure.py`, and Docker
for `tests/install-test.sh`. That test installs into throwaway containers and
proves the `--both` path over real ssh. Running `tmx` needs neither.

## Deliberately out of scope

Surviving a reboot, starting on login, and mosh.

Durability here means surviving a dropped connection, not a restart. I did try
session-restoring plugins and kept getting a machine full of half-remembered
sessions I had no memory of starting. A reboot clearing everything is a feature to
me, not a gap, and `tmx <name>` is cheap enough that rebuilding costs nothing.

## License

MIT, see [LICENSE](LICENSE).
