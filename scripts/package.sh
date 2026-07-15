#!/usr/bin/env sh
# Stage the built gawk into a self-contained dist archive. Linux + macOS.
#   TARGET    e.g. x86_64-linux-glibc | aarch64-linux-glibc | aarch64-macos
#   BUILD_DIR (default $ROOT/build)
#   GAWK_SRC  (default $ROOT/upstream/gawk — for the man page)
#   DIST      (default $ROOT/dist)
#
# BUNDLED-BUILD LAYOUT inside dist/gawk-$TARGET/:
#   bin/gawk              ← single CLI binary, RPATH='$ORIGIN/../lib'
#   lib/
#     libgmp.so.*         ← bundled from system
#     libmpfr.so.*
#     libreadline.so.*
#     libhistory.so.*     ← (readline companion, if present)
#     libncurses.so.*     ← (readline may depend on this)
#     extension/
#       libreadfile.so    ← gawk loadable extensions (@load "readfile")
#       libreaddir.so
#       libfilefuncs.so
#       libfnmatch.so
#       libfork.so
#       libinplace.so
#       libordchr.so
#       librevoutput.so
#       librevtwoway.so
#       librwarray.so
#       libintdiv.so
#       libtime.so
#   man/man1/gawk.1
#   README.md             ← install + shim model
#   LICENSE               ← upstream GPL-3.0 copy (required by GPL)
#   NOTICE                ← wrapper MIT + upstream GPL-3.0 split
#
# SINGLE-BINARY POLICY: bin/ contains only bin/gawk. NO bin/awk symlink,
# NO bin/gawk-5.4.1 hardlink, NO bin/pgawk debug variant. Aliases are
# added by the deployer's shim, not embedded in the build artifact.
#
# Windows (handled by package.ps1): DLLs go in bin/ (alongside gawk.exe),
# extension DLLs go in bin/extension/. No lib/ subdir.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
GAWK_SRC="${GAWK_SRC:-$ROOT/upstream/gawk}"
DIST="${DIST:-$ROOT/dist}"
TARGET="${TARGET:?set TARGET, e.g. x86_64-linux-glibc}"

ext_for() { [ -f "$1.exe" ] && printf '%s.exe' "$1" || printf '%s' "$1"; }
BIN="$(ext_for "$BUILD_DIR/gawk")"
[ -x "$BIN" ] || { echo "error: $BIN not built (out-of-tree BUILD_DIR=$BUILD_DIR)" >&2; exit 1; }

# Man page lives under upstream/gawk/doc/gawk.1.
MAN_SRC="$GAWK_SRC/doc/gawk.1"
[ -f "$MAN_SRC" ] || { echo "error: $MAN_SRC not found" >&2; exit 1; }

STAGE="$DIST/gawk-$TARGET"
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/lib" "$STAGE/man/man1"

# ─── 1. Single binary (bin/gawk only) ─────────────────────────────────
cp "$BIN" "$STAGE/bin/gawk"
chmod +x "$STAGE/bin/gawk"

# ─── 2. Man page ───────────────────────────────────────────────────────
cp "$MAN_SRC" "$STAGE/man/man1/gawk.1"

# ─── 3. Bundle all non-libc .so deps from ldd output ──────────────────
echo "==> Bundling .so deps via ldd:"
LDD_OUTPUT="$(ldd "$BIN" 2>&1)"
echo "$LDD_OUTPUT" | sed 's/^/    /'

# Allowed system libs (libc + libm + libpthread + dynamic linker) — these
# come from the OS, never bundle them.
SYSTEM_LIBS_RE='^(linux-vdso|linux-gate|libc\.so|libm\.so|libpthread\.so|libdl\.so|libresolv\.so|libnsl\.so|libutil\.so|librt\.so|ld-linux|ld-musl)'

# Find system library paths.
SYSTEM_LIB_DIRS="/lib /lib64 /usr/lib /usr/lib64"
[ -d /lib/x86_64-linux-gnu ] && SYSTEM_LIB_DIRS="$SYSTEM_LIB_DIRS /lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu"
[ -d /lib/aarch64-linux-gnu ] && SYSTEM_LIB_DIRS="$SYSTEM_LIB_DIRS /lib/aarch64-linux-gnu /usr/lib/aarch64-linux-gnu"

bundled_count=0
echo "$LDD_OUTPUT" | while IFS= read -r line; do
	# Match patterns:
	#   libfoo.so.10 => /usr/lib/x86_64-linux-gnu/libfoo.so.10 (0x...)
	#   libfoo.so.10 => not found
	lib="$(echo "$line" | sed -nE 's/^\s*(lib[^ ]+\.so[.0-9]*)\s*=>\s*(\/[^ ]+).*/\1|\2/p')"
	[ -z "$lib" ] && continue
	libname="${lib%|*}"
	libpath="${lib#*|}"

	# Skip system libs.
	case "$libname" in
		$SYSTEM_LIBS_RE) continue ;;
	esac

	# Copy to lib/.
	dest="$STAGE/lib/$libname"
	if [ ! -e "$dest" ]; then
		echo "    bundle: $libname (from $libpath)"
		cp -P "$libpath" "$STAGE/lib/"
		bundled_count=$((bundled_count + 1))
	fi
done

# Also bundle libreadline companion libs (libhistory, libncurses) — these
# aren't NEEDED by gawk itself but are loaded by libreadline via dlopen.
for maybe in libhistory.so libncurses.so; do
	for dir in $SYSTEM_LIB_DIRS; do
		if [ -f "$dir/$maybe" ] || [ -f "$dir/$maybe.5" ] || [ -f "$dir/$dir/$maybe.6" ]; then
			find "$dir" -maxdepth 1 -name "${maybe}*" 2>/dev/null | while IFS= read -r f; do
				base="$(basename "$f")"
				[ -e "$STAGE/lib/$base" ] || cp -P "$f" "$STAGE/lib/"
			done
		fi
	done
done

# ─── 4. Bundle gawk loadable extensions (lib/extension/*.so) ──────────
EXT_DIR="$BUILD_DIR/extension/.libs"
if [ -d "$EXT_DIR" ]; then
	mkdir -p "$STAGE/lib/extension"
	echo "==> Bundling gawk loadable extensions from $EXT_DIR:"
	for extso in "$EXT_DIR"/*.so "$EXT_DIR"/*.dylib; do
		[ -f "$extso" ] || continue
		base="$(basename "$extso")"
		cp "$extso" "$STAGE/lib/extension/"
		echo "    bundle: extension/$base"
	done
fi

# ─── 5. LICENSE (upstream GPL-3.0 copy — required by GPL) ─────────────
cp "$GAWK_SRC/COPYING" "$STAGE/LICENSE"

# ─── 6. NOTICE (wrapper MIT + upstream GPL-3.0 split) ─────────────────
cat > "$STAGE/NOTICE" <<EOF
# NOTICE

This archive (\`gawk-$TARGET\`) packages a build of **GNU Awk 5.4.1**
with all upstream features enabled (readline, mpfr, extensions, pma)
plus the wrapper build/packaging layer around it.

## Wrapper license (the archive structure, scripts, this NOTICE)

The wrapper files (scripts/, .github/, README.md, NOTICE) are:

    Copyright (c) 2026 Li Junhao
    Licensed under the MIT License.

## Upstream license (the gawk binary, man page, and bundled .so files)

\`bin/gawk\`, \`man/man1/gawk.1\`, and \`lib/*.so*\` (including bundled
\`libgmp\`, \`libmpfr\`, \`libreadline\`, \`libhistory\`, \`libncurses\`,
\`lib/extension/*.so\`) are derived from GNU Awk 5.4.1, vendored via
\`git subtree\` from https://git.savannah.gnu.org/cgit/gawk.git
(maintained by Arnold Robbins and the FSF gawk team).

Upstream gawk is GNU GPL-3.0-or-later — see LICENSE (the GPL-3.0
text is reproduced verbatim from upstream \`gawk/COPYING\`).

Bundled third-party libraries (libgmp, libmpfr, libreadline,
libhistory, libncurses) retain their own licenses:
  - libgmp      : LGPL-3.0-or-later (GNU MP)
  - libmpfr     : LGPL-3.0-or-later (GNU MPFR)
  - libreadline : GPL-3.0-or-later (GNU Readline)
  - libhistory  : GPL-3.0-or-later (GNU Readline companion)
  - libncurses  : MIT-like (ncurses)

GPL-3.0 grants explicit redistribution rights for binary forms
(\`x eget ljh-sh/gawk\`, distro packages, embedded use) provided that:

1. The GPL-3.0 license text accompanies the binary (LICENSE file).
2. Source code for the GPL-3.0 component is made available —
   it is, at \`upstream/gawk/\` in the source repo and at
   \`https://git.savannah.gnu.org/cgit/gawk.git\`.
3. Modified versions are clearly marked — ljh-sh/gawk carries
   no source modifications to gawk 5.4.1 (byte-for-byte upstream).
EOF

# ─── 7. README (install + shim model) ──────────────────────────────────
cat > "$STAGE/README.md" <<'EOF'
# gawk — single-binary + bundled-libs release

Self-contained archive from https://github.com/ljh-sh/gawk (release tag).

## Install

### Recommended: `x eget` (one-liner, handles shim + PATH)

```bash
x eget ljh-sh/gawk
```

`x eget` auto-detects your platform, downloads the matching release
archive, verifies SHA256, installs to `~/.local/share/ljh-sh/gawk/<ver>/`,
and adds a POSIX sh shim to `~/.local/bin/gawk`. The shim puts the
real binary's directory in PATH via x-cmd's path management.

### Manual install

```bash
tar -xzf gawk-<target>.tar.gz
# Pick a permanent location (suggestion: /opt/ljh-sh/gawk/<ver>/):
sudo mkdir -p /opt/ljh-sh/gawk
sudo cp -r gawk-<target> /opt/ljh-sh/gawk/5.4.1
# Optionally create symlink:
sudo ln -s /opt/ljh-sh/gawk/5.4.1/bin/gawk /usr/local/bin/gawk
```

### Shim model (POSIX)

The deployer provides a shim that execs the real binary:

```sh
#!/bin/sh
# bin/gawk shim — example for x eget / package manager
DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$DIR/libexec/gawk.real" -Wl,-rpath,"$DIR/../lib" "$@"
```

Or simpler: x eget installs the entire archive to a known location
and creates a shim that execs the real binary directly.

### Windows shim (.bat)

```bat
@echo off
rem bin\gawk.bat shim — example
"%~dp0gawk.exe" %*
```

### Optional: traditional `awk` symlink

```bash
sudo ln -s /usr/local/bin/gawk /usr/local/bin/awk
```

## What's in this archive

```
bin/gawk           # the CLI, dynamic-linked, RPATH='$ORIGIN/../lib'
lib/
  libgmp.so.*      # high-precision arithmetic
  libmpfr.so.*     # GNU MPFR runtime
  libreadline.so.* # interactive REPL
  libhistory.so.*  # readline companion
  libncurses.so.*  # readline dependency
  extension/
    libreadfile.so   # @load "readfile" — read files by line
    libreaddir.so    # @load "readdir" — list directory contents
    libfilefuncs.so  # @load "filefuncs" — stat() wrappers
    libfnmatch.so    # @load "fnmatch" — filename glob match
    libfork.so       # @load "fork" — process forking
    libinplace.so    # @load "inplace" — in-place file editing
    libordchr.so     # @load "ordchr" — char <-> codepoint
    librwarray.so    # @load "rwarray" — serialize arrays
    libintdiv.so     # @load "intdiv" — exact integer division
    libtime.so       # @load "time" — gawk time functions
    librevoutput.so  # @load "revoutput" — reverse output
    librevtwoway.so  # @load "revtwoway" — reverse I/O
man/man1/gawk.1
LICENSE            # GNU GPL-3.0 (upstream copy)
NOTICE             # MIT (wrapper) + GPL-3.0 (upstream)
README.md          # this file
```

## Build configuration

- `--enable-shared` — libtool produces .so
- `--enable-extensions` — all 12 upstream extensions available
- `--with-readline` — interactive REPL with line editing
- `--with-mpfr` — high-precision arithmetic
- `--enable-pma` — persistent memory allocator (opt-in via `GAWK_PERSIST_FILE`)
- Linux: glibc dynamic, RPATH='$ORIGIN/../lib' for portable lib lookup
- macOS: @rpath @loader_path/../lib
- Windows: DLLs co-located with .exe (Windows app-local search)

See the AUDIT-*.md file in the GitHub release for the source-level
security review, and https://ljh-sh.github.io/gawk/ for full docs.

## Wrapper license

MIT — see NOTICE.

## Upstream license

GNU GPL-3.0-or-later — see LICENSE and
https://git.savannah.gnu.org/cgit/gawk.git
EOF

# ─── 8. Tar it up ──────────────────────────────────────────────────────
tar -C "$DIST" -czf "$STAGE.tar.gz" \
	--sort=name --mtime='1970-01-01 00:00:00 UTC' --owner=0 --group=0 --numeric-owner \
	"gawk-$TARGET"

# Per-archive .sha256 (basename-keyed).
( cd "$DIST" && sha256sum "$STAGE.tar.gz" ) | sed 's|^\([^ ]*\)  \./|\1  |' \
	> "$STAGE.tar.gz.sha256"

echo "==> packaged: $STAGE.tar.gz"
ls -la "$STAGE.tar.gz" "$STAGE.tar.gz.sha256"
echo
echo "==> Layout preview:"
( cd "$STAGE" && find . -maxdepth 3 -type f | sort | sed 's/^/    /' )