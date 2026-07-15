#!/usr/bin/env sh
# Build gawk as a dynamic-linked, lib-bundled binary. Linux gnu + macOS + MinGW.
# Out-of-tree build into BUILD_DIR (default ./build) — leaves upstream/
# untouched so repeated builds don't fight over state.
#
# Used by:
#   - .github/workflows/build-and-test.yml + release.yml on:
#       ubuntu-latest       (Linux glibc, host arch = x86_64)
#       ubuntu-24.04-arm    (Linux glibc, host arch = aarch64)
#       macos-14            (host arch = aarch64-macos; cross to x86_64)
#       windows-latest      (MSYS2/mingw64 x86_64)
#       windows-11-arm      (MSYS2/mingw64 aarch64 via clang)
#   - Local development on any POSIX host.
#
# Cross-compile: set GAWK_TARGET_ARCH + GAWK_TARGET_OS (or GAWK_TRIPLET)
# + GAWK_OS_HINT (darwin | windows). The script exports CC/CFLAGS/LDFLAGS
# and tells autotools --host=<triplet>.
#
# ====================================================================
# BUNDLED-BUILD MODEL (ljh-sh/gawk specific):
# ====================================================================
#   bin/gawk              ← single CLI binary, RPATH='$ORIGIN/../lib'
#   lib/lib*.so*          ← bundled deps (libgmp, libmpfr, libreadline)
#   lib/extension/*.so    ← gawk loadable extensions (readfile, etc.)
# ====================================================================
# All upstream features are ENABLED (user requirement: full gawk):
#   --enable-shared       (libtool produces .so / .dylib / .dll)
#   --enable-extensions   (readfile, readdir, filefuncs, fnmatch, fork,
#                          inplace, ordchr, revoutput, revtwoway, rwarray,
#                          intdiv, time — loaded from lib/extension/)
#   --with-readline       (interactive REPL with line editing)
#   --with-mpfr           (high-precision arithmetic)
#   --enable-pma          (persistent memory allocator; opt-in via
#                          GAWK_PERSIST_FILE env var)
#
# RPATH='$ORIGIN/../lib' (Linux) / @loader_path/../lib (macOS) lets the
# binary find its bundled deps regardless of where the deployer's shim
# places bin/gawk — as long as lib/ remains a sibling of bin/.
#
# Windows: DLLs are placed in the same dir as gawk.exe (bin/), so
# Windows application-local DLL search finds them automatically.
# No RPATH concept on Windows.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SRC="${GAWK_SRC:-$ROOT/upstream/gawk}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"

[ -f "$SRC/configure.ac" ] \
	|| { echo "error: $SRC/configure.ac not found" >&2; exit 1; }
command -v autoreconf >/dev/null 2>&1 \
	|| { echo "error: autoreconf not found in PATH (install autoconf + automake + libtool + gettext-dev)" >&2; exit 1; }
command -v bison >/dev/null 2>&1 \
	|| { echo "error: bison not found in PATH (gawk 5.x requires bison)" >&2; exit 1; }
command -v make >/dev/null 2>&1 \
	|| { echo "error: make not found in PATH" >&2; exit 1; }

JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.nproc 2>/dev/null || echo 4)"

# Configure args (ljh-sh/gawk bundled-build defaults).
#   --disable-dependency-tracking   one-shot CI build, no dep graph
#   --enable-shared                 libtool produces .so / .dylib
#   --enable-extensions             enable @load / -l mechanism
#   --with-readline                 interactive REPL
#   --with-mpfr                     high-precision arithmetic
#   --enable-pma                    persistent malloc (opt-in via env)
#   --disable-silent-rules          `make` logs each step
CONFIGURE_ARGS="--disable-dependency-tracking --enable-shared --enable-extensions --with-readline --with-mpfr --enable-pma --disable-silent-rules"

# Cross-compile: GAWK_TARGET_ARCH + GAWK_TARGET_OS, etc.
HOST_ARCH="$(uname -m 2>/dev/null || echo unknown)"
TARGET_ARCH="${GAWK_TARGET_ARCH:-$HOST_ARCH}"
TRIPLET="${GAWK_TRIPLET:-}"
if [ -n "${GAWK_TARGET_OS:-}" ]; then
	TRIPLET="${TRIPLET:-${GAWK_TARGET_ARCH}-${GAWK_TARGET_OS}}"
fi

# RPATH strategy:
#   - Linux glibc: -Wl,-rpath,'$$ORIGIN/../lib'
#       (note $$ to escape shell expansion; $ORIGIN is the runtime path)
#   - macOS:       -Wl,-rpath,@loader_path/../lib
#   - Windows:     no RPATH (DLLs go in same dir as .exe; Windows app-local
#                  DLL search handles it)
RPATH_LINUX="-Wl,-rpath,\$\$ORIGIN/../lib"
RPATH_MACOS="-Wl,-rpath,@loader_path/../lib"

if [ "$TARGET_ARCH" != "$HOST_ARCH" ] || [ -n "${GAWK_TARGET_OS:-}" ]; then
	[ -z "$TRIPLET" ] && TRIPLET="$TARGET_ARCH"
	case "${GAWK_OS_HINT:-}" in
	darwin)
		# Apple SDK is shared between arches; clang auto-discovers via xcrun.
		export CC=clang
		export CFLAGS="-arch $TARGET_ARCH -O2"
		export LDFLAGS="-arch $TARGET_ARCH $RPATH_MACOS"
		;;
	windows)
		# Cross-toolchain. mingw64 x86_64 host → aarch64 via clang.
		case "$TARGET_ARCH" in
		x86_64)
			export CC="${TARGET_ARCH}-w64-mingw32-gcc"
			;;
		aarch64)
			# clang -target handles cross from x86_64 mingw64 host.
			export CC=clang
			export CFLAGS="-target ${TARGET_ARCH}-w64-windows-gnu -O2"
			export LDFLAGS="-target ${TARGET_ARCH}-w64-windows-gnu"
			TRIPLET="${TARGET_ARCH}-w64-windows-gnu"
			;;
		esac
		;;
	*)
		echo "error: unknown GAWK_OS_HINT '$GAWK_OS_HINT' (expected 'darwin' or 'windows')" >&2
		exit 1
		;;
	esac
	CONFIGURE_ARGS="$CONFIGURE_ARGS --host=$TRIPLET"
else
	# Native build — set RPATH for current OS.
	case "$(uname -s 2>/dev/null || echo unknown)" in
	Linux)
		export LDFLAGS="${LDFLAGS:-} $RPATH_LINUX"
		;;
	Darwin)
		export LDFLAGS="${LDFLAGS:-} $RPATH_MACOS"
		;;
	esac
fi

# Out-of-tree: create build dir, run autoreconf + configure in src, build in build/.
mkdir -p "$BUILD_DIR"

if [ ! -x "$SRC/configure" ] || [ "$SRC/configure.ac" -nt "$SRC/configure" ]; then
	echo "==> autoreconf -fi in $SRC"
	( cd "$SRC" && autoreconf -fi )
fi

echo "==> configure: $SRC/configure $CONFIGURE_ARGS"
echo "    CC=$CC"
echo "    CFLAGS=$CFLAGS"
echo "    LDFLAGS=$LDFLAGS"
( cd "$BUILD_DIR" && "$SRC/configure" $CONFIGURE_ARGS )

echo "==> make -j$JOBS"
make -C "$BUILD_DIR" -j"$JOBS"

# Verify the binary exists and is executable.
BIN="$BUILD_DIR/gawk"
[ -x "$BIN" ] || BIN="$BUILD_DIR/gawk.exe"
[ -x "$BIN" ] || { echo "error: $BIN not built" >&2; exit 1; }
echo "==> built: $BIN"
"$BIN" --version | head -1

# Show RPATH for verification (Linux only).
if [ "$(uname -s 2>/dev/null)" = "Linux" ]; then
	echo "==> RPATH verification (readelf -d):"
	if command -v readelf >/dev/null 2>&1; then
		readelf -d "$BIN" | grep -E 'RPATH|RUNPATH' || echo "    (no readelf RPATH/RUNPATH entry — linker may use different mechanism)"
	else
		echo "    readelf not available; skip"
	fi
fi