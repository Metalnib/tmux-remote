# Install

Written for macOS with MacPorts, which is what it was tested on. Nothing depends
on MacPorts specifically, so substitute your own package manager's install command
below. `TMX_PATH_PREPEND` in the config file is how you tell the scripts where
your tools live.

Two machines:

- **the client** - whatever you sit at. Any terminal, zsh.
- **the remote** - holds the repos and runs the tmux server that matters. You reach
  it by the nickname `remote-box`, which points at `remote.local` or
  `192.168.1.10`.

Same user on both. Assume this repo is checked out at `~/tmux-remote` on
whichever machine you are working on.

## The quick way

`./install.sh` does this whole page. From the client, once `ssh remote-box`
(the alias from `ssh/config.client`) logs in without a password:

```sh
~/tmux-remote/install.sh --both --remote-host=remote-box
```

Or run it on each machine separately and it asks which role that machine plays.
It checks dependencies per role, derives `TMX_PATH_PREPEND` from where your tools
really are, backs up anything it replaces, and never overwrites a `config` or
`projects` you have edited. `--dry-run` shows the plan, `--uninstall` removes
what it installed.

The rest of this page is the same install by hand, with the reasons attached.
Worth a read when something misbehaves, even if the script did the work.

---

## 0. Prerequisites

On the **remote**: `zsh`, `tmux`, `fzf`, `git`. On the **client**: only `zsh`
and `ssh`; add tmux there if you also want local sessions and the F12 nesting
setup. With MacPorts:

```sh
sudo port install tmux fzf git      # remote (zsh ships with macOS)
```

`tmux` needs to be 3.2 or newer - check with `tmux -V`.

Install a Nerd Font and select it in:

- the terminal on the client (the exact iTerm2 setting is in §2.5; other terminals
  have an equivalent)
- whatever terminal you use on the remote's own screen

Nerd Fonts are not in MacPorts; they are a manual font install. If you ever end
up on a terminal without one, `TMX_GLYPHS=0` gives you plain-text labels instead
of icons, with no other change in behaviour.

**Check the font before blaming anything else.** Installing the font is not
enough; you also have to select it in the terminal profile, and it is easy to do
that on one machine and forget the other:

```sh
printf '\ue0b0 \ue0b2 \ue0b3 \ue0a0 \uf179 \uf07b \uf126 \uf017 \uf1da\n'
```

Nine icons means that font is fine. Boxes, question marks or blank space mean it
has no Nerd Font glyphs, and the status line shows the same boxes. Run the check
**in the terminal you actually use**, and on **both** machines, since the remote's
own screen renders the same status line.

---

## 1. The remote machine

Run this on the remote.

### 1.1 tmux config

```sh
mkdir -p ~/.config/tmux
[ -f ~/.config/tmux/tmux.conf ] && cp ~/.config/tmux/tmux.conf ~/.config/tmux/tmux.conf.bak
cp ~/tmux-remote/tmux/remote.tmux.conf ~/.config/tmux/tmux.conf
```

Also back up and remove a legacy `~/.tmux.conf` if you have one - tmux reads it
too, and two configs fighting over the prefix is a confusing afternoon:

```sh
[ -f ~/.tmux.conf ] && mv ~/.tmux.conf ~/.tmux.conf.bak
```

### 1.2 Scripts

```sh
mkdir -p ~/.local/bin
cp ~/tmux-remote/bin/tmx ~/tmux-remote/bin/tmx-status ~/.local/bin/
chmod +x ~/.local/bin/tmx ~/.local/bin/tmx-status
```

### 1.3 tmx config, docs, and the role marker

```sh
mkdir -p ~/.config/tmx/docs
cp ~/tmux-remote/config/projects       ~/.config/tmx/projects
cp ~/tmux-remote/config/config.example ~/.config/tmx/config
cp ~/tmux-remote/docs/*.md             ~/.config/tmx/docs/

# Marks this machine as the remote, so tmx never tries to ssh to itself.
touch ~/.config/tmx/remote
```

Then edit the two files you just copied:

- **`~/.config/tmx/config`** - every line starts commented out, and the defaults
  work if your tools are in `/opt/local/bin`. Uncomment `TMX_REMOTE_HOST` and
  set it to the ssh host alias you will use from the client. If `tmux`, `fzf`
  and `git` live somewhere else, set `TMX_PATH_PREPEND` as well; §1.4 explains
  why this cannot be left to your shell profile.
- **`~/.config/tmx/projects`** - where your work is, and what to call it. Lines
  without `=` are roots, whose children the picker offers; lines with `=` are
  aliases that name one directory. Defaults are the roots `~` and `~/code`. This is
  the file you will revisit most, and it documents itself.

The config file is parsed, not sourced: plain `KEY=value`, no shell expansion,
so write full paths rather than `$HOME`. Precedence is environment, then this
file, then built-in defaults.

### 1.4 PATH

Three separate environments are involved, and it is worth knowing which is
which:

| What | Shell it gets | Reads |
|---|---|---|
| Your panes inside a session | interactive **login** zsh | `/etc/zprofile`, `~/.zprofile`, `~/.zshrc`, `~/.zshenv` - everything |
| `tmx`, forwarded over ssh | **login** zsh (`$SHELL -lc`) | `~/.zprofile`, `~/.zshenv` |
| tmux's own status commands | no shell profile at all | nothing - the server's environment only |

Panes are full login shells. tmux does that by default when `default-command` is
empty, which is why it is left empty. Nothing about working in a session is
stripped down.

The middle row is the one that surprises people. Plain `ssh host command` gives
a non-interactive, non-login shell that reads only `~/.zshenv`, so your package
manager's directory is absent and `tmux` looks uninstalled. `tmx` goes through
`$SHELL -lc`, so the tmux server starts from your real login environment.

The bottom row cannot be fixed with dotfiles - tmux runs `#()` status commands
itself, with no shell in between - so `tmx-status` sets its own `PATH`.

Put `PATH` in `~/.zshenv` regardless. Of all the zsh startup files it is the
only one read by *every* shell, interactive or not, login or not:

```sh
grep -q '.local/bin' ~/.zshenv 2>/dev/null || \
  echo 'export PATH="/opt/local/bin:/opt/local/sbin:$HOME/.local/bin:$PATH"' >> ~/.zshenv
```

Check it from the client - this is the environment that actually matters:

```sh
ssh remote-box 'echo $PATH; command -v tmux fzf git'
```

### 1.5 Enable Remote Login

System Settings → General → Sharing → **Remote Login** on. Limit it to your own
user while you are there.

### 1.6 Note the hostname

```sh
hostname -s
```

Whatever this prints is the machine's own name. It has nothing to do with the
`remote-box` ssh nickname, and nothing here depends on it: the marker file from
1.3 is what role detection uses. It matters only if you delete that file, and
then you set `TMX_REMOTE_NAME` in `~/.config/tmx/config` to this value.

### 1.7 Smoke test, locally on the remote

Syntax-check both scripts first - this catches a bad copy or a stray edit before
tmux starts calling them from a status line, where errors are invisible:

```sh
zsh -n ~/.local/bin/tmx && zsh -n ~/.local/bin/tmx-status && echo "syntax ok"
```

`zsh -n` is the authority, but it only catches syntax. There is a second check for
the classes it cannot see at all: a block terminator left in argument position; an
unbraced `$var:` taking a history modifier; `for x in $(cmd)` word-splitting on
IFS; and a declaration whose value refers to a name assigned in the same
statement.

That one is a development aid, not an install step. It needs `python3`, which
nothing else here does, so skip it if you would rather not:

```sh
python3 ~/tmux-remote/bin/lint-shell-structure.py \
  ~/tmux-remote/bin/tmx ~/tmux-remote/bin/tmx-status
```

Then check the status helper produces a line on its own:

```sh
~/.local/bin/tmx-status right <a-live-session-name>
```

You should get one line of text with `#[...]` colour tags in it. Then:

```sh
tmx ls          # "No sessions."
tmx ~/code      # creates and attaches
```

You should get a blue status bar saying REMOTE and one window, `shell`. Add
`--ai` if you want an agent window too. `C-b d` detaches.

---

## 2. The client machine

Run this on the laptop.

### 2.1 ssh key

A dedicated key for this one hop, rather than reusing a general-purpose one:

```sh
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/client_to_remote_ed25519 \
  -C "client -> remote-box"
```

- `ed25519` is the strong choice - no key size to pick, and shorter and faster
  than RSA at a higher security level. `-b` does nothing for ed25519; ignore any
  advice to pass it.
- `-a 100` raises the number of KDF rounds protecting the **private key file**.
  It only matters if you set a passphrase, which is worth doing: it means a copy
  of the file alone is not enough to reach the remote.

If you set a passphrase, `AddKeysToAgent yes` in the ssh config gets you one
prompt per agent lifetime. To have macOS remember it across reboots, run this
command once - and note it must be **Apple's** ssh-add, since MacPorts' OpenSSH
has no keychain support:

```sh
/usr/bin/ssh-add --apple-use-keychain ~/.ssh/client_to_remote_ed25519
```

The config deliberately does not use the `UseKeychain` option to achieve this.
That option exists only in Apple's ssh. With MacPorts installed,
`/opt/local/bin/ssh` comes first on `PATH`, and there an unknown option is a
**fatal** parse error. It breaks every `ssh` and `scp` on the machine, including
connections to completely unrelated hosts. `IgnoreUnknown` does not save you,
because it only applies to connections matching the block it sits in.

This key lives only on the client. The remote's own `~/.ssh/id_ed25519` is that
machine's git key and has nothing to do with this - only the `.pub` half of the
new key goes over.

Copy the public half to the remote:

```sh
ssh-copy-id -i ~/.ssh/client_to_remote_ed25519.pub youruser@remote.local
```

No `ssh-copy-id`? Append `~/.ssh/client_to_remote_ed25519.pub` to
`~/.ssh/authorized_keys` on the remote by hand - **append**, `>>` not `>`, or
you will wipe any key already trusted there. Then check `~/.ssh/authorized_keys`
is `chmod 600` and `~/.ssh` is `chmod 700`.

Verify before moving on, while password auth is still available as a fallback:

```sh
ssh -i ~/.ssh/client_to_remote_ed25519 youruser@remote.local hostname
```

### 2.2 ssh config

```sh
mkdir -p ~/.ssh/cm
chmod 700 ~/.ssh ~/.ssh/cm
cat ~/tmux-remote/ssh/config.client >> ~/.ssh/config
chmod 600 ~/.ssh/config
```

`~/.ssh/cm` is where the shared connection sockets live; ssh will not create it
for you.

Then check both routes:

```sh
ssh remote-box     hostname   # via mDNS
ssh remote-box-ip  hostname   # via 192.168.1.10
```

### 2.3 tmux config

```sh
mkdir -p ~/.config/tmux
[ -f ~/.config/tmux/tmux.conf ] && cp ~/.config/tmux/tmux.conf ~/.config/tmux/tmux.conf.bak
cp ~/tmux-remote/tmux/client.tmux.conf ~/.config/tmux/tmux.conf
[ -f ~/.tmux.conf ] && mv ~/.tmux.conf ~/.tmux.conf.bak
```

### 2.4 Scripts and docs

Only `tmx` is needed here - it forwards itself over ssh, so `tmx-status` stays
on the remote.

```sh
mkdir -p ~/.local/bin ~/.config/tmx/docs
cp ~/tmux-remote/bin/tmx ~/.local/bin/
chmod +x ~/.local/bin/tmx
cp ~/tmux-remote/docs/*.md ~/.config/tmx/docs/

# Same settings file as on the remote. TMX_REMOTE_HOST is the one that matters
# here: it is the ssh host alias this machine forwards to.
cp ~/tmux-remote/config/config.example ~/.config/tmx/config

grep -q '.local/bin' ~/.zshenv 2>/dev/null || \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshenv

zsh -n ~/.local/bin/tmx && echo "syntax ok"
```

Do **not** create `~/.config/tmx/remote` here. That file is what tells `tmx` it is
on the remote, so `tmx` on this machine would try to ssh to itself.

### 2.5 iTerm2 settings

Three things, all one-time:

1. **Font** - Settings → Profiles → Text → a Nerd Font.
2. **Clipboard** - Settings → General → Selection → tick "Applications in
   terminal may access clipboard". Without this, copying inside the remote tmux
   never reaches your local ⌘V.
3. **Term type** - Settings → Profiles → Terminal → Report Terminal Type
   `xterm-256color`. tmux switches to `tmux-256color` internally by itself.

---

## 3. End-to-end check

From a plain shell on the client:

```sh
tmx ls
```

That should ssh to the remote, run `tmx ls` there, and print the table - no
manual `ssh remote-box` step.

```sh
tmx
```

The picker, over remote sessions and remote work dirs. Pick something and you
land in a session with a blue REMOTE status bar showing hostname, directory, git
branch, worktree flag, last-attached and uptime.

Then, to confirm the pieces that matter:

```sh
# survives a disconnect
tmx code-api          # attach, start something long-running
# close the laptop lid / kill iTerm2 / pull the wifi
tmx code-api          # everything is still there

# same dir always resolves to the same session
tmx ~/code/api
tmx code-api          # same session, not a second one

# worktrees
cd-into-a-repo-on-the-remote-box && tmx wt feat/1234

# nesting is unambiguous
# start a local session with C-b, attach to a remote one inside it:
#   purple bar = laptop, blue bar = remote, F12 turns the laptop's keys off
```

Mirrored attach: with a session open on the remote's own display, run `tmx
<same-name>` from the laptop. Both screens show the same window and share the
keyboard. The window sizes itself to the smaller of the two terminals, so
nothing is cut off on either.

---

## 4. Updating later

Both machines, after pulling changes to this repo:

```sh
cp ~/tmux-remote/bin/tmx ~/.local/bin/           # both machines
cp ~/tmux-remote/bin/tmx-status ~/.local/bin/    # remote only
chmod +x ~/.local/bin/tmx ~/.local/bin/tmx-status
cp ~/tmux-remote/docs/*.md ~/.config/tmx/docs/
```

`chmod +x` is not paranoia: `cp` onto an existing file keeps the *destination's*
mode, and a `tmx-status` that is not executable makes the status line fail
silently rather than complain.

**Do not copy `config/projects` or `config/config.example` again.** Both are
templates you edited during install, and `~/.config/tmx/projects` and
`~/.config/tmx/config` are now yours. Overwriting them with the repo's generic
versions points the picker at directories you do not have, and resets your remote
host alias. The picker then just goes quiet, with no error to explain why. If a
new version adds a setting, read the example and add that one line by hand:

```sh
diff ~/.config/tmx/config ~/tmux-remote/config/config.example
```

For the tmux config, copy the right file for the machine - `client.tmux.conf` or
`remote.tmux.conf` - and then `prefix r` to reload it. Running sessions keep
going; only the config is re-read.

Finish with `tmx version`, which reports both copies and whether they match. It
compares a content hash, not just the version string, so a stale copy on one
machine cannot pass as up to date.

---

## 5. Uninstall

```sh
rm -f  ~/.local/bin/tmx ~/.local/bin/tmx-status
rm -rf ~/.config/tmx
mv ~/.config/tmux/tmux.conf.bak ~/.config/tmux/tmux.conf   # if you had one
```

Remove the `Host remote-box` / `Host remote-box-ip` block from `~/.ssh/config`
on the laptop. Running tmux sessions on the remote are untouched by any of this
- run `tmux kill-server` there if you want them gone too.
