# provinator

`provinator` is a single POSIX command that installs and uninstalls a fixed set of proof and cryptography tools. Copy this repository into any project and run it. It is not a service and it does not install a runtime of its own.

The command is a shell script. It downloads the pinned upstream installers, checks the vendored checksums, and keeps everything it installs under a user prefix (default `~/.local/provinator`). A C compiler, `make`, `perl`, `git`, `curl` or `wget`, and `tar` are used only when an upstream build needs them. provinator does not install those, and uninstall does not remove them.

## Install

```sh
git clone https://github.com/presempathy-awb/provinator.git
cd provinator
sh provinator install
export PATH="$HOME/.local/provinator/bin:$PATH"
```

Install one tool, or several:

```sh
sh provinator install opam coq
sh provinator --prefix "$HOME/.local/provinator" install easycrypt
```

`sh provinator install` installs every tool. On macOS it skips `strace` and says so. The script does not edit shell startup files.

Running install again is a no-op for tools that already have a receipt.

## Uninstall

```sh
sh provinator uninstall
sh provinator uninstall easycrypt
sh provinator uninstall --dry-run
```

Uninstall reads the receipts under the prefix and deletes only those paths. It does not call the system package manager, and it does not remove compilers or packages outside the prefix. A file you put in the prefix yourself is left in place.

Uninstalling `coq` removes that tool's switch and links. It leaves `opam`, Why3, and EasyCrypt in place. Uninstalling `opam` removes the opam binary and its root; the Coq, Why3, and EasyCrypt switches stay until you uninstall those tools.

## Prefix

The default prefix is `$HOME/.local/provinator`. Override it with `--prefix` or `PROVINATOR_PREFIX`. The prefix must be an absolute path and must not be a system directory such as `/usr`, `/usr/local`, `/opt`, or your home directory itself.

```text
~/.local/provinator/
  bin/                 links and the opam binary
  opt/opam-root/       opam root created by provinator
  opt/coq/             local opam switch for Coq
  opt/why3/            local opam switch for Why3
  opt/easycrypt/       local opam switch for EasyCrypt
  opt/elan/            ELAN_HOME
  opt/prover9/         Mace4/Prover9 binaries
  opt/openssl/         OpenSSL 3.5 LTS (ML-DSA)
  opt/strace/          Linux only
  var/receipts/        paths uninstall is allowed to remove
```

## Tools

| Tool | What it is for | How it is installed |
| --- | --- | --- |
| `opam` | OCaml package manager used for Coq, Why3, and EasyCrypt. | Official opam 2.6.0 binary for this OS and CPU. |
| `coq` | Proof assistant. Version 9.2.0 is the Rocq compatibility package. | Local opam switch `opt/coq`, compiler OCaml 4.14.2, package `coq.9.2.0`. |
| `why3` | Deductive verification platform. WhyML programs are checked by external provers. | Local opam switch `opt/why3`, package `why3.1.8.2`. |
| `easycrypt` | Proof assistant for game-based cryptographic proofs. It needs Why3 1.8.x. | Local opam switch, pinned to EasyCrypt commit `2aaa14acf7b2ce234b475f24f9e85ba0bdaeb024` (tag `r2026.09`). |
| `elan` | Installs and selects Lean toolchains. Provides `lean` and `lake`. | elan 4.2.4 with toolchain `leanprover/lean4:v4.34.1`. |
| `prover9` | First-order theorem prover. `mace4` searches for finite models. Both come from William McCune's LADR distribution. | Official `LADR-2009-11A.tar.gz`, built with the system C compiler and `-fcommon`. |
| `mldsa` | ML-DSA (FIPS 204) signatures. | Upstream OpenSSL 3.5.8 LTS, which is the 3.5 line that includes ML-DSA. The `openssl` binary is linked into the prefix. liboqs is the other upstream ML-DSA implementation; this installer uses OpenSSL. |
| `strace` | Traces Linux system calls. | Official strace 7.2 source. Refused on macOS. |

Coq, Why3, and EasyCrypt each get their own opam switch, so uninstalling one does not delete the others. The OCaml compiler inside a switch is removed with that switch. It is not a system compiler.

EasyCrypt's install checks free space before it downloads or builds anything. If `df` reports less than 8 GiB free on the prefix filesystem, the command exits and leaves no EasyCrypt files. 8 GiB means 8 × 1024 × 1024 KiB. Exactly 8 GiB free is enough to start.

## Pins

Versions and URLs are in `pins/versions.env`. SHA-256 values are in `pins/checksums.sha256`.

- opam and elan checksums are the GitHub release asset digests.
- Why3 and Rocq/Coq checksums are the ones published in `ocaml/opam-repository`.
- OpenSSL's checksum is the file published at `openssl.org`.
- strace's checksum is the GitHub release asset digest. The project also publishes a PGP signature.
- The official Prover9 download page does not publish a digest. The vendored SHA-256 was computed on 2026-09-24 from the official `LADR-2009-11A.tar.gz` (1,795,750 bytes).
- EasyCrypt tag `r2026.09` has no release tarball checksum. The installer pins commit `2aaa14acf7b2ce234b475f24f9e85ba0bdaeb024`.

## What the host must already have

| Needed for | Commands |
| --- | --- |
| Every download | `curl` or `wget`, plus `sha256sum` or `shasum` |
| Coq, Why3, EasyCrypt, Prover9, OpenSSL, strace | a C compiler (`cc`, `gcc`, or `clang`) and `make` |
| EasyCrypt | `git` |
| OpenSSL | `perl` |
| strace | `xz` or `unxz`, Linux only |
| Coq on Linux | libc headers, because the Rocq package checks for them |

## Test

The test parses the scripts and checks that uninstall deletes the install layout and nothing else. It does not use the network.

```sh
sh tests/parse-and-layout.sh
```

## Help

```sh
sh provinator --help
sh provinator install --help
sh provinator uninstall --help
```
