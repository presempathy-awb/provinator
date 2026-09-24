# Shared helpers for provinator. Sourced by the command; not executed directly.

die() {
  printf 'provinator: %s\n' "$*" >&2
  exit 1
}

info() {
  printf 'provinator: %s\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1
  Install it with the system package manager. provinator does not install it."
}

require_c_compiler() {
  if command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || command -v clang >/dev/null 2>&1; then
    return 0
  fi
  die "a C compiler (cc, gcc, or clang) must already be installed.
  provinator does not install or remove system compilers.
  provinator install --help"
}

c_compiler() {
  if command -v cc >/dev/null 2>&1; then
    printf '%s\n' cc
    return 0
  fi
  if command -v gcc >/dev/null 2>&1; then
    printf '%s\n' gcc
    return 0
  fi
  if command -v clang >/dev/null 2>&1; then
    printf '%s\n' clang
    return 0
  fi
  die "a C compiler (cc, gcc, or clang) must already be installed."
}

host_os() {
  uname -s
}

host_arch() {
  uname -m
}

job_count() {
  jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '%s\n' 1)
  case "$jobs" in
    ''|*[!0-9]*) jobs=1 ;;
  esac
  printf '%s\n' "$jobs"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
    return 0
  fi
  die "sha256sum or shasum is required to verify downloads."
}

checksum_of() {
  name=$1
  sum=$(awk -v name="$name" '
    $0 ~ /^[[:space:]]*#/ { next }
    $0 ~ /^[[:space:]]*$/ { next }
    $2 == name { print $1; found = 1; exit }
    END { if (!found) exit 1 }
  ' "$ROOT/pins/checksums.sha256") || die "no vendored checksum for $name"
  printf '%s\n' "$sum"
}

fetch_verified() {
  url=$1
  dest=$2
  name=$3
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$dest" "$url" || die "download failed: $url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$dest" "$url" || die "download failed: $url"
  else
    die "curl or wget is required to download $name
  provinator install --help"
  fi
  expect=$(checksum_of "$name")
  got=$(sha256_file "$dest")
  if [ "$got" != "$expect" ]; then
    die "checksum mismatch for $name
  expected $expect
  got      $got"
  fi
}

known_tool() {
  awk -v name="$1" '$0 == name { found = 1; exit } END { exit !found }' "$ROOT/pins/tools"
}

layout_rels() {
  awk -v tool="$1" '$1 == tool { print $2 }' "$ROOT/pins/layout"
}

assert_safe_prefix() {
  case "$PREFIX" in
    /*) ;;
    *) die "prefix must be an absolute path: $PREFIX" ;;
  esac
  case "$PREFIX" in
    */) PREFIX=${PREFIX%/} ;;
  esac
  case "$PREFIX" in
    /|/usr|/usr/local|/usr/bin|/usr/lib|/usr/lib64|/bin|/sbin|/lib|/lib64|/opt|/opt/homebrew|/nix|/System|/Applications|/tmp|/var/tmp|/private/tmp)
      die "refusing prefix $PREFIX
  Use a user prefix such as \$HOME/.local/provinator."
      ;;
  esac
  if [ -n "${HOME:-}" ] && [ "$PREFIX" = "$HOME" ]; then
    die "refusing to use \$HOME as the prefix
  Use a user prefix such as \$HOME/.local/provinator."
  fi
  case "$PREFIX" in
    *..*) die "refusing prefix that contains .." ;;
  esac
}

prefix_physical() {
  if [ ! -d "$PREFIX" ]; then
    return 0
  fi
  phys=$(CDPATH= cd -- "$PREFIX" && pwd -P) || die "cannot resolve prefix $PREFIX"
  case "$phys" in
    /|/usr|/usr/local|/usr/bin|/usr/lib|/usr/lib64|/bin|/sbin|/lib|/lib64|/opt|/opt/homebrew|/nix|/System|/Applications|/tmp|/var/tmp|/private/tmp)
      die "refusing prefix $PREFIX (resolves to $phys)"
      ;;
  esac
  if [ -n "${HOME:-}" ] && [ "$phys" = "$HOME" ]; then
    die "refusing prefix $PREFIX (resolves to \$HOME)"
  fi
  PREFIX_PHYS=$phys
}

receipt_file() {
  printf '%s\n' "$PREFIX/var/receipts/$1"
}

already_installed() {
  [ -f "$(receipt_file "$1")" ]
}

write_receipt() {
  tool=$1
  shift
  mkdir -p "$PREFIX/var/receipts"
  receipt=$(receipt_file "$tool")
  : > "$receipt"
  for rel in "$@"; do
    case "$rel" in
      ''|/*|*..*) die "refusing to record path $rel" ;;
    esac
    printf '%s\n' "$rel" >> "$receipt"
  done
  printf '%s\n' "var/receipts/$tool" >> "$receipt"
}

layout_paths() {
  tool=$1
  layout_rels "$tool"
  printf '%s\n' "var/receipts/$tool"
}

materialize_tool() {
  tool=$1
  mkdir -p "$PREFIX/bin" "$PREFIX/opt" "$PREFIX/var/receipts"
  receipt=$(receipt_file "$tool")
  : > "$receipt"
  layout_rels "$tool" | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    case "$rel" in
      bin/*)
        : > "$PREFIX/$rel"
        ;;
      opt/*)
        mkdir -p "$PREFIX/$rel"
        ;;
      *)
        mkdir -p "$(dirname "$PREFIX/$rel")"
        : > "$PREFIX/$rel"
        ;;
    esac
  done
  layout_rels "$tool" >> "$receipt"
  printf '%s\n' "var/receipts/$tool" >> "$receipt"
}

remove_under_prefix() {
  target=$1
  case "$target" in
    "$PREFIX"/*) ;;
    *) die "refusing to remove $target (outside $PREFIX)" ;;
  esac
  case "$target" in
    *..*) die "refusing to remove $target" ;;
  esac
  if [ "$dry_run" -eq 1 ]; then
    printf 'remove %s\n' "$target"
    return 0
  fi
  if [ -L "$target" ]; then
    rm -f "$target"
    return 0
  fi
  if [ -d "$target" ]; then
    real=$(CDPATH= cd -- "$target" && pwd -P) || return 0
    case "$real" in
      "$PREFIX_PHYS"/*) ;;
      *) die "refusing to remove $target (real path $real is outside $PREFIX_PHYS)" ;;
    esac
    rm -rf "$target"
    return 0
  fi
  if [ -e "$target" ]; then
    rm -f "$target"
  fi
}

uninstall_tool() {
  tool=$1
  receipt=$(receipt_file "$tool")
  if [ ! -f "$receipt" ]; then
    info "$tool: not installed"
    return 0
  fi
  copy=$(mktemp)
  cp "$receipt" "$copy"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    case "$rel" in
      /*|*..*) die "receipt for $tool contains an unsafe path: $rel" ;;
    esac
    remove_under_prefix "$PREFIX/$rel"
  done < "$copy"
  rm -f "$copy"
  if [ "$dry_run" -eq 0 ]; then
    info "removed $tool"
  fi
}

link_tool_bins() {
  switch_bin=$1
  shift
  for name in "$@"; do
    if [ -e "$switch_bin/$name" ] || [ -L "$switch_bin/$name" ]; then
      rm -f "$PREFIX/bin/$name"
      ln -s "$switch_bin/$name" "$PREFIX/bin/$name"
    fi
  done
}

opam_asset_name() {
  os=$1
  arch=$2
  case "$os:$arch" in
    Linux:x86_64) printf '%s\n' "opam-${OPAM_VERSION}-x86_64-linux" ;;
    Linux:aarch64|Linux:arm64) printf '%s\n' "opam-${OPAM_VERSION}-arm64-linux" ;;
    Darwin:x86_64) printf '%s\n' "opam-${OPAM_VERSION}-x86_64-macos" ;;
    Darwin:arm64|Darwin:aarch64) printf '%s\n' "opam-${OPAM_VERSION}-arm64-macos" ;;
    *) die "unsupported platform for opam: $os $arch
  Supported: Linux and macOS, x86_64 and arm64.
  provinator install --help" ;;
  esac
}

elan_asset_name() {
  os=$1
  arch=$2
  case "$os:$arch" in
    Linux:x86_64) printf '%s\n' "elan-x86_64-unknown-linux-gnu.tar.gz" ;;
    Linux:aarch64|Linux:arm64) printf '%s\n' "elan-aarch64-unknown-linux-gnu.tar.gz" ;;
    Darwin:x86_64) printf '%s\n' "elan-x86_64-apple-darwin.tar.gz" ;;
    Darwin:arm64|Darwin:aarch64) printf '%s\n' "elan-aarch64-apple-darwin.tar.gz" ;;
    *) die "unsupported platform for elan: $os $arch
  Supported: Linux and macOS, x86_64 and arm64.
  provinator install --help" ;;
  esac
}
