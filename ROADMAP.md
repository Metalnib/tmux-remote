# Roadmap

What is planned, in rough order. Nothing here is a promise.

## Easier install

Today's install is a page of `cp` commands in [INSTALL.md](INSTALL.md). That
page stays, because it explains *what* is being set up and why, but it should
not be the only route.

**`install.sh`, run on one machine.** Idempotent, no arguments needed.

- Detect the role, or ask once.
- **Check every dependency** and say what is missing, using whichever package
  manager is actually present. See the list below.
- Derive `TMX_PATH_PREPEND` from where those tools really are. This is the
  single biggest source of silent failure and it can be computed instead of
  asked.
- Back up anything it would overwrite.
- Copy the scripts and configs, set the executable bit, write the role marker.
- Seed the `projects` file from directories that exist.
- Never overwrite an existing `config` or `projects`; show a diff against the
  example when new settings appear.
- Verify at the end: syntax check, both tmux configs parse, `tmx version`.

**The dependency check, in full.** Missing pieces should be named plainly, with
the install command for the package manager that is actually present, rather
than failing later in a way that looks like a bug in `tmx`:

| dependency | check |
|---|---|
| `zsh` | present, and 5.x or newer |
| `tmux` | present, and 3.2 or newer (`tmux -V`) |
| `git` | present |
| `fzf` | present, needed by the picker |
| `pbcopy` / `pbpaste` | needed by the clipboard bridge on the client |
| PATH | the four tools above reachable from a **non-login** shell, which is what `ssh host command` gets |
| ssh | the host alias resolves, and key auth works without a password prompt |
| Remote Login | enabled on the remote, otherwise nothing else matters |
| **a Nerd Font** | see below |

**The font is a dependency too**, and the one most likely to be half-installed.
It splits into two checks:

- **Installed**: exactly checkable in plain shell, if `fc-list` is available.
  Query each codepoint and intersect the results, dropping the hidden system
  fallback families whose names begin with a dot:

```sh
fc-list ':charset=F179' family | tr ',' '\n' | sed 's/^ *//' | grep -v '^\.' | sort -u
```

  Intersecting all nine is what makes it trustworthy. `E0B0` on its own is a poor
  test, because a number of unrelated fonts claim coverage in that part of the
  private use area; the Font Awesome codepoints discriminate properly. Without
  `fc-list`, fall back to scanning the font directories by name and lean on the
  visual check below.
- **Selected**: whether the terminal profile actually uses that font cannot be
  detected from a shell, so print the glyphs and ask, in the terminal being set
  up. Nine icons means it is fine. Boxes mean the status line will show boxes,
  and the script should offer to set `TMX_GLYPHS=0` rather than leaving it
  looking broken.

```sh
printf '\ue0b0 \ue0b2 \ue0b3 \ue0a0 \uf179 \uf07b \uf126 \uf017 \uf1da\n'
```

Both checks belong in `tmx doctor` as well, so they can be re-run later.

**Both machines from one command.**

```sh
./install.sh --both --remote-host my-remote
```

Installs locally, copies the repo to the remote, runs the same script there over
ssh, then proves the round trip.

## `tmx doctor`

One command that checks the things that go wrong and explains each failure in
plain language:

- ssh reachability, and whether the host alias resolves
- the role marker, and that the client does *not* have one
- `PATH` as seen by a non-interactive shell, which is what `ssh host command`
  gets
- tmux version, `fzf` presence
- whether the terminal's font can draw the status-line glyphs
- `config` and `projects` sanity
- version skew between the two machines

Most "it does not work" reports should become self-service.

## Smaller things

- A way to preview what the projects file produces, `tmx dirs` or similar. Tuning
  roots currently means opening the picker and reading the lower group, or
  triggering the truncated "known names" list with a bad argument. This is the
  config people change most, so it deserves a direct answer.
- An `AGENTS` column or marker in `tmx ls`, rather than reading window names.
- A key binding for `tmx --ai`, alongside `prefix f` for the plain picker.
- Optional per-session layouts beyond shell plus agent.
- Automate the last of the interactive tests. Nesting and the `F12` keys-off
  toggle are now covered: running three tmux servers inside each other lets a
  harness inject real keypresses into a client's input, which `send-keys` into a
  pane cannot do. The same trick should reach mirrored attach and OSC 52. The
  fzf picker is driven the same way already.

## Not planned

- Session persistence across a reboot, or auto-start on login. Durability here
  means surviving a disconnect. A reboot wiping every session is intended.
- mosh integration.
- Windows or Linux client support. Neither has been tried; the clipboard bridge
  and the font handling both assume macOS.
