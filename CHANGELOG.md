# Changelog

Versions match `TMX_VERSION` in `bin/tmx`, which `tmx version` prints for both
machines along with a content hash.

Not released yet. Everything below describes the pre-release history of the two
scripts, newest first.

## 2026-08-06.2

**Changed**

- `roots` and `aliases` are now one file, `~/.config/tmx/projects`. A line without
  `=` is a root, a line with `=` is an alias. An existing `roots` file is still
  read, with a warning suggesting the rename.

## 2026-08-06.1

**Added**

- Session aliases. `~/.config/tmx/projects` maps a name of your own to a directory,
  and the alias becomes the session name, so a path a root does not reach can still
  be one short word.

**Changed**

- **One session per directory, whatever it is called.** An alias, the derived name
  and a bare path all attach to the same session, and `tmx` says which name it
  found. Previously a session renamed by hand, or reached under a second name,
  could leave two sessions on one working tree.

## 2026-08-05.9

**Fixed**

- Status line: a work directory containing an apostrophe killed the whole
  right-hand segment, and quote characters shifted the arguments so wrong values
  were displayed. `status-right` now passes only the session name, whose
  character set is controlled; `tmx-status` looks the rest up from tmux itself.
- `tmx wt`: two branch names that sanitise alike, such as `feat/1234` and
  `feat-1234`, mapped to one worktree path and the second silently attached to
  the first branch's working tree. It now refuses and explains the collision. A
  pre-existing directory at that path is checked for actually being a worktree.
- `tmx-status` was missing `setopt extended_glob`, so its config-file whitespace
  trimming did nothing and it read the same file differently from `tmx`.
- Glyph fallback triggered on any tmux server without a UTF-8 locale, because it
  measured character length. It now tests for the failures it means to catch.
- `tmx help` broke for any `PAGER` other than bare `less`.
- Directories whose names contain a newline produced phantom picker entries that
  opened sessions on unrelated directories. They are no longer offered.
- Symlinked work directories were never offered by the picker.
- `tmx clip push` ignored a custom `TMX_CLIP_FILE`, and `tmx clip` reported
  "nothing saved" for every ssh failure including an unreachable host.
- `bin/lint-shell-structure.py`: a line merely mentioning `<<EOF`, including in
  a comment, disabled every check for the rest of the file.

**Changed**

- `tmx kill --all` documented as killing the tmux server, which is what it does.

## 2026-08-05.8

**Added**

- `--ai=<agent>` selects which AI agent to run; `TMX_AI_DEFAULT` sets what plain
  `--ai` uses. An agent's command defaults to its own name, so no configuration
  is needed for an agent already on `PATH`. `TMX_AI_<agent>` overrides that.
- The agent window is named after the agent, so two agents can share a session
  and `tmx ls` shows which is running.

**Fixed**

- A `local` declaration whose value referred to another name assigned in the
  same statement, which yields an empty value in zsh and bash alike. Added a
  linter rule for the class.

## 2026-08-05.7

**Changed**

- Session names now replace all punctuation except `-` and `_`, so a name is
  always typeable unquoted. Letters are preserved in any script.

**Fixed**

- `for x in $(cmd)` split paths on whitespace, so a directory with a space in
  its name failed to resolve, listed as fragments in the picker, and produced
  half-names in suggestions. Three sites.

## 2026-08-05.5

**Added**

- `tmx ls` gained a `WINDOWS` column, and `tmx ls -w` expands each session into
  a window tree showing each window's foreground command.

## 2026-08-05.4

**Changed**

- The AI window is opt-in. `tmx <target>` creates a shell-only session; `--ai`
  adds the agent window, including on a session that is already running.

## 2026-08-05.3

**Fixed**

- Session creation aborted with `bad substitution`: an unbraced `$name` followed
  by `:shell` took zsh's `:s` history modifier.
- `display-message -p -t "=name"` returns empty rather than failing, so
  `session_dir`'s fallback never produced a directory. Needs a trailing colon.
- `cmd_preview` read session options with a bare name, which prefix-matches a
  different session when the exact one is gone.

**Added**

- `tmx version` includes a content hash, so a stale copy cannot report "in
  sync".
- Nerd Font glyphs in both tmux configs.
- `bin/lint-shell-structure.py` rules for the zsh classes `zsh -n` cannot see,
  with `--self-test`.
