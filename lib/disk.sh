# EasyCrypt refuses to start when the prefix filesystem has under 8 GiB free.
# 8 GiB = 8 * 1024 * 1024 KiB.

easycrypt_min_free_kib() {
  printf '%s\n' 8388608
}

disk_probe_dir() {
  dir=$PREFIX
  while [ ! -d "$dir" ]; do
    next=$(dirname "$dir")
    if [ "$next" = "$dir" ]; then
      break
    fi
    dir=$next
  done
  printf '%s\n' "$dir"
}

free_kib() {
  probe=$1
  require_cmd df
  require_cmd awk
  avail=$(df -Pk "$probe" | awk 'NR == 2 { print $4 }')
  case "$avail" in
    ''|*[!0-9]*)
      die "could not read free disk space for $probe"
      ;;
  esac
  printf '%s\n' "$avail"
}

require_easycrypt_disk() {
  probe=$(disk_probe_dir)
  avail=$(free_kib "$probe")
  need=$(easycrypt_min_free_kib)
  if [ "$avail" -lt "$need" ]; then
    die "EasyCrypt install refused: free disk is under 8 GiB (${avail} KiB available on ${probe}; need ${need} KiB)."
  fi
}
