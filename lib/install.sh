# Install and uninstall implementations. Sourced by the command.

opam_cmd() {
  OPAMROOT="$PREFIX/opt/opam-root" \
    OPAMYES=1 \
    OPAMCOLOR=never \
    "$PREFIX/bin/opam" "$@"
}

ensure_dirs() {
  mkdir -p "$PREFIX/bin" "$PREFIX/opt" "$PREFIX/var/cache"
}

ensure_opam() {
  if ! already_installed opam; then
    install_opam
  fi
  if [ ! -x "$PREFIX/bin/opam" ]; then
    die "opam is not installed under $PREFIX
  provinator install opam"
  fi
}

create_switch() {
  dest=$1
  if [ -e "$dest" ]; then
    die "switch directory already exists: $dest
  provinator uninstall $(basename "$dest")"
  fi
  opam_cmd switch create "$dest" "ocaml-base-compiler.${OCAML_COMPILER}" --yes
}

install_opam() {
  if already_installed opam; then
    info "opam: already installed"
    return 0
  fi
  if [ "$layout_only" -eq 1 ]; then
    materialize_tool opam
    info "opam: layout recorded"
    return 0
  fi
  require_cmd uname
  asset=$(opam_asset_name "$(host_os)" "$(host_arch)")
  ensure_dirs
  work=$(mktemp -d "${TMPDIR:-/tmp}/provinator.XXXXXX")
  fetch_verified "$OPAM_BASE_URL/$asset" "$work/$asset" "$asset"
  mkdir -p "$PREFIX/bin"
  cp "$work/$asset" "$PREFIX/bin/opam"
  chmod 755 "$PREFIX/bin/opam"
  rm -rf "$work"
  opam_cmd init \
    --root "$PREFIX/opt/opam-root" \
    --bare \
    --no-setup \
    --disable-sandboxing \
    --yes
  # shellcheck disable=SC2046
  write_receipt opam $(layout_rels opam)
  info "installed opam"
}

install_coq() {
  if already_installed coq; then
    info "coq: already installed"
    return 0
  fi
  if [ "$layout_only" -eq 1 ]; then
    materialize_tool coq
    info "coq: layout recorded"
    return 0
  fi
  require_c_compiler
  require_cmd make
  ensure_opam
  ensure_dirs
  create_switch "$PREFIX/opt/coq"
  opam_cmd install --switch "$PREFIX/opt/coq" --yes "coq.${COQ_VERSION}"
  link_tool_bins "$PREFIX/opt/coq/bin" coq coqc coqtop coqdep coq_makefile rocq
  # shellcheck disable=SC2046
  write_receipt coq $(layout_rels coq) bin/coqdep bin/coq_makefile bin/rocq
  info "installed coq"
}

install_why3() {
  if already_installed why3; then
    info "why3: already installed"
    return 0
  fi
  if [ "$layout_only" -eq 1 ]; then
    materialize_tool why3
    info "why3: layout recorded"
    return 0
  fi
  require_c_compiler
  require_cmd make
  ensure_opam
  ensure_dirs
  create_switch "$PREFIX/opt/why3"
  opam_cmd install --switch "$PREFIX/opt/why3" --yes "why3.${WHY3_VERSION}"
  link_tool_bins "$PREFIX/opt/why3/bin" why3
  # shellcheck disable=SC2046
  write_receipt why3 $(layout_rels why3)
  info "installed why3"
}

install_easycrypt() {
  if already_installed easycrypt; then
    info "easycrypt: already installed"
    return 0
  fi
  if [ "$layout_only" -eq 1 ]; then
    materialize_tool easycrypt
    info "easycrypt: layout recorded"
    return 0
  fi
  require_easycrypt_disk
  require_cmd git
  require_c_compiler
  require_cmd make
  ensure_opam
  ensure_dirs
  create_switch "$PREFIX/opt/easycrypt"
  opam_cmd pin add \
    --yes \
    --no-action \
    --switch "$PREFIX/opt/easycrypt" \
    --root "$PREFIX/opt/opam-root" \
    easycrypt \
    "git+${EASYCRYPT_GIT_URL}#${EASYCRYPT_COMMIT}"
  opam_cmd install --switch "$PREFIX/opt/easycrypt" --yes easycrypt
  link_tool_bins "$PREFIX/opt/easycrypt/bin" easycrypt
  # shellcheck disable=SC2046
  write_receipt easycrypt $(layout_rels easycrypt)
  info "installed easycrypt"
}

install_elan() {
  if already_installed elan; then
    info "elan: already installed"
    return 0
  fi
  if [ "$layout_only" -eq 1 ]; then
    materialize_tool elan
    info "elan: layout recorded"
    return 0
  fi
  require_cmd tar
  asset=$(elan_asset_name "$(host_os)" "$(host_arch)")
  ensure_dirs
  work=$(mktemp -d "${TMPDIR:-/tmp}/provinator.XXXXXX")
  fetch_verified "$ELAN_BASE_URL/$asset" "$work/$asset" "$asset"
  tar -xzf "$work/$asset" -C "$work"
  init=
  for candidate in "$work/elan-init" "$work"/*/elan-init; do
    if [ -f "$candidate" ]; then
      init=$candidate
      break
    fi
  done
  if [ -z "$init" ]; then
    rm -rf "$work"
    die "elan-init was not in $asset"
  fi
  chmod 755 "$init"
  ELAN_HOME="$PREFIX/opt/elan" "$init" -y \
    --default-toolchain "$LEAN_TOOLCHAIN" \
    --no-modify-path \
    || {
      rm -rf "$work"
      die "elan-init failed"
    }
  rm -rf "$work"
  extras=
  if [ -d "$PREFIX/opt/elan/bin" ]; then
    for bin in "$PREFIX/opt/elan/bin"/*; do
      if [ -e "$bin" ] || [ -L "$bin" ]; then
        name=$(basename "$bin")
        rm -f "$PREFIX/bin/$name"
        ln -s "$bin" "$PREFIX/bin/$name"
        extras="$extras bin/$name"
      fi
    done
  fi
  # shellcheck disable=SC2086
  write_receipt elan $(layout_rels elan) $extras
  info "installed elan"
}

install_prover9() {
  if already_installed prover9; then
    info "prover9: already installed"
    return 0
  fi
  if [ "$layout_only" -eq 1 ]; then
    materialize_tool prover9
    info "prover9: layout recorded"
    return 0
  fi
  require_c_compiler
  require_cmd make
  require_cmd tar
  ensure_dirs
  work=$(mktemp -d "${TMPDIR:-/tmp}/provinator.XXXXXX")
  fetch_verified "$PROVER9_URL" "$work/LADR-2009-11A.tar.gz" "LADR-2009-11A.tar.gz"
  tar -xzf "$work/LADR-2009-11A.tar.gz" -C "$work"
  src=$work/LADR-2009-11A
  if [ ! -d "$src" ]; then
    rm -rf "$work"
    die "LADR-2009-11A directory missing from the official tarball"
  fi
  (
    cd "$src" || exit 1
    make CC="$(c_compiler)" XFLAGS=-fcommon all
  ) || {
    rm -rf "$work"
    die "Prover9 build failed"
  }
  mkdir -p "$PREFIX/opt/prover9/bin"
  extras=
  for bin in "$src/bin"/*; do
    if [ -f "$bin" ] && [ -x "$bin" ]; then
      name=$(basename "$bin")
      cp "$bin" "$PREFIX/opt/prover9/bin/$name"
      chmod 755 "$PREFIX/opt/prover9/bin/$name"
      rm -f "$PREFIX/bin/$name"
      ln -s "$PREFIX/opt/prover9/bin/$name" "$PREFIX/bin/$name"
      extras="$extras bin/$name"
    fi
  done
  rm -rf "$work"
  if [ ! -x "$PREFIX/opt/prover9/bin/prover9" ] || [ ! -x "$PREFIX/opt/prover9/bin/mace4" ]; then
    die "Prover9 build did not produce prover9 and mace4"
  fi
  # shellcheck disable=SC2086
  write_receipt prover9 $(layout_rels prover9) $extras
  info "installed prover9"
}

install_mldsa() {
  if already_installed mldsa; then
    info "mldsa: already installed"
    return 0
  fi
  if [ "$layout_only" -eq 1 ]; then
    materialize_tool mldsa
    info "mldsa: layout recorded"
    return 0
  fi
  require_c_compiler
  require_cmd make
  require_cmd perl
  require_cmd tar
  ensure_dirs
  work=$(mktemp -d "${TMPDIR:-/tmp}/provinator.XXXXXX")
  fetch_verified "$OPENSSL_URL" "$work/openssl-${OPENSSL_VERSION}.tar.gz" "openssl-${OPENSSL_VERSION}.tar.gz"
  tar -xzf "$work/openssl-${OPENSSL_VERSION}.tar.gz" -C "$work"
  src=$work/openssl-${OPENSSL_VERSION}
  if [ ! -d "$src" ]; then
    rm -rf "$work"
    die "OpenSSL source directory missing from the official tarball"
  fi
  jobs=$(job_count)
  (
    cd "$src" || exit 1
    ./config \
      --prefix="$PREFIX/opt/openssl" \
      --openssldir="$PREFIX/opt/openssl/ssl" \
      --libdir=lib
    make -j"$jobs"
    make install_sw
  ) || {
    rm -rf "$work"
    die "OpenSSL build failed"
  }
  rm -rf "$work"
  if [ ! -x "$PREFIX/opt/openssl/bin/openssl" ]; then
    die "OpenSSL build did not produce bin/openssl"
  fi
  rm -f "$PREFIX/bin/openssl"
  ln -s "$PREFIX/opt/openssl/bin/openssl" "$PREFIX/bin/openssl"
  # shellcheck disable=SC2046
  write_receipt mldsa $(layout_rels mldsa)
  info "installed mldsa"
}

install_strace() {
  os=$(host_os)
  if [ "$os" != "Linux" ]; then
    die "strace is Linux-only and is not installed on $os.
  provinator install opam coq why3 easycrypt elan prover9 mldsa"
  fi
  if already_installed strace; then
    info "strace: already installed"
    return 0
  fi
  if [ "$layout_only" -eq 1 ]; then
    materialize_tool strace
    info "strace: layout recorded"
    return 0
  fi
  require_c_compiler
  require_cmd make
  require_cmd tar
  if ! command -v xz >/dev/null 2>&1 && ! command -v unxz >/dev/null 2>&1; then
    die "xz is required to unpack the official strace tarball.
  provinator does not install it."
  fi
  ensure_dirs
  work=$(mktemp -d "${TMPDIR:-/tmp}/provinator.XXXXXX")
  fetch_verified "$STRACE_URL" "$work/strace-${STRACE_VERSION}.tar.xz" "strace-${STRACE_VERSION}.tar.xz"
  tar -xJf "$work/strace-${STRACE_VERSION}.tar.xz" -C "$work"
  src=$work/strace-${STRACE_VERSION}
  if [ ! -d "$src" ]; then
    rm -rf "$work"
    die "strace source directory missing from the official tarball"
  fi
  jobs=$(job_count)
  (
    cd "$src" || exit 1
    ./configure --prefix="$PREFIX/opt/strace"
    make -j"$jobs"
    make install
  ) || {
    rm -rf "$work"
    die "strace build failed"
  }
  rm -rf "$work"
  if [ ! -x "$PREFIX/opt/strace/bin/strace" ]; then
    die "strace build did not produce bin/strace"
  fi
  rm -f "$PREFIX/bin/strace"
  ln -s "$PREFIX/opt/strace/bin/strace" "$PREFIX/bin/strace"
  # shellcheck disable=SC2046
  write_receipt strace $(layout_rels strace)
  info "installed strace"
}

install_one() {
  case "$1" in
    opam) install_opam ;;
    coq) install_coq ;;
    why3) install_why3 ;;
    easycrypt) install_easycrypt ;;
    elan) install_elan ;;
    prover9) install_prover9 ;;
    mldsa) install_mldsa ;;
    strace) install_strace ;;
    *) die "unknown tool: $1
  provinator install --help" ;;
  esac
}

selection_contains() {
  needle=$1
  for item in $tools; do
    if [ "$item" = "$needle" ]; then
      return 0
    fi
  done
  return 1
}

drop_tool() {
  drop=$1
  kept=
  for item in $tools; do
    if [ "$item" != "$drop" ]; then
      kept="$kept $item"
    fi
  done
  tools=$kept
}

prepare_selection() {
  if [ -z "$tools" ]; then
    tools=$(awk 'NF && $1 !~ /^#/ { printf "%s ", $1 }' "$ROOT/pins/tools")
    explicit=0
  else
    explicit=1
  fi
  for tool in $tools; do
    known_tool "$tool" || die "unknown tool: $tool
  provinator install --help"
  done
  os=$(host_os)
  if selection_contains strace && [ "$os" != "Linux" ]; then
    if [ "$explicit" -eq 1 ]; then
      die "strace is Linux-only and is not installed on $os.
  provinator install opam coq why3 easycrypt elan prover9 mldsa"
    fi
    drop_tool strace
    info "skipping strace on $os"
  fi
}

cmd_install() {
  prepare_selection
  if [ "$layout_only" -eq 0 ] && selection_contains easycrypt && ! already_installed easycrypt; then
    require_easycrypt_disk
  fi
  mkdir -p "$PREFIX"
  prefix_physical
  for tool in $tools; do
    install_one "$tool"
  done
  info "prefix: $PREFIX"
}

cmd_uninstall() {
  if [ -z "$tools" ]; then
    tools=$(awk 'NF && $1 !~ /^#/ { printf "%s ", $1 }' "$ROOT/pins/tools")
  fi
  for tool in $tools; do
    known_tool "$tool" || die "unknown tool: $tool
  provinator uninstall --help"
  done
  if [ ! -d "$PREFIX" ]; then
    info "prefix does not exist: $PREFIX"
    return 0
  fi
  prefix_physical
  for tool in $tools; do
    uninstall_tool "$tool"
  done
  info "prefix: $PREFIX"
}
