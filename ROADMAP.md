# Roadmap

What is planned, in rough order. Nothing here is a promise.

## `tmx doctor`

`install.sh` runs these checks at install time: per-role dependencies, tmux
version, where the tools live, font coverage via `fc-list`, ssh key auth. `tmx
doctor` is the same idea, re-runnable later when something that used to work
stops:

- ssh reachability, and whether the host alias resolves
- the role marker, and that the client does *not* have one
- `PATH` as seen by a non-interactive shell, which is what `ssh host command`
  gets
- tmux version, `fzf` presence
- whether the terminal's font can draw the status-line glyphs
- `config` and `projects` sanity
- version skew between the two machines

Then most "it does not work" questions answer themselves.

## Smaller things

- A way to preview what the projects file produces, `tmx dirs` or similar. Today
  you tune roots by opening the picker and reading the lower group, or by giving a
  bad argument to see the truncated "known names" list. This is the config people
  change most, so it deserves a direct answer.
- An `AGENTS` column or marker in `tmx ls`, rather than reading window names.
- A key binding for `tmx --ai`, alongside `prefix f` for the plain picker.
- Optional per-session layouts beyond shell plus agent.
- Automate the last of the interactive tests. Nesting and the `F12` keys-off
  toggle are covered now. Running three tmux servers inside each other lets a
  harness inject real keypresses into a client's input, which `send-keys` into a
  pane cannot do. The same trick should reach mirrored attach and OSC 52. The fzf
  picker is driven that way already.

## Not planned

- Session persistence across a reboot, or auto-start on login. Durability here
  means surviving a disconnect. A reboot wiping every session is intended.
- mosh integration.
- Windows or Linux client support. Neither has been tried; the clipboard bridge
  and the font handling both assume macOS.
