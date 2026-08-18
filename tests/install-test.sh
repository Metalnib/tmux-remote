#!/bin/sh
# tests/install-test.sh -- integration test for install.sh, in Docker.
#
#   tests/install-test.sh            build, run everything, clean up
#   tests/install-test.sh --keep     leave the containers running afterwards
#
# A version-consistency check runs first, without Docker.
#
# Part 1 exercises the installer alone in a container: missing dependencies,
# a clean install of each role, re-running, the legacy migrations, --dry-run,
# --uninstall, and that `tmx ls` reports real values afterwards.
#
# Part 2 is the real thing: two containers, sshd between them, the shipped
# ssh/config.client edited the way the README says, and `install.sh --both` run on
# the client using the nickname that template defines. It has to end with `tmx version`
# reporting "in sync" and a session actually created on the remote by a
# plain `tmx <name>` typed on the client.
#
# Needs Docker. Development tool only; nothing here runs at install time.

set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
IMG=tmxtest-img
NET=tmxtest-net
KEEP=${1:-}

PASS=0; FAILED=0

say()  { printf '%s\n' "$*"; }
pass() { PASS=$((PASS+1));    printf '  pass  %s\n' "$*"; }
fail() { FAILED=$((FAILED+1)); printf '  FAIL  %s\n' "$*"; }

cleanup() {
  [ "$KEEP" = "--keep" ] && { say ""; say "kept: containers tmxtest-client/tmxtest-remote, network $NET"; return; }
  docker rm -f tmxtest-client tmxtest-remote >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Runs before Docker, because it needs neither Docker nor a container: the
# release name lives in two files and they drift silently. CHANGELOG.md promises
# in its own header that they match, and `tmx version` is what tells you whether
# the two machines are in sync, so a stale TMX_VERSION makes that check lie.
say "== Version consistency"
SV=$(sed -n "s/^typeset -g TMX_VERSION='\(.*\)'.*/\1/p" "$REPO/bin/tmx" | head -1)
CV=$(sed -n 's/^## //p' "$REPO/CHANGELOG.md" | head -1)
if [ -n "$SV" ] && [ "$SV" = "$CV" ]; then
  pass "TMX_VERSION and the newest CHANGELOG heading agree ($SV)"
else
  fail "TMX_VERSION is '$SV', newest CHANGELOG heading is '$CV'"
fi

command -v docker >/dev/null 2>&1 || { say "docker not found"; exit 1; }

say "== Building the test image (debian + zsh/tmux/fzf/git/sshd)"
docker build -q -t "$IMG" - <<'EOF' >/dev/null
FROM debian:stable-slim
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      zsh tmux fzf git openssh-server openssh-client ca-certificates && \
    rm -rf /var/lib/apt/lists/* && mkdir -p /run/sshd
EOF

# in_fresh SCRIPT -- run sh -c SCRIPT in a throwaway full container, repo at /repo
in_fresh() {
  docker run --rm -v "$REPO":/repo:ro "$IMG" sh -c "$1"
}

say ""
say "== Part 1: the installer alone"

# 1. missing dependencies are named, with the right package hint, and exit 1
out=$(docker run --rm -v "$REPO":/repo:ro debian:stable-slim \
        sh /repo/install.sh --role=remote 2>&1) && rc=0 || rc=$?
if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'zsh missing' \
                 && printf '%s' "$out" | grep -q 'apt install'; then
  pass "bare image: missing deps named with apt hint, exit 1"
else
  fail "bare image: expected exit 1 + 'zsh missing' + apt hint (got rc=$rc)"
fi

# 2. clean remote install: right files, marker, PATH derived, projects seeded
out=$(in_fresh '
  mkdir -p /root/code
  sh /repo/install.sh --role=remote >/tmp/o 2>&1 || { cat /tmp/o; exit 9; }
  test -x /root/.local/bin/tmx || exit 1
  test -x /root/.local/bin/tmx-status || exit 2
  test -f /root/.config/tmux/tmux.conf || exit 3
  test -e /root/.config/tmx/remote || exit 4
  test -f /root/.config/tmx/docs/tmx-commands.md || exit 5
  grep -q "^TMX_PATH_PREPEND=" /root/.config/tmx/config || exit 6
  grep -q "^~/code$" /root/.config/tmx/projects || exit 7
  zsh -n /root/.local/bin/tmx || exit 8
') && pass "remote role: all files land, config derived, tmx parses" \
  || fail "remote role install (exit $?)"

# 3. clean client install: only the client files, host alias written
in_fresh '
  sh /repo/install.sh --role=client --remote-host=myremote >/tmp/o 2>&1 || { cat /tmp/o; exit 9; }
  test -x /root/.local/bin/tmx || exit 1
  test ! -e /root/.local/bin/tmx-status || exit 2   # remote-only
  test ! -e /root/.config/tmx/remote || exit 3      # remote-only
  test ! -e /root/.config/tmx/projects || exit 4    # remote-only
  grep -q "^TMX_REMOTE_HOST=myremote$" /root/.config/tmx/config || exit 5
' && pass "client role: nothing remote-only lands, host alias written" \
  || fail "client role install (exit $?)"

# 4. re-run is idempotent: no backups, user config untouched
in_fresh '
  sh /repo/install.sh --role=remote >/dev/null 2>&1
  echo "TMX_GLYPHS=0" >> /root/.config/tmx/config
  sh /repo/install.sh --role=remote >/tmp/o 2>&1
  find /root -name "*.bak.*" | grep -q . && exit 1
  grep -q "^TMX_GLYPHS=0$" /root/.config/tmx/config || exit 2
  grep -q "left untouched" /tmp/o || exit 3
' && pass "re-run: no backups, edited config kept" \
  || fail "re-run idempotency (exit $?)"

# 5. legacy migrations: roots file renamed, ~/.tmux.conf moved aside
in_fresh '
  mkdir -p /root/.config/tmx
  printf "~\n" > /root/.config/tmx/roots
  printf "set -g prefix C-a\n" > /root/.tmux.conf
  sh /repo/install.sh --role=remote >/tmp/o 2>&1
  test -f /root/.config/tmx/projects || exit 1
  test ! -e /root/.config/tmx/roots || exit 2
  test ! -e /root/.tmux.conf || exit 3
  ls /root/.tmux.conf.bak.* >/dev/null 2>&1 || exit 4
' && pass "legacy roots renamed to projects, ~/.tmux.conf moved aside" \
  || fail "legacy migrations (exit $?)"

# 6. --dry-run creates nothing
in_fresh '
  sh /repo/install.sh --role=remote --dry-run >/dev/null 2>&1
  test ! -e /root/.local/bin/tmx || exit 1
  test ! -e /root/.config/tmx || exit 2
' && pass "--dry-run touches nothing" \
  || fail "--dry-run created files (exit $?)"

# 7. --uninstall removes what install put, keeps the user's files
in_fresh '
  sh /repo/install.sh --role=remote >/dev/null 2>&1
  sh /repo/install.sh --uninstall >/dev/null 2>&1
  test ! -e /root/.local/bin/tmx || exit 1
  test ! -e /root/.local/bin/tmx-status || exit 2
  test ! -e /root/.config/tmx/remote || exit 3
  test -f /root/.config/tmx/config || exit 4
  test -f /root/.config/tmx/projects || exit 5
' && pass "--uninstall: bins and marker gone, config and projects kept" \
  || fail "--uninstall (exit $?)"

# 8. no role, no terminal: refuses with instructions instead of hanging
out=$(in_fresh 'sh /repo/install.sh 2>&1') && rc=0 || rc=$?
if [ "$rc" != 0 ] && printf '%s' "$out" | grep -q -- '--role=remote'; then
  pass "no role + no tty: refuses and names the flag"
else
  fail "no role + no tty: expected refusal naming --role (rc=$rc)"
fi

# 9. `tmx ls` reports the truth. tmux escapes control bytes in format output, so
# a tab-delimited record silently collapses into one field on some versions and
# every column after the first is wrong rather than empty. The awk checks read
# the fields the way a person reads the columns. See docs/gotchas.md.
in_fresh '
  mkdir -p "/root/code/api" "/root/code/odd|dir"
  sh /repo/install.sh --role=remote >/dev/null 2>&1
  export PATH=/root/.local/bin:$PATH
  tmx code-api >/dev/null 2>&1
  tmx /root/code/odd\|dir >/dev/null 2>&1
  tmux rename-window -t "=code-api:" "odd|winname" >/dev/null 2>&1

  tmx ls > /tmp/ls 2>&1 || exit 1
  head -1 /tmp/ls | grep -q "^SESSION" || exit 2
  # Field positions are checked by what each value sits next to, so this reads
  # the same whether column(1) aligned the output or not.
  # DIR must be the directory, not a whole collapsed record
  grep -Eq "^code-api[[:space:]]+~/code/api[[:space:]]" /tmp/ls || exit 3
  # a printable delimiter inside a value must not shift the columns
  grep -Eq "^code-odd-dir[[:space:]]+~/code/odd\|dir[[:space:]]" /tmp/ls || exit 4
  # UP is arithmetic on a field, so a collapsed record gives a nonsense age;
  # WINDOWS is last, which pins UP to the field before it
  grep -Eq "^code-api[[:space:]].*[[:space:]][0-9]+[smhd][[:space:]]+1:odd\|winname\*[[:space:]]*$" /tmp/ls || exit 5

  tmx ls -w > /tmp/lsw 2>&1 || exit 7
  grep -q "odd|winname" /tmp/lsw || exit 8

  # the same record feeds the one-session-per-directory guard
  printf "myapi=/root/code/api\n" >> /root/.config/tmx/projects
  tmx myapi 2>&1 | grep -q "already open as .code-api." || exit 9
  [ "$(tmux list-sessions | wc -l)" = 2 ] || exit 10
' && pass "tmx ls: real dir, delimiter-proof columns, dir guard still holds" \
  || fail "tmx ls output (exit $?)"

say ""
say "== Part 2: two containers, ssh between them, install.sh --both"

docker network create "$NET" >/dev/null 2>&1 || true
docker rm -f tmxtest-client tmxtest-remote >/dev/null 2>&1 || true

docker run -d --name tmxtest-remote --network "$NET" --hostname remote "$IMG" \
  sh -c 'ssh-keygen -A && exec /usr/sbin/sshd -D -e' >/dev/null
docker run -d --name tmxtest-client --network "$NET" --hostname client \
  -v "$REPO":/repo:ro "$IMG" sleep 900 >/dev/null

# Step 1 of the README, followed literally: the key it tells you to make, the
# ~/.ssh/cm directory it warns ssh will not create, the shipped template, and the
# two lines marked "# EDIT ME". So this covers the documented path rather than a
# hand-rolled config, including IdentitiesOnly, ControlPath and AddressFamily.
PUB=$(docker exec tmxtest-client sh -c '
  mkdir -p /root/.ssh/cm && chmod 700 /root/.ssh /root/.ssh/cm
  ssh-keygen -q -t ed25519 -N "" -f /root/.ssh/client_to_remote_ed25519 2>/dev/null || true
  cat /repo/ssh/config.client >> /root/.ssh/config
  sed -i "s|^    User youruser.*|    User root|" /root/.ssh/config
  sed -i "s|^    HostName remote[.]local.*|    HostName remote|" /root/.ssh/config
  # the README has a human answer "yes" to the fingerprint prompt; this is that,
  # non-interactively
  printf "\nHost *\n    StrictHostKeyChecking accept-new\n" >> /root/.ssh/config
  chmod 600 /root/.ssh/config
  cat /root/.ssh/client_to_remote_ed25519.pub')
docker exec tmxtest-remote sh -c \
  "mkdir -p /root/.ssh && printf '%s\n' '$PUB' > /root/.ssh/authorized_keys && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys"

# the nickname the template defines has to work before anything else can
docker exec tmxtest-client ssh -o BatchMode=yes remote-box true 2>/dev/null \
  && pass "the shipped ssh template: 'ssh remote-box' logs in with no password" \
  || fail "ssh remote-box failed using ssh/config.client as documented"

# something to open a session on, over there
docker exec tmxtest-remote sh -c 'mkdir -p /root/code/api'

# the flagship path from the README, with the nickname the template defines
if out=$(docker exec tmxtest-client sh /repo/install.sh --both --remote-host=remote-box 2>&1); then
  pass "--both ran to completion"
else
  fail "--both exited non-zero"; printf '%s\n' "$out" | tail -20 | sed 's/^/        /'
fi

printf '%s' "$out" | grep -q 'in sync' \
  && pass "tmx version round trip says 'in sync'" \
  || fail "no 'in sync' in the --both output"

docker exec tmxtest-remote sh -c \
  'test -x /root/.local/bin/tmx-status && test -e /root/.config/tmx/remote && test -f /root/.config/tmx/projects' \
  && pass "remote container: files installed over ssh" \
  || fail "remote container: expected files missing"

# the end-to-end moment: a plain `tmx <name>` on the client creates a live
# session on the remote. No tty here, so the final attach fails; the session
# must exist anyway.
docker exec tmxtest-client /root/.local/bin/tmx code-api >/dev/null 2>&1 || true
docker exec tmxtest-remote tmux has-session -t=code-api 2>/dev/null \
  && pass "tmx code-api on the client created the session on the remote" \
  || fail "no code-api session on the remote"

docker exec tmxtest-remote sh -c \
  'tmux list-windows -t "=code-api" -F "#{window_name}" | grep -qx shell' \
  && pass "the session has its shell window" \
  || fail "shell window missing"

say ""
say "== $PASS passed, $FAILED failed"
[ "$FAILED" = 0 ]
