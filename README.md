# gawk — full-featured, lib-bundled multi-platform builds of GNU Awk

[Vendored](upstream/gawk/) [GNU Awk 5.4.1](https://git.savannah.gnu.org/cgit/gawk.git)
(a GPL-3.0-or-later AWK interpreter maintained by Arnold Robbins and
the FSF gawk team) with a native per-OS packaging layer that bundles
**all runtime dependencies** in a sibling `lib/` directory. The single
`bin/gawk` binary uses `RPATH='$ORIGIN/../lib'` (Linux) or
`@loader_path/../lib` (macOS) to find its deps — so the deployer can
install the archive anywhere and the binary still works.

This is a **distribution repo** (gawk source + build/packaging
scripts + CI). See `NOTICE.md` for the upstream GPL-3.0 terms that
apply to the `gawk` binary and bundled libraries.

## What's in the release archive

| File | Purpose |
|------|---------|
| `bin/gawk` | The CLI, dynamic-linked, RPATH='$ORIGIN/../lib' |
| `lib/libgmp.so.*` | GNU MP — bundled |
| `lib/libmpfr.so.*` | GNU MPFR — bundled |
| `lib/libreadline.so.*` | Readline (interactive REPL) — bundled |
| `lib/libhistory.so.*` | Readline companion — bundled |
| `lib/libncurses.so.*` | Readline dependency — bundled |
| `lib/extension/*.so` | 12 gawk loadable extensions (`@load "readfile"` etc.) |
| `man/man1/gawk.1` | Man page |
| `LICENSE` | GPL-3.0 (upstream gawk + bundled readline companion) |
| `NOTICE` | MIT (wrapper) + GPL-3.0 (upstream) split |
| `README.md` | This file |

> **No `awk` symlink.** The user requirement is a single `gawk`
> binary in `bin/`; the traditional `awk` → `gawk` symlink is
> created at deployment time (by the `x eget` shim or your package
> manager), not embedded in the build artifact.

## Install

### Recommended: `x eget` (one-liner, handles PATH)

```bash
x eget ljh-sh/gawk    # auto-detects arch, adds to PATH
```

`x eget` downloads the matching release archive, verifies SHA256,
extracts to `~/.local/share/ljh-sh/gawk/5.4.1/`, and adds the install
location to your PATH (via x-cmd's PATH management). x-cmd handles
the dispatch wrapper / symlink internally — we don't ship a shim in
this archive.

### Manual install

```bash
tar -xzf gawk-<target>.tar.gz
# Pick a permanent location:
sudo mkdir -p /opt/ljh-sh/gawk
sudo cp -r gawk-<target> /opt/ljh-sh/gawk/5.4.1
# Symlink to put gawk on PATH:
sudo ln -s /opt/ljh-sh/gawk/5.4.1/bin/gawk /usr/local/bin/gawk
```

The symlink works because RPATH='$ORIGIN/../lib' resolves relative
to the **executable's** location, not the symlink's location — so
the binary still finds `lib/`.

### Windows

```powershell
Expand-Archive gawk-x86_64-windows.zip
Move-Item gawk-x86_64-windows C:\Program Files\ljh-sh\gawk\5.4.1
# Symlink to put gawk on PATH:
New-Item -ItemType SymbolicLink `
    -Path 'C:\Program Files\ljh-sh\gawk\bin\gawk.exe' `
    -Target 'C:\Program Files\ljh-sh\gawk\5.4.1\bin\gawk.exe'
```

Or just run via full path:
```powershell
& 'C:\Program Files\ljh-sh\gawk\5.4.1\bin\gawk.exe' --version
```

## Platform matrix

Six targets via GitHub Actions on native runners. Linux uses **glibc**
(built on Ubuntu 24.04 host = glibc 2.39); non-libc dependencies are
bundled in `lib/`.

| target | runner | linkage | archive |
|---|---|---|---|
| `x86_64-linux-glibc` | `ubuntu-latest` | glibc dynamic + RPATH=$ORIGIN/../lib | `.tar.gz` |
| `aarch64-linux-glibc` | `ubuntu-24.04-arm` | glibc dynamic + RPATH=$ORIGIN/../lib | `.tar.gz` |
| `aarch64-macos` | `macos-14` | @rpath @loader_path/../lib | `.tar.gz` |
| `x86_64-macos` | `macos-14` (cross from aarch64) | @rpath @loader_path/../lib | `.tar.gz` |
| `x86_64-windows` | `windows-latest` + MSYS2 + mingw64 | DLLs co-located in bin/ | `.zip` |
| `aarch64-windows` | `windows-11-arm` + MSYS2 + mingw64 (clang) | DLLs co-located in bin/ | `.zip` |

> `aarch64-windows` may fail at MSYS2 toolchain resolution — CI
> allows it to fail (continue-on-error) but other targets still
> publish.

## Build configuration (full gawk features)

The wrapper scripts apply the following configure flags unconditionally:

| Flag | Reason |
|------|--------|
| `--enable-shared` | libtool produces .so / .dylib / .dll |
| `--enable-extensions` | Enable `@load` / `-l` mechanism |
| `--with-readline` | Interactive REPL with line editing |
| `--with-mpfr` | High-precision arithmetic |
| `--enable-pma` | Persistent memory allocator (opt-in via `GAWK_PERSIST_FILE`) |
| `--disable-dependency-tracking` | One-shot CI build |

> User requirement (2026-07-15): **"用户要的就是 gawk 全功能"** — every
> upstream feature is ENABLED. The wrapper does NOT patch upstream
> gawk; it only changes configure flags and bundles the runtime deps.

## Deployment: dispatch via x-cmd or symlink

`bin/gawk` is the real binary with RPATH='$ORIGIN/../lib' embedded.
How the user invokes it is up to the deployer:

- **x-cmd `eget`** — internal dispatch wrapper handles PATH and
  invocation. No shim in our archive.
- **Manual** — symlink from `$PREFIX/bin/gawk` to the real binary.
  RPATH resolves relative to the executable, so symlink location
  doesn't matter.
- **Package manager** — post-install hook creates the symlink.

The archive contains only the real distribution (`bin/`, `lib/`,
`man/`, `LICENSE`, `NOTICE`, `README.md`). No shim, no wrapper, no
alias binary.

## Quick check after install

```bash
$ gawk --version
GNU Awk 5.4.1

$ echo 'a b c' | gawk '{print $2}'
b

$ printf '1\n2\n3\n4\n5\n' | gawk 'BEGIN{s=0} {s+=$1} END{print s}'
15

$ gawk 'BEGIN{@load "readfile"; print "loaded readfile ext"}'
loaded readfile ext
```

## Build from source (vendoring update)

```bash
git subtree pull --prefix=upstream/gawk \
    git://git.savannah.gnu.org/gawk.git master --squash
```

Verify byte-for-byte upstream match after the pull:

```bash
git diff HEAD~1..HEAD -- upstream/gawk/ | head -20
( cd upstream/gawk && git rev-parse HEAD )   # record the vendored SHA
```

## Repository layout

```
upstream/gawk/        # git subtree of GNU Awk 5.4.1 (no local patches)
scripts/
  build.sh            # POSIX build, cross-compile aware, RPATH embedded
  smoke.sh            # E2E test (11+ checks) + RPATH verification
  package.sh          # stage bin/ + lib/ + man/, tar.gz + sha256
  package.ps1         # Windows packaging (zip + sha256, DLLs in bin/)
.github/workflows/
  build-and-test.yml  # push + PR: full 6-target matrix + artifact upload
  release.yml         # v* tag + dispatch: same matrix + GitHub Release
docs/                 # GitHub Pages content (ljh-sh.github.io/gawk)
AUDIT-2026-07-15.md   # source-level security audit
SECURITY.md           # vulnerability reporting policy
NOTICE.md             # wrapper MIT + upstream GPL-3.0 split
LICENSE               # wrapper MIT
```

> **No shim files** in this repo. Dispatch (PATH, invocation) is
> handled by the deployer — x-cmd's `eget` for end-users, package
> manager post-install hooks for distros, or manual symlink.

## Security

See [`SECURITY.md`](SECURITY.md) for the vulnerability reporting
policy and [`AUDIT-2026-07-15.md`](AUDIT-2026-07-15.md) for the
source-level audit. Headline: 1 HIGH (AWKPATH, no build-time fix),
3 MEDIUM (mostly documented AWK language features), 5 LOW/INFO.

## Pages

Full documentation at <https://ljh-sh.github.io/gawk/>: install
instructions, audit summary, threat model, build matrix status, CI
smoke results, links back to this repository.

## License

- **Wrapper** (this repo's scripts, workflows, README, NOTICE, docs):
  **MIT** — see `LICENSE`.
- **Vendored upstream/gawk/**: **GNU GPL-3.0-or-later** — see
  `upstream/gawk/COPYING` and the LICENSE file inside each release
  archive.
- **Bundled libs**:
  - libgmp, libmpfr: LGPL-3.0-or-later
  - libreadline, libhistory: GPL-3.0-or-later
  - libncurses: MIT-like

All bundled library licenses are documented in `NOTICE` inside each
release archive.