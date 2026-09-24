#!/bin/sh
# Parse the installer and check that uninstall removes the install layout.
# No network.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
failures=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

ok() {
  printf 'ok: %s\n' "$*"
}

parse_scripts() {
  shell_bin=$1
  for file in \
    "$ROOT/provinator" \
    "$ROOT"/lib/*.sh \
    "$ROOT"/tests/*.sh \
    "$ROOT"/pins/versions.env
  do
    if ! "$shell_bin" -n "$file"; then
      fail "$shell_bin -n $file"
    fi
  done
  ok "$shell_bin -n"
}

expect_layout_present() {
  prefix=$1
  while read -r _tool rel; do
    [ -n "$rel" ] || continue
    if [ ! -e "$prefix/$rel" ] && [ ! -L "$prefix/$rel" ]; then
      fail "missing layout path $rel"
    fi
    case "$rel" in
      opt/*)
        if [ ! -d "$prefix/$rel" ]; then
          fail "expected directory $rel"
        fi
        ;;
      bin/*)
        if [ ! -f "$prefix/$rel" ]; then
          fail "expected file $rel"
        fi
        ;;
    esac
  done < "$ROOT/pins/layout"
}

expect_layout_absent() {
  prefix=$1
  while read -r _tool rel; do
    [ -n "$rel" ] || continue
    if [ -e "$prefix/$rel" ] || [ -L "$prefix/$rel" ]; then
      fail "layout path still present: $rel"
    fi
  done < "$ROOT/pins/layout"
}

check_checksum_pins() {
  for name in \
    opam-2.6.0-x86_64-linux \
    opam-2.6.0-arm64-linux \
    opam-2.6.0-x86_64-macos \
    opam-2.6.0-arm64-macos \
    elan-x86_64-unknown-linux-gnu.tar.gz \
    elan-aarch64-unknown-linux-gnu.tar.gz \
    elan-x86_64-apple-darwin.tar.gz \
    elan-aarch64-apple-darwin.tar.gz \
    why3-1.8.2.tar.gz \
    rocq-9.2.0.tar.gz \
    openssl-3.5.8.tar.gz \
    strace-7.2.tar.xz \
    LADR-2009-11A.tar.gz
  do
    sum=$(awk -v name="$name" '
      $0 ~ /^[[:space:]]*#/ { next }
      $2 == name { print $1; found = 1; exit }
      END { if (!found) exit 1 }
    ' "$ROOT/pins/checksums.sha256") || {
      fail "missing checksum for $name"
      continue
    }
    case "$sum" in
      *[!0-9a-f]*)
        fail "checksum for $name is not hex"
        ;;
    esac
    if [ "${#sum}" -ne 64 ]; then
      fail "checksum for $name is not 64 hex characters"
    fi
  done
  ok "checksum pins"
}

check_tool_list() {
  expected='opam
coq
why3
easycrypt
elan
prover9
mldsa
strace'
  got=$(awk 'NF && $1 !~ /^#/ { print $1 }' "$ROOT/pins/tools")
  if [ "$got" != "$expected" ]; then
    fail "tool list is not the closed set"
  else
    ok "tool list"
  fi
  while IFS= read -r tool; do
    [ -n "$tool" ] || continue
    count=$(awk -v tool="$tool" '$1 == tool { n++ } END { print n + 0 }' "$ROOT/pins/layout")
    if [ "$count" -lt 1 ]; then
      fail "no layout paths for $tool"
    fi
  done < "$ROOT/pins/tools"
  ok "layout covers every tool"
}

check_disk_boundary() {
  low=$(mktemp -d)
  cat > "$low/df" <<'EOF'
#!/bin/sh
printf '%s\n' 'Filesystem 1024-blocks Used Available Capacity Mounted on'
printf '%s\n' 'mock 99999999 0 8388607 1% /'
EOF
  chmod 755 "$low/df"
  high=$(mktemp -d)
  cat > "$high/df" <<'EOF'
#!/bin/sh
printf '%s\n' 'Filesystem 1024-blocks Used Available Capacity Mounted on'
printf '%s\n' 'mock 99999999 0 8388608 1% /'
EOF
  chmod 755 "$high/df"
  probe=$(mktemp -d)
  # shellcheck source=../lib/common.sh
  . "$ROOT/lib/common.sh"
  # shellcheck source=../lib/disk.sh
  . "$ROOT/lib/disk.sh"
  if [ "$(easycrypt_min_free_kib)" -ne $((8 * 1024 * 1024)) ]; then
    fail "8 GiB threshold is not 8388608 KiB"
  fi
  if (
    PATH="$high:$PATH"
    PREFIX=$probe
    require_easycrypt_disk
  ); then
    ok "8 GiB free is enough to start EasyCrypt"
  else
    fail "exactly 8 GiB free was refused"
  fi
  if (
    PATH="$low:$PATH"
    PREFIX=$probe
    require_easycrypt_disk
  ) 2>/dev/null; then
    fail "under 8 GiB was accepted"
  else
    ok "under 8 GiB is refused"
  fi
  rm -rf "$low" "$high" "$probe"
}

check_easycrypt_does_not_start() {
  fake=$(mktemp -d)
  cat > "$fake/df" <<'EOF'
#!/bin/sh
printf '%s\n' 'Filesystem 1024-blocks Used Available Capacity Mounted on'
printf '%s\n' 'mock 99999999 0 1024 1% /'
EOF
  chmod 755 "$fake/df"
  prefix=$(mktemp -d)
  err=$(mktemp)
  if PATH="$fake:$PATH" "$ROOT/provinator" --prefix "$prefix" install easycrypt >"$err" 2>&1; then
    fail "EasyCrypt install started with 1024 KiB free"
  else
    ok "EasyCrypt install exits when free disk is under 8 GiB"
  fi
  if ! grep -q 'refused' "$err"; then
    fail "refusal message missing"
    cat "$err" >&2
  fi
  if [ -e "$prefix/opt/easycrypt" ] || [ -e "$prefix/bin/opam" ] || [ -e "$prefix/bin/easycrypt" ]; then
    fail "EasyCrypt install created files after the disk refusal"
  else
    ok "EasyCrypt refusal creates no install paths"
  fi
  rm -rf "$fake" "$prefix" "$err"
}

check_strace_darwin() {
  fake=$(mktemp -d)
  cat > "$fake/uname" <<'EOF'
#!/bin/sh
if [ "$1" = "-s" ]; then
  printf '%s\n' Darwin
  exit 0
fi
if [ "$1" = "-m" ]; then
  printf '%s\n' arm64
  exit 0
fi
printf '%s\n' Darwin
EOF
  chmod 755 "$fake/uname"
  prefix=$(mktemp -d)
  if PATH="$fake:$PATH" "$ROOT/provinator" --prefix "$prefix" install strace >/tmp/provinator-strace-err 2>&1; then
    fail "strace install succeeded on Darwin"
  else
    ok "strace install fails on Darwin"
  fi
  if [ -e "$prefix/opt/strace" ] || [ -e "$prefix/bin/strace" ]; then
    fail "strace layout was created on Darwin"
  else
    ok "strace refusal creates no install paths"
  fi
  rm -rf "$fake" "$prefix" /tmp/provinator-strace-err
}

check_inverse() {
  prefix=$(mktemp -d)
  other=$(mktemp -d)
  outside=$(mktemp -d)
  printf '%s\n' keep > "$prefix/keep-me"
  mkdir -p "$prefix/opt"
  printf '%s\n' keep > "$prefix/opt/user-file"
  printf '%s\n' outside > "$outside/sentinel"
  printf '%s\n' other > "$other/sentinel"

  "$ROOT/provinator" --prefix "$prefix" install --layout-only >/dev/null
  expect_layout_present "$prefix"
  "$ROOT/provinator" --prefix "$prefix" install --layout-only >/dev/null
  expect_layout_present "$prefix"
  ok "layout-only install is idempotent"

  "$ROOT/provinator" --prefix "$prefix" uninstall --dry-run >/dev/null
  expect_layout_present "$prefix"
  ok "uninstall --dry-run leaves the layout"

  "$ROOT/provinator" --prefix "$prefix" uninstall coq >/dev/null
  for rel in opt/coq bin/coq bin/coqc bin/coqtop; do
    if [ -e "$prefix/$rel" ] || [ -L "$prefix/$rel" ]; then
      fail "coq path remained after uninstall coq: $rel"
    fi
  done
  for rel in bin/opam opt/opam-root bin/why3 opt/why3; do
    if [ ! -e "$prefix/$rel" ] && [ ! -L "$prefix/$rel" ]; then
      fail "unrelated path removed with coq: $rel"
    fi
  done
  ok "uninstall coq removes only the coq layout"

  "$ROOT/provinator" --prefix "$other" uninstall >/dev/null
  if [ ! -f "$prefix/bin/opam" ]; then
    fail "uninstall of another prefix removed this prefix"
  fi
  ok "uninstall stays inside its prefix"

  "$ROOT/provinator" --prefix "$prefix" uninstall >/dev/null
  expect_layout_absent "$prefix"
  if [ -e "$prefix/var/receipts/opam" ] || [ -e "$prefix/var/receipts/mldsa" ] || [ -e "$prefix/var/receipts/strace" ]; then
    fail "receipts remained after uninstall"
  fi
  if [ ! -f "$prefix/keep-me" ] || [ ! -f "$prefix/opt/user-file" ]; then
    fail "uninstall removed files it did not install"
  fi
  if [ ! -f "$outside/sentinel" ] || [ ! -f "$other/sentinel" ]; then
    fail "uninstall removed files outside the prefix"
  fi
  "$ROOT/provinator" --prefix "$prefix" uninstall >/dev/null
  ok "uninstall is the inverse of the install layout"

  rm -rf "$prefix" "$other" "$outside"
}

parse_scripts sh
if command -v dash >/dev/null 2>&1; then
  parse_scripts dash
fi

check_tool_list
check_checksum_pins
check_disk_boundary
check_easycrypt_does_not_start
check_strace_darwin
check_inverse

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: %s check(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'PASS\n'
