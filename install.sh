#!/bin/sh
# install.sh -- set up tmx on this machine, or on both machines at once.
#
#   ./install.sh                          asks: this machine, or both over ssh
#   ./install.sh --role=remote            this machine holds the repos
#   ./install.sh --role=client            this machine is the one you sit at
#   ./install.sh --both --remote-host=remote-box
#                                         client here, then the remote over ssh
#                                         (the name is your ssh alias for it)
#   ./install.sh --dry-run                show what would happen, touch nothing
#   ./install.sh --uninstall              remove what an install put here
#
# Safe to re-run. It never overwrites ~/.config/tmx/config or projects, and it
# backs up anything else it replaces.
#
# POSIX sh on purpose: it runs before anything it sets up has been verified, so
# it must not depend on zsh, the PATH, or the config it is about to write.

set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/tmx"
TMUXCFG="${XDG_CONFIG_HOME:-$HOME/.config}/tmux"
BIN="$HOME/.local/bin"
STAMP=$(date +%Y%m%d-%H%M%S)

ROLE=""; BOTH=0; DRY=0; UNINSTALL=0; RHOST=""; DEPLOY_TARGET=0
FAIL=0

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
ok()   { printf '   ok    %s\n' "$*"; }
warn() { printf '   warn  %s\n' "$*"; }
bad()  { printf '   FAIL  %s\n' "$*"; FAIL=$((FAIL+1)); }
die()  { printf 'install: %s\n' "$*" >&2; exit 1; }

# No eval anywhere: arguments pass through exactly as given.
run() {
  if [ "$DRY" = 1 ]; then printf '   would %s\n' "$*"; else "$@"; fi
}

# append FILE LINE...   one line per argument, dry-run aware
append() {
  af=$1; shift
  if [ "$DRY" = 1 ]; then
    for l in "$@"; do printf '   would append to %s: %s\n' "$af" "$l"; done
  else
    for l in "$@"; do printf '%s\n' "$l" >> "$af"; done
  fi
}

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
  exit 0
}

while [ $# -gt 0 ]; do
  case $1 in
    --role=remote|--role=client) ROLE=${1#--role=} ;;
    --role) shift; ROLE=${1-}
            case $ROLE in remote|client) ;; *) die "--role needs remote or client" ;; esac ;;
    --both)          BOTH=1 ;;
    # Internal: set by --both on the remote leg, where installing the remote is
    # the whole point, so the client-machine guard must not ask.
    --deploy-target) DEPLOY_TARGET=1 ;;
    --remote-host=*) RHOST=${1#*=} ;;
    --remote-host)   shift; RHOST=${1-}; [ -n "$RHOST" ] || die "--remote-host needs a name" ;;
    --dry-run)       DRY=1 ;;
    --uninstall)     UNINSTALL=1 ;;
    -h|--help)       usage ;;
    *)               die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

# --both starts on the machine you sit at, so the local half is the client.
[ "$BOTH" = 1 ] && [ -z "$ROLE" ] && ROLE=client

# ---------------------------------------------------------------- uninstall
if [ "$UNINSTALL" = 1 ]; then
  step "Removing tmx"
  for f in "$BIN/tmx" "$BIN/tmx-status" "$CFG/remote"; do
    if [ -e "$f" ]; then run rm -f "$f"; ok "removed $f"; fi
  done
  [ -d "$CFG/docs" ] && { run rm -rf "$CFG/docs"; ok "removed $CFG/docs"; }
  say ""
  say "Left alone on purpose, they are yours:"
  say "  $CFG/config"
  say "  $CFG/projects"
  say "  $TMUXCFG/tmux.conf   (a .bak from install time may sit next to it)"
  exit 0
fi

# ---------------------------------------------------------------- role
if [ -z "$ROLE" ]; then
  if [ -e "$CFG/remote" ]; then
    ROLE=remote
    say "Found $CFG/remote, so installing as the REMOTE."
  elif [ -t 0 ]; then
    # Every option says WHERE the install lands. Asked as "which machine is
    # this?", with a bare "remote" option, people reasonably read it as "deploy
    # to the remote" and turn the machine in front of them into the remote.
    say "What should this do?"
    say "  1) install on THIS machine, as the client  (what you sit at)"
    say "  2) install on THIS machine, as the remote  (it holds the repos)"
    say "  3) install here as the client, then deploy to the remote over ssh"
    printf 'Enter 1, 2 or 3: '
    read -r answer
    case $answer in
      1) ROLE=client ;;
      2) ROLE=remote ;;
      3) ROLE=client; BOTH=1
         printf 'ssh nickname of the remote, as in ~/.ssh/config: '
         read -r RHOST
         [ -n "$RHOST" ] || die "no nickname given, so there is nothing to deploy to"
         ;;
      *) die "expected 1, 2 or 3" ;;
    esac
  else
    die "not a terminal, so I cannot ask: pass --role=remote or --role=client"
  fi
fi

# An installed CLIENT tmux config, with no remote marker beside it, means this is
# the machine you sit at. Installing it as the remote stops it forwarding, and
# every session then lands here instead of over there.
#
# TMX_REMOTE_HOST is NOT the signal to use: config.example goes to both machines,
# so a correctly installed remote names a host too.
if [ "$ROLE" = remote ] && [ "$UNINSTALL" = 0 ] && [ "$DEPLOY_TARGET" = 0 ] &&
   [ ! -e "$CFG/remote" ] &&
   grep -q 'for the CLIENT machine' "$TMUXCFG/tmux.conf" 2>/dev/null; then
  RH_SET=$(sed -n 's/^TMX_REMOTE_HOST=//p' "$CFG/config" 2>/dev/null | head -1)
  [ -n "$RH_SET" ] || RH_SET=your-remote
  warn "this machine has the CLIENT tmux config, so it is the one you sit at"
  say  "         As the remote it would stop forwarding, and run everything here."
  say  "         To install on '$RH_SET' over ssh instead, run:"
  say  "             $0 --both --remote-host=$RH_SET"
  if [ -t 0 ]; then
    printf 'Install THIS machine as the remote anyway? [y/N] '
    read -r ans
    case $ans in
      y|Y|yes|YES) ;;
      *) die "stopped, nothing changed" ;;
    esac
  else
    die "refusing: pass --role=client, or --both --remote-host=$RH_SET"
  fi
fi

# ---------------------------------------------------------------- deps
# The two roles need different things. The client forwards over ssh before it
# ever touches tmux, so tmux/fzf/git are REMOTE requirements; the client needs
# zsh (tmx is a zsh script) and ssh, and tmux only if you want local sessions.
step "Checking what is installed (as the $ROLE)"

have() { command -v "$1" >/dev/null 2>&1; }

pkg_hint() {
  if   have port;   then echo "sudo port install $1"
  elif have apt;    then echo "sudo apt install $1"
  elif have pacman; then echo "sudo pacman -S $1"
  else echo "install $1 with your package manager"
  fi
}

if have zsh; then ok "zsh   $(command -v zsh)"
else bad "zsh missing, tmx is a zsh script.  $(pkg_hint zsh)"; fi

tmux_version_ok() {
  tv=$(tmux -V | sed 's/^tmux //; s/[a-z]*$//')
  case $tv in
    ''|*[!0-9.]*) warn "could not read a version from: $(tmux -V)"; return 0 ;;
  esac
  maj=${tv%%.*}; min=${tv#*.}; min=${min%%.*}
  if [ "$maj" -gt 3 ] 2>/dev/null || { [ "$maj" = 3 ] && [ "${min:-0}" -ge 2 ]; }; then
    ok "tmux $tv is new enough"
  else
    bad "tmux $tv is too old, 3.2 or newer is needed"
  fi
}

if [ "$ROLE" = remote ]; then
  for t in git tmux fzf; do
    if have "$t"; then ok "$t   $(command -v "$t")"
    else bad "$t missing, the remote needs it.  $(pkg_hint "$t")"; fi
  done
  have tmux && tmux_version_ok
  # Not fatal: tmx ls falls back to unaligned output without it.
  if have column; then ok "column   $(command -v column)"
  else warn "no column(1), so 'tmx ls' output will not line up.  $(pkg_hint column)"; fi
else
  if have ssh; then ok "ssh   $(command -v ssh)"
  else bad "ssh missing, the client cannot reach the remote without it"; fi
  if have tmux; then tmux_version_ok
  else warn "no tmux here. Fine for driving the remote; needed only for local sessions and the F12 nesting setup"; fi
  if have pbcopy && have pbpaste; then ok "pbcopy/pbpaste for the clipboard bridge"
  else warn "no pbcopy/pbpaste, so 'tmx clip' will not work on this machine"; fi
fi

# ---------------------------------------------------------------- PATH
step "Working out where your tools live"

# tmx runs from shells that skip your profile, so it needs the real locations
# written down rather than inherited.
PREPEND=""
for t in tmux fzf git; do
  have "$t" || continue
  d=$(dirname -- "$(command -v "$t")")
  case ":$PREPEND:" in *":$d:"*) ;; *) PREPEND="${PREPEND:+$PREPEND:}$d" ;; esac
done
[ -n "$PREPEND" ] && ok "TMX_PATH_PREPEND=$PREPEND" \
                  || warn "no tools found to derive a PATH from"

# ---------------------------------------------------------------- files
step "Installing files"

backup() {  # backup EXISTING INCOMING -- skip when identical
  [ -e "$1" ] || return 0
  cmp -s "$1" "$2" 2>/dev/null && return 0
  run cp -p "$1" "$1.bak.$STAMP"
  [ "$DRY" = 1 ] || ok "backed up $1 -> $1.bak.$STAMP"
}

run mkdir -p "$BIN" "$CFG" "$TMUXCFG"

backup "$BIN/tmx" "$REPO/bin/tmx"
run cp "$REPO/bin/tmx" "$BIN/tmx"
run chmod +x "$BIN/tmx"
ok "$BIN/tmx"

# A legacy ~/.tmux.conf would fight the XDG one over the prefix, silently.
if [ -e "$HOME/.tmux.conf" ]; then
  run mv "$HOME/.tmux.conf" "$HOME/.tmux.conf.bak.$STAMP"
  warn "moved ~/.tmux.conf aside (-> .bak.$STAMP): tmux reads it AS WELL as the new config, and two configs fighting over the prefix is a confusing afternoon"
fi

if [ "$ROLE" = remote ]; then
  backup "$BIN/tmx-status" "$REPO/bin/tmx-status"
  run cp "$REPO/bin/tmx-status" "$BIN/tmx-status"
  run chmod +x "$BIN/tmx-status"
  ok "$BIN/tmx-status"

  run mkdir -p "$CFG/docs"
  run cp "$REPO/docs/tmux-keys.md" "$REPO/docs/tmx-commands.md" "$REPO/docs/gotchas.md" "$CFG/docs/"
  ok "$CFG/docs  (prefix ? and prefix / read these)"

  backup "$TMUXCFG/tmux.conf" "$REPO/tmux/remote.tmux.conf"
  run cp "$REPO/tmux/remote.tmux.conf" "$TMUXCFG/tmux.conf"
  ok "$TMUXCFG/tmux.conf  (remote palette)"

  run touch "$CFG/remote"
  ok "$CFG/remote  (marks this machine as the one that does the work)"
else
  backup "$TMUXCFG/tmux.conf" "$REPO/tmux/client.tmux.conf"
  run cp "$REPO/tmux/client.tmux.conf" "$TMUXCFG/tmux.conf"
  ok "$TMUXCFG/tmux.conf  (client palette, F12 toggle)"

  # ssh/config.client sets ControlPath here and ssh refuses to create it itself,
  # which fails every connection with "cannot bind to path".
  if [ ! -d "$HOME/.ssh/cm" ]; then
    run mkdir -p "$HOME/.ssh/cm"
    run chmod 700 "$HOME/.ssh/cm"
    ok "$HOME/.ssh/cm  (ssh connection-sharing sockets live here)"
  fi
  if [ -e "$CFG/remote" ]; then
    warn "$CFG/remote exists on a CLIENT, so tmx would ssh to itself. Remove it: rm $CFG/remote"
  fi
fi

# ---------------------------------------------------------------- config
step "Your settings"

if [ -e "$CFG/config" ]; then
  ok "$CFG/config exists, left untouched"
  if ! diff -q "$CFG/config" "$REPO/config/config.example" >/dev/null 2>&1; then
    say "   compare with the shipped example for new settings:"
    say "     diff $CFG/config $REPO/config/config.example"
  fi
else
  run cp "$REPO/config/config.example" "$CFG/config"
  ok "$CFG/config created from the example"
  if [ -n "$PREPEND" ]; then
    append "$CFG/config" \
      "" \
      "# Added by install.sh: where tmux, fzf and git actually are on this machine." \
      "TMX_PATH_PREPEND=$PREPEND"
    ok "TMX_PATH_PREPEND written for you"
  fi
fi

# The remote never dials out, so the host alias only matters on the client.
if [ "$ROLE" = client ]; then
  if grep -q '^TMX_REMOTE_HOST=' "$CFG/config" 2>/dev/null; then
    ok "TMX_REMOTE_HOST already set: $(grep '^TMX_REMOTE_HOST=' "$CFG/config" | head -1)"
  elif [ -n "$RHOST" ]; then
    append "$CFG/config" "TMX_REMOTE_HOST=$RHOST"
    ok "TMX_REMOTE_HOST=$RHOST written for you"
  else
    warn "set TMX_REMOTE_HOST in $CFG/config to the ssh alias of your remote"
  fi
fi

if [ "$ROLE" = remote ]; then
  # Old installs had a "roots" file; same format, projects also takes aliases.
  if [ ! -e "$CFG/projects" ] && [ -e "$CFG/roots" ]; then
    run mv "$CFG/roots" "$CFG/projects"
    ok "renamed your old roots file to projects (same format, aliases now work too)"
  fi
  if [ -e "$CFG/projects" ]; then
    ok "$CFG/projects exists, left untouched"
  else
    run cp "$REPO/config/projects" "$CFG/projects"
    ok "$CFG/projects created"
    for d in code src dev projects work repos; do
      [ -d "$HOME/$d" ] || continue
      grep -q "^~/$d\$" "$CFG/projects" 2>/dev/null && continue
      append "$CFG/projects" "~/$d"
      ok "added root ~/$d, it exists here"
    done
  fi
fi

# ---------------------------------------------------------------- font
step "Status line glyphs"

CPS="E0B0 E0B2 E0B3 E0A0 F179 F07B F126 F017 F1DA"
if have fc-list; then
  acc=$(mktemp); first=1
  for cp in $CPS; do
    cur=$(mktemp)
    fc-list ":charset=$cp" family 2>/dev/null | tr ',' '\n' | sed 's/^ *//' \
      | grep -v '^\.' | sort -u > "$cur"
    if [ "$first" = 1 ]; then cp "$cur" "$acc"; first=0
    else comm -12 "$acc" "$cur" > "$acc.n" && mv "$acc.n" "$acc"; fi
    rm -f "$cur"
  done
  if [ -s "$acc" ]; then
    ok "fonts with every glyph: $(tr '\n' ' ' < "$acc")"
    say "   select one of those in your terminal, or the status line shows boxes."
  else
    warn "no installed font covers all nine glyphs."
    say "   install a Nerd Font, or set TMX_GLYPHS=0 in $CFG/config."
  fi
  rm -f "$acc"
else
  warn "no fc-list here, so font coverage cannot be checked automatically"
fi
say ""
say "   These should be nine icons, not boxes, in the terminal you actually use:"
printf '     '
# Octal, not \xNN: POSIX printf takes octal, and macOS printf ignores \x.
printf '\356\202\260 \356\202\262 \356\202\263 \356\202\240 \357\205\271 \357\201\273 \357\204\246 \357\200\227 \357\207\232\n'

# ---------------------------------------------------------------- verify
step "Checking the install"

if have zsh && [ "$DRY" = 0 ]; then
  if zsh -n "$BIN/tmx" 2>/dev/null; then ok "tmx parses"; else bad "tmx does not parse"; fi
  if [ "$ROLE" = remote ]; then
    if zsh -n "$BIN/tmx-status" 2>/dev/null; then ok "tmx-status parses"; else bad "tmx-status does not parse"; fi
  fi
fi

if have tmux && [ "$DRY" = 0 ]; then
  if tmux -f "$TMUXCFG/tmux.conf" -L tmxinstallcheck new-session -d 2>/dev/null; then
    ok "tmux config parses"
    tmux -L tmxinstallcheck kill-server 2>/dev/null || true
  else
    bad "tmux config does not parse"
  fi
fi

# Printing advice here and leaving it undone made the very next command in the
# README ("tmx version") fail with "command not found". Do it instead.
case ":$PATH:" in
  *":$BIN:"*) ok "$BIN is already on your PATH" ;;
  *)
    if grep -q '.local/bin' "$HOME/.zshenv" 2>/dev/null; then
      ok "~/.zshenv already puts $BIN on PATH (open a new terminal for it)"
    else
      append "$HOME/.zshenv" 'export PATH="$HOME/.local/bin:$PATH"'
      ok "added $BIN to PATH in ~/.zshenv, the one file every zsh reads"
      say "         open a NEW terminal, or run: source ~/.zshenv"
    fi ;;
esac

# ssh is the client's whole transport, so prove it now rather than at first use.
if [ "$ROLE" = client ] && [ -n "$RHOST" ] && [ "$DRY" = 0 ]; then
  if ssh -o BatchMode=yes -o ConnectTimeout=5 "$RHOST" true 2>/dev/null; then
    ok "ssh $RHOST works with key auth"
  else
    warn "cannot reach '$RHOST' with key auth yet. In order, the usual causes:"
    say "     1. no key:      ssh-keygen -t ed25519 -f ~/.ssh/client_to_remote_ed25519"
    say "     2. not sent:    ssh-copy-id -i ~/.ssh/client_to_remote_ed25519.pub $RHOST"
    say "     3. no host:     merge $REPO/ssh/config.client into ~/.ssh/config"
    say "                     and fill in the two '# EDIT ME' lines"
    say "     Then 'ssh $RHOST' must log in without a password prompt."
  fi
fi

# ---------------------------------------------------------------- the far side
if [ "$BOTH" = 1 ]; then
  step "Installing on the remote ($RHOST)"
  [ "$ROLE" = client ] || die "--both is for running on the client"
  [ -n "$RHOST" ] || die "--both needs --remote-host=NAME"
  if [ "$DRY" = 1 ]; then
    say "   would copy this repo to $RHOST:~/tmux-remote and run install.sh --role=remote there"
  else
    say "   copying the repo to $RHOST:~/tmux-remote"
    tar -cf - --exclude .git --exclude '*.bak.*' -C "$REPO" . \
      | ssh "$RHOST" 'mkdir -p ~/tmux-remote && tar -xf - -C ~/tmux-remote' \
      || die "cannot reach $RHOST over ssh. Fix 'ssh $RHOST' first."
    say "   running the installer there"
    # Through a login shell, for the same reason tmx does it: plain
    # `ssh host command` reads only ~/.zshenv, so tools in /opt/local/bin look
    # missing and TMX_PATH_PREPEND gets derived from a PATH nobody uses.
    # See docs/gotchas.md #12.
    ssh "$RHOST" '$SHELL -lc "sh ~/tmux-remote/install.sh --role=remote --deploy-target"' \
      || bad "the remote install reported problems"

    say ""
    say "   proving the round trip:"
    if TMX_REMOTE_HOST="$RHOST" "$BIN/tmx" version; then
      ok "both machines answer"
    else
      bad "tmx version could not reach the remote copy"
    fi
  fi
fi

# ---------------------------------------------------------------- done
step "Done"
if [ "$FAIL" -gt 0 ]; then
  say "$FAIL problem(s) above need fixing before this will work."
  exit 1
fi

if [ "$ROLE" = client ]; then
  say "Next:"
  [ -n "$RHOST" ] || say "  - set TMX_REMOTE_HOST in $CFG/config to your ssh alias"
  say "  - check:  tmx version      (both machines, 'in sync')"
  say "  - then:   tmx <a-directory-name-on-the-remote>"
else
  say "Next:"
  if [ "$(uname -s)" = Darwin ]; then
    say "  - System Settings > General > Sharing > Remote Login must be ON,"
    say "    or the client cannot ssh in at all"
  else
    say "  - an ssh server must be running here, or the client cannot get in"
  fi
  say "  - edit $CFG/projects so the picker offers your directories"
  say "  - check:  tmx ls"
fi
exit 0
