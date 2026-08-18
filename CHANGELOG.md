# Changelog

Versions match `TMX_VERSION` in `bin/tmx`, which `tmx version` prints for both
machines along with a content hash.

Install script. Better instructions.

## 2026-08-18

**Added**

- `tests/install-test.sh`: Docker integration test for the installer. Eighteen
  checks, from missing-dependency messages up to `--both` across two containers
  over real ssh, ending with a session created remotely by a plain `tmx <name>`.
  Part 2 appends the shipped `ssh/config.client`, edits the two `# EDIT ME` lines
  and connects by the nickname it defines, so the documented install path is what
  gets tested. The remote container keeps tmux and fzf where only a login shell
  can see them, which is what a MacPorts remote looks like.
- `install.sh`: one command per machine, or `--both --remote-host=NAME` from the
  client to do the pair. Checks dependencies per role, derives
  `TMX_PATH_PREPEND`, migrates a legacy `roots` file and a legacy `~/.tmux.conf`,
  checks font glyph coverage, never overwrites an edited `config` or `projects`,
  and proves the round trip with `tmx version`. `--dry-run` and `--uninstall`
  included.

**Changed**

- Renamed the SSH alias from tmx-remote to remote-box; TMX_REMOTE_HOST now defaults to remote-box.
- README: clarified the alias, shortened install steps, and noted existing behaviour around project-directory seeding and unknown names.
- config/config.example: clarified that TMX_REMOTE_NAME is a hostname, not an SSH alias.
- Docs: tightened wording, fixed tense usage, and removed duplicated or awkward phrasing.

**Fixed**

- `install.sh --both` ran the remote installer through plain `ssh host command`,
  which reads only `~/.zshenv`. Tools in `/opt/local/bin` looked missing and
  `TMX_PATH_PREPEND` was derived as `/usr/bin`, so `tmx` on a freshly deployed
  remote could not find tmux. The remote leg goes through `$SHELL -lc`, the way
  `bin/tmx` does. See docs/gotchas.md #12.
- `install.sh` asked "Which machine is this?" and offered "remote", which reads as
  "deploy to the remote" and turned the machine in front of you into the remote.
  It now asks what to do, and one of the three answers is "install here as the
  client, then deploy to the remote over ssh". Choosing the remote role on a
  machine that carries the client tmux config asks for confirmation first.
- `TMX_VERSION` said `2026-08-06.4` while the newest release here was
  `2026-08-18`. `tests/install-test.sh` fails when the two disagree.
- `SPEC.md` said the status line falls back to plain text when a glyph "is not
  exactly one character". That was the behaviour before 2026-08-05.9;
  `tmx-status` tests for a glyph that arrives empty or as a literal `\u` escape,
  because a character count depends on the locale.
- `SPEC.md`'s file tree listed `config/roots`, which has not existed since roots
  and aliases merged into `config/projects`. The tree was also missing
  `CHANGELOG.md` and `ROADMAP.md`.
- `install.sh` only warned when `~/.local/bin` was not on `PATH`, so the next
  documented step, `tmx version`, failed with "command not found". It now adds
  the line to `~/.zshenv` itself.
- Docs claimed `tmux`, `fzf` and `git` are needed on both machines. The client
  forwards over ssh before any of them run: it needs `zsh` and `ssh`, tmux only
  for optional local sessions.
- `SPEC.md` had the `tmx wt` arguments in the wrong order.

## 2026-08-06.4

**Fixed**

- **`tmx ls`, the picker and the status line showed wrong values on tmux 3.5a.**
  tmux escapes control bytes in format output, so the tab delimiter arrived as
  `_` and a whole record came back as a single field: `DIR` showed the entire
  record, `LAST ATTACHED` and `UP` showed ages in the thousands of days, and the
  status line lost its directory, branch and uptime. Records now use a printable
  delimiter with the one field that may contain it last, and a session's
  directory is looked up per session so it stays exact. Measured as correct on
  3.5a and 3.7b, including a directory named `odd|dir` and a window named
  `odd|winname`.
- **A second name for a directory opened a duplicate session on tmux 3.5a.** The
  one-session-per-directory guard read the same collapsed record, so it never
  matched and an alias re-opened a directory that was already running.
- `tmx ls` died with "command not found: column" on a machine without
  `column(1)`, which minimal Linux images do not ship. It falls back to
  unaligned output. `install.sh` reports `column` as optional.
- `bin/lint-shell-structure.py` treated the opening quote of a nested string
  inside `$( )` as closing the outer one, then read every following `#` as a
  comment, and reported an unclosed quote that `zsh -n` accepts.

**Added**

- `bin/lint-shell-structure.py` rejects a tab used as a delimiter inside a tmux
  `-F` format.
- `tests/install-test.sh` checks that `tmx ls` reports a real directory, keeps
  its columns aligned to the right fields when a value contains the delimiter,
  and still refuses a duplicate session for one directory.

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
