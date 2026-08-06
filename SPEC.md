# Design notes

What `tmx` does, and why it does it that way. The reasoning matters more than
the rules: most of these choices exist because of something specific about tmux,
zsh or ssh, and undoing one tends to break something that is not obviously
related.

- [docs/gotchas.md](docs/gotchas.md) has the measured behaviour behind them.
- [CHANGELOG.md](CHANGELOG.md) has what changed and when.

## 1. Machines and roles

| | Client | Remote |
|---|---|---|
| What it is | whatever you sit at, typically a laptop | the machine with the CPU, RAM and repos |
| Terminal | any, Nerd Font recommended | its own screen, when used directly |
| Shell | zsh | zsh |
| tmux server | yes, for local sessions | yes, for the work sessions |
| tmux prefix | `C-b` | `C-b` |
| Repos | none | all of them |
| Reachable as | - | an mDNS name, plus a reserved LAN address as fallback |

Transport is plain ssh with key auth, so anywhere ssh reaches, `tmx` reaches: a
LAN, a VPN, a public address, a jump host. Nothing in the scripts assumes
otherwise. It was built and tested on a LAN, which is the only reason
`ssh/config.client` ships LAN-flavoured defaults (mDNS name, an address
fallback, `AddressFamily inet`, no jump host) - those are conveniences to edit,
not requirements. Over a higher-latency link expect tmux redraws to feel it;
exposing ssh beyond a trusted network is your call to secure. mosh is not used.

Built and tested on macOS with MacPorts, which is why `/opt/local/bin` is the
default for `TMX_PATH_PREPEND`. Nothing depends on MacPorts specifically: the
scripts need `tmux`, `fzf`, `git` and `zsh` on `PATH`, and that one setting is
how you tell them where those live. See §7.

## 2. Session model

### 2.1 Naming (deterministic, idempotent)

`slug(dir)`:

1. Resolve `dir` to a real absolute path (symlinks followed).
2. `base = basename(dir)`, `parent = dirname(dir)`.
3. If `parent` is `$HOME` → name is `base`. Otherwise → name is
   `basename(parent)-base`.
4. Sanitise: whitespace and all of `[:punct:]` **except `-` and `_`** → `-`;
   collapse runs of `-`; strip leading and trailing `-`.
5. **Case is preserved.** Letters are preserved in any script, so Cyrillic and
   accented names survive; only punctuation is replaced.

**Why sanitise at all.** tmux silently rewrites `.` and `:` in a session name to
`_`: `new-session -s a.b` stores `a_b`, and every later `has-session -t=a.b`
then fails, so create-or-attach breaks and the slug no longer predicts the
stored name. Those two characters *must* be replaced by `tmx` itself. Everything
else - spaces, parens, `/`, `$`, non-ASCII letters - tmux keeps verbatim, and
`=name`, `=name:2` and `=name:shell` all resolve fine.

Replacing the rest is a usability decision rather than a tmux requirement.
Session names are things you type, and `tmx` prints them as runnable commands in
its suggestions and error messages; preserving them verbatim would mean quoting
at every one of those sites while still being lossy on `.` and `:`, so it buys
no fidelity. The invariant instead is that **a session name is only letters,
digits, `-` and `_`**, and is therefore always typeable unquoted. `_` is kept
rather than replaced, so that adding this rule does not rename existing
sessions. Where two directories still collide on one name, `tmx` refuses and
prints both paths.

Examples:

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

Same dir always resolves to the same name, so create and attach are the same
operation: if the session exists, attach; if not, create then attach.

**Collisions.** Because the rule is lossy - sanitising means `~/code/a.b` and
`~/code/a-b` both become `code-a-b` - two directories can want one name. Names
taken directly from `$HOME` can also collide with a name derived from a nested
directory. When a requested name already exists but points at a *different*
directory, `tmx` refuses and prints both paths rather than attaching to the
wrong session.

### 2.2 Worktree sessions

`tmx wt <branch>` (run from inside a repo) or `tmx wt <dir> <branch>`:

- Session name: `<repo-slug>--<branch-slug>`, where `branch-slug` maps `/` and
  `.` to `-`, case preserved.
- `feat/1234` in `~/code/globex/mono` → `globex-mono--feat-1234`.
- If the worktree does not exist on disk, `tmx wt` creates it via `git worktree
  add`, then opens the session there.
- Status line flags the session as a worktree.

Worktree location: `<repo-parent>/.worktrees/<repo-basename>--<branch-slug>`.

The `<repo-basename>--` component is a deliberate refinement of the
flat-worktree decision. Without it, `~/code/api` and `~/code/web` both branching
`feat/x` would resolve to the same path `~/code/.worktrees/feat-x`. Flat, one
level deep, and `.worktrees` being a dotdir means the picker never lists
worktrees as plain dirs - they appear only as live sessions.

### 2.3 Window layout

Every new session gets, with `base-index 1`:

1. Window 1 `shell` - plain zsh at the work dir. Focused on attach, always.
2. Window 2, named after an AI agent, running that agent at the same work dir.
   **Only with `--ai`.**

The agent window is opt-in. `--ai` is accepted in any position by `tmx`, `tmx
<name|dir>` and `tmx wt`, and survives the ssh hop from the client. Without it a
session is shell-only. Both windows always share one work dir: `-c` is passed to
each, so they cannot diverge.

**Which agent.** `--ai` runs `TMX_AI_DEFAULT`; `--ai=<agent>` runs a named one.
An agent's command defaults to its own name, so `--ai=codex` works with no
configuration when `codex` is on `PATH`; `TMX_AI_<agent>` in the config file
overrides that, arguments and quoting preserved. Agent names are restricted to
letters, digits and underscore because the name becomes both a tmux window name
and part of a variable name. The window is named after the agent rather than a
generic `ai`, which makes `tmx ls` informative, lets two agents share a session,
and keeps "asking for the same agent twice" a no-op.

`--ai` is also additive on a session that is already running, which is the one
case where `tmx` touches an existing session's layout. It adds the window at
index 2 when that index is free, appends otherwise rather than renumbering
windows you opened yourself, and never creates a second window for the same
agent. It is created with `-d`, so enabling it does not move you off your shell.

Extra windows and panes are ad hoc and inherit the current pane's cwd. The agent
window is created with `remain-on-exit off`; quitting the agent closes the
window, and `tmx` does not recreate it. Apart from adding an agent window on
request, existing sessions are never restructured.

Anything that is not an agent - a database client, a log tail, a bare ssh - is
launched by hand in an ad-hoc window. There is no list of extra tools `tmx`
starts for you.

### 2.4 Picker

fzf-based (`port install fzf`), invoked as `tmx` with no arguments and bound to
a key inside tmux.

Two groups in one list, live sessions first:

```
session  code-api          ~/code/api            attached
session  globex-mono--feat-1234  ~/code/.worktrees/mono--feat-1234  last 2h ago
dir      acme-api                ~/code/acme/api
```

Roots come from `~/.config/tmx/projects`, which holds both roots (a bare path) and
aliases (`name = path`), distinguished by the presence of `=`:

```
~
~/code
```

Rules:

- Each root is scanned **one level deep only**.
- **Blocklist** applied to every root: `Library`, `Applications`, `Desktop`,
  `Downloads`, `Documents`, `Music`, `Movies`, `Pictures`, `Public`, `Sites`,
  and any dotted dir. Non-git dirs are otherwise listed.
- **Deeper root wins:** a child that is itself a listed root is dropped from the
  parent's listing, so it is never offered itself, only as a container of its
  children.
- A container such as `~/code/acme` is deliberately **not** listed as a root.
  With "deeper root wins" that would remove it from `~/code`'s listing, so
  `code-acme` could never be created by name. Names one level deeper stay
  reachable by path: `tmx ~/code/acme/api` opens as `acme-api`, because the slug
  rule does not depend on your roots.
- Selecting a session attaches; selecting a dir creates-or-attaches.

## 3. Durability and attach

- No tmux-resurrect, no continuum, no launchd auto-start. Reboot wipes sessions
  - intended.
- Sessions survive ssh disconnect (that is the whole point of the server-side
  tmux).
- **Mirrored attach:** the client and the remote's own screen attach to the same
  session, same window, same keystrokes. `tmx` never passes `-d`, so it never
  kicks the other client off.
- `window-size smallest` and `aggressive-resize off` are set explicitly - tmux
  3.x defaults to `latest`, which would truncate one screen. Result: the window
  clamps to the smaller terminal; the larger display shows unused space, nothing
  is ever hidden.
- `detach-on-destroy off` so killing a session drops you to another rather than
  to a bare shell.

## 4. Nesting: local vs remote

Both servers run at once. Nesting is permitted, and both use the **default
`C-b`**.

Both servers use `C-b`. Giving the remote its own prefix would make every
keypress unambiguous, but it costs muscle memory and means tmux documentation no
longer applies as written. The remote is also used directly from its own screen,
where a non-default prefix would apply as well. One prefix everywhere, and the
palette tells you which server you are typing at.

The consequence is accepted rather than engineered around: when a remote session
is attached from inside a local one, the laptop's server sees `C-b` first.

- **`C-b C-b`** - `send-prefix` is bound on both servers, so double-tapping
  forwards one prefix to the inner session. `C-b c` makes a window on the
  laptop; `C-b C-b c` makes one on the remote. This is the primary mechanism.
- **`F12` toggle** on the local server, promoted from belt-and-braces to the
  alternative: turns the local key table off, greys the local status bar and
  shows `CLIENT keys off`, so plain `C-b` falls through to the remote for as
  long as you want. Press again to restore.
- **Colour split:** the two servers get distinct status-bar palettes and an
  explicit label - `CLIENT` on the client's server, `REMOTE` on the remote.
  Different accent colour, different background. With a shared prefix these no
  longer tell you which key to press, but they remain how you know which machine
  you are looking at.
- **No nest guard.** `tmx` does not refuse to run inside a local tmux session;
  nesting is a supported way to work, one local window per remote session
  (`prefix f` on the laptop uses `new-window`, not a popup, so the remote
  session is not living inside something that can close under it).
- Status style uses **Nerd Font glyphs** (powerline separators, branch and
  worktree icons).

  **Requires a Nerd Font** selected in the client's terminal **and** in whatever
  terminal is used on the remote directly, since the remote's own screen renders
  the same status line. A non-patched font there shows tofu boxes. Nerd Fonts
  are usually a manual font-file install; INSTALL.md covers it. `TMX_GLYPHS=0`
  switches to plain text labels instead.

## 5. Remote status line

Left: server label, session name, window list.

Right, in order:

1. hostname
2. work dir (`~`-shortened)
3. git branch (glyph + name)
4. worktree indicator (glyph, shown only when the dir is a linked worktree)
5. last attached - `attached` when a client is connected, else relative (`last
   2h ago`)
6. active since - `up 3d 4h`

Computed by `tmx-status`, a small script reading `#{session_activity}` /
`#{session_created}` and the git state, refreshed every **15 s**
(`status-interval 15`). Relative times can therefore lag up to 15 s after a
detach.

**Glyphs.** Nerd Font icons and powerline separators are literal characters in
three places: `status-left` and `window-status-current-format` in both `.conf`
files, and the `status-right` segments in `tmux-status`. A tmux config cannot
use `$'\u…'` escapes, so the `.conf` files must carry literals; `tmux-status`
carries literals too but could use escapes if a transport ever strips them
again. Separator direction differs by side and is not interchangeable:
`status-left` and the window list grow left to right and use **U+E0B0** (solid,
pointing right), while `status-right` is built with **U+E0B2** / **U+E0B3**
(pointing left). Icons: U+F179 host, U+F07B dir, U+E0A0 branch, U+F126 worktree,
U+F017 last attached, U+F1DA active since. `tmx-status` falls back to plain text
labels if a glyph is not exactly one character, and `TMX_GLYPHS=0` forces that
fallback.

## 6. Client-side ssh

`~/.ssh/config` gets a shared block plus two host entries:

- `tmx-remote` → `remote.local` (mDNS, normal use)
- `tmx-remote-ip` → `192.168.1.10` (reserved static IP, fallback when mDNS
  misbehaves). Per-network: the reservation lives on one router, so this needs
  editing on a location change, whereas `remote.local` follows the machine.

Both inherit user `youruser`, `ServerAliveInterval 30`, `ServerAliveCountMax 3`,
`TCPKeepAlive yes`, `ControlMaster auto` with a socket under `~/.ssh/cm` and
`ControlPersist 10m` so repeated `tmx` calls reuse one connection.

Key: a dedicated `~/.ssh/client_to_remote_ed25519` on the client, generated
`ed25519 -a 100`, with `IdentitiesOnly yes` so nothing else in the agent is
offered. Distinct from the remote's own `~/.ssh/id_ed25519`, which is that
machine's git key and is not involved - only the public half of the laptop's key
is added to the remote's `authorized_keys`. `AddKeysToAgent yes` for one
passphrase prompt per agent lifetime.

**No `UseKeychain`.** The option exists only in Apple's ssh, and MacPorts'
`/opt/local/bin/ssh` precedes `/usr/bin/ssh` on `PATH`; under it, an unknown
option is a fatal parse error that disables `ssh` and `scp` machine-wide, for
every host. `IgnoreUnknown UseKeychain` is not an adequate guard - it applies
only to connections matching the block containing it, so a connection to a raw
IP or an unrelated host still aborts. Keychain persistence is instead a one-off
`/usr/bin/ssh-add --apple-use-keychain`.

The `Host` pattern list includes the raw IP as well as the two aliases, so
connecting by address by hand still picks up the key, keepalives and connection
sharing.

**No `ForwardAgent`** - the remote holds its own git keys.

## 7. Entry point

One script, `tmx`, installed at `~/.local/bin/tmx` on **both** machines, with
subcommands:

| Command | Effect |
|---|---|
| `tmx` | fuzzy picker over sessions + dirs |
| `tmx <name-or-dir>` | create-or-attach |
| `tmx wt <branch>` | worktree session |
| `tmx ls` | sessions with dir, branch, worktree flag, last attached, uptime, and a compact `index:name` window list |
| `tmx ls -w` | the same, expanded per session into a window tree showing each window's foreground command |
| `tmx kill <name>` | kill one session, confirm prompt |
| `tmx kill --all` | kill every session, confirm prompt |
| `tmx help keys` / `tmx help cmds` | page the cheatsheets |

Dispatch logic:

1. **On the client** (hostname ≠ `tmx-remote`): re-exec as `ssh -t tmx-remote
   '$SHELL -lc "tmx …"'`. So `tmx code-api` from a local shell lands you inside
   the remote session in one step. Remote host is overridable via
   `TMX_REMOTE_HOST`.

   The `$SHELL -lc` wrapper is required, not cosmetic. Plain `ssh host command`
   runs a non-interactive, non-login zsh that reads only `~/.zshenv`, so
   MacPorts' `/opt/local/bin` is absent and `tmux`, `fzf` and `git` appear
   uninstalled. Going through a login shell also means the tmux server, when
   this call is what starts it, inherits the real environment rather than a
   stripped one.
2. **On the remote, outside tmux:** create if needed, then `attach-session`.
3. **On the remote, inside tmux** (`$TMUX` set): create detached if needed, then
   `switch-client -t` - never a nested attach.

## 8. Deliverables

```
tmux-remote/
├── README.md                what this is, and why
├── LICENSE                  MIT
├── SPEC.md                  this file: the design, and the reasoning
├── INSTALL.md               step by step, both machines
├── tmux/
│   ├── remote.tmux.conf     remote: C-b prefix, REMOTE palette, status line
│   └── client.tmux.conf     client: C-b prefix, CLIENT palette, F12 toggle
├── ssh/
│   └── config.client        block to merge into the client's ~/.ssh/config
├── bin/
│   ├── tmx                  create/attach/wt/ls/kill/picker/help
│   ├── tmx-status           status-line data helper, remote only
│   └── lint-shell-structure.py   structural checks zsh -n cannot do
├── config/
│   ├── config.example       settings template -> ~/.config/tmx/config
│   └── roots                picker roots
└── docs/
    ├── tmux-keys.md         keybindings cheatsheet, for a tmux beginner
    ├── tmx-commands.md      the CLI, with worked examples
    └── gotchas.md           measured surprises in zsh, tmux and ssh
```

`prefix ?` opens either doc in a `display-popup`, paged with `less -R`.

Both docs assume zero prior tmux knowledge: what a server/session/window/pane
is, what detach means, what to do when something looks stuck.

## 9. Other config decisions

- `default-terminal tmux-256color`, plus `terminal-features` for RGB truecolor.
- Mouse **on** - scroll, click-to-focus pane, drag-to-resize.
- `set-clipboard on` with OSC 52, so a copy in the remote tmux lands in the
  client's clipboard. Your terminal has to allow it: in iTerm2 that is Settings
  → General → Selection → "Applications in terminal may access clipboard"; other
  terminals have an equivalent, and some enable it by default. Nested, the
  payload makes two hops - the remote's tmux emits it, the client's re-emits to
  the terminal - which works, but is where a large selection is most likely to
  be truncated.
- **Clipboard file bridge**, for selections too big for OSC 52. `Y` in copy mode
  on the remote writes the selection to `~/.cache/tmx/clip.txt` and reports the
  size; `tmx clip` on the client fetches it over ssh onto the local clipboard;
  `tmx clip scp` prints the raw `scp` line instead. The reverse direction is
  `tmx clip push` on the client, then `prefix P` on the remote. `tmx clip` is
  dispatched before `tmx`'s ssh-forwarding branch, since it does opposite things
  on each machine. Plain `y` remains the one-keystroke default.
- vi-style copy mode keys.
- `history-limit 50000`, `escape-time 10`, `focus-events on`, `renumber-windows
  on`, `pane-base-index 1`.
- Config lives at `~/.config/tmux/tmux.conf` on each machine (XDG). Existing
  files are backed up, not overwritten.
- `default-command` deliberately left **empty**, which is what makes tmux start
  each pane as an interactive *login* shell - so panes read `/etc/zprofile`,
  `~/.zprofile` and `~/.zshrc` and have the full environment. Verified by
  inspection: `$0` in a pane is `-zsh`, with the leading dash marking a login
  shell. Setting `default-command` at all would silently downgrade this.
- `tmx-status` sets its own `PATH`. tmux executes `#()` status commands itself,
  with no shell profile in between, so this is the only place that environment
  can be fixed.

## 10. Explicitly out of scope

Session persistence across a reboot, auto-starting on login, and mosh
integration. Durability here means surviving a disconnect, not a restart.

---

## 11. Open questions, and how they landed

Four things were genuinely undecided at the start. Recording the outcomes
because each one constrains the code.

- **Name collisions.** Resolved by refusing rather than guessing: a name that
  already exists pointing at a different directory makes `tmx` stop and print
  both paths. See §2.1.
- **Worktree layout.** Flat, one level deep, in a `.worktrees` dotdir next to
  the repo - plus a `<repo-basename>--` prefix in the leaf, so two repos under
  one parent branching the same name do not collide on a path. See §2.2.
- **Glyphs.** A Nerd Font is required for the status line as designed, with
  `TMX_GLYPHS=0` as the plain-text escape hatch. See §5.
- **Reaching the remote.** An mDNS name is the primary route, with a reserved
  LAN address as a fallback, since the name follows the machine between networks
  and the address does not. A purpose-made key rather than reusing an existing
  `id_ed25519`, so the client's access is separable from whatever keys the
  remote already has. See §6.

## 12. Host role detection

`tmx` decides whether it is on the client or the remote by, in order:

1. `TMX_ROLE=remote` in the environment, or
2. the marker file `~/.config/tmx/remote` existing, or
3. `hostname -s` matching `TMX_REMOTE_NAME` (default `tmx-remote`),
   case-insensitive.

The marker file is created on the remote during install, so the logic never
depends on how macOS happens to be reporting the hostname that day.
