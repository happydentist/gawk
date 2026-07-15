# scripts/package.ps1
# Stage the built gawk into a self-contained Windows .zip archive.
#
# Mirrors scripts/package.sh but uses Windows app-local DLL search
# instead of RPATH: DLLs and .exe are placed in the SAME bin/
# directory. Windows automatically finds DLLs co-located with the
# .exe (no RPATH concept on Windows).
#
# Used by:
#   - .github/workflows/build-and-test.yml + release.yml on:
#       windows-latest   (x86_64-windows)
#       windows-11-arm   (aarch64-windows)
#
# Layout inside dist/gawk-$TARGET/:
#   bin/gawk.exe                  ← single CLI binary
#   bin/libgmp-*.dll              ← bundled from MSYS2 mingw64
#   bin/libmpfr-*.dll
#   bin/libreadline-*.dll
#   bin/libhistory-*.dll
#   bin/libncurses-*.dll
#   bin/extension/readfile.dll    ← gawk loadable extensions
#   bin/extension/readdir.dll
#   bin/extension/filefuncs.dll
#   bin/extension/fnmatch.dll
#   bin/extension/fork.dll
#   bin/extension/inplace.dll
#   bin/extension/ordchr.dll
#   bin/extension/revoutput.dll
#   bin/extension/revtwoway.dll
#   bin/extension/rwarray.dll
#   bin/extension/intdiv.dll
#   bin/extension/time.dll
#   man/man1/gawk.1
#   LICENSE NOTICE README.md
#
# SINGLE-BINARY POLICY: bin/ contains only gawk.exe + bundled DLLs.
# No awk.exe symlink, no gawk-5.4.1.exe hardlink.

$ErrorActionPreference = 'Stop'

$BUILD_DIR = if ($env:BUILD_DIR) { $env:BUILD_DIR } else { "$PSScriptRoot\..\build" }
$GAWK_SRC  = if ($env:GAWK_SRC)  { $env:GAWK_SRC }  else { "$PSScriptRoot\..\upstream\gawk" }
$DIST      = if ($env:DIST)      { $env:DIST }      else { "$PSScriptRoot\..\dist" }
$TARGET    = if ($env:TARGET)    { $env:TARGET }    else { throw "set TARGET, e.g. x86_64-windows" }

# Locate the freshly-built binary
$BIN = "$BUILD_DIR\gawk.exe"
if (-not (Test-Path $BIN)) { throw "error: $BIN not built (BUILD_DIR=$BUILD_DIR)" }

# Man page lives under upstream/gawk/doc/gawk.1
$MAN_SRC = "$GAWK_SRC\doc\gawk.1"
if (-not (Test-Path $MAN_SRC)) { throw "error: $MAN_SRC not found" }

$STAGE = "$DIST\gawk-$TARGET"
if (Test-Path $STAGE) { Remove-Item -Recurse -Force $STAGE }
$binDir = "$STAGE\bin"
$extDir = "$STAGE\bin\extension"
$manDir = "$STAGE\man\man1"
New-Item -ItemType Directory -Force -Path $binDir, $extDir, $manDir | Out-Null

# ─── 1. Single binary (bin/gawk.exe only) ────────────────────────────────
Copy-Item $BIN $binDir\gawk.exe

# ─── 2. Man page (note: gawk installs as gawk.1, not awk.1) ─────────────
Copy-Item $MAN_SRC $manDir\gawk.1

# ─── 3. Bundle all required DLLs (anything bin/gawk.exe needs at runtime)
# We walk the mingw64 bin dir for the ones gawk actually links against.
$DLL_PATTERNS = @(
    'libgmp-*.dll',
    'libmpfr-*.dll',
    'libreadline-*.dll',
    'libhistory-*.dll',
    'libncurses-*.dll',
    'libgcc_s_seh-*.dll',
    'libwinpthread-*.dll',
    'libstdc++-*.dll'
)

# Find MSYS2 mingw64 bin
$mingwBin = if ($env:MINGW_PREFIX) { $env:MINGW_PREFIX + '\bin' } else { 'C:\msys64\mingw64\bin' }

foreach ($pattern in $DLL_PATTERNS) {
    Get-ChildItem -Path $mingwBin -Filter $pattern -ErrorAction SilentlyContinue | ForEach-Object {
        $dest = Join-Path $binDir $_.Name
        if (-not (Test-Path $dest)) {
            Write-Host "    bundle: $($_.Name) (from $mingwBin)"
            Copy-Item $_.FullName $dest
        }
    }
}

# ─── 4. Bundle gawk loadable extensions (bin/extension/*.dll) ──────────
$EXT_DIR = "$BUILD_DIR\extension\.libs"
if (Test-Path $EXT_DIR) {
    Get-ChildItem -Path $EXT_DIR -Filter '*.dll' | ForEach-Object {
        Write-Host "    bundle: extension\$($_.Name)"
        Copy-Item $_.FullName $extDir\$_.Name
    }
}

# ─── 5. LICENSE (upstream GPL-3.0 copy) ─────────────────────────────────
Copy-Item "$GAWK_SRC\COPYING" $STAGE\LICENSE

# ─── 6. NOTICE (GPL-3.0 wrapper + GPL-3.0 upstream split) ──────────────
@"
# NOTICE

This archive (gawk-$TARGET) packages a build of GNU Awk 5.4.1 with
all upstream features enabled (readline, mpfr, extensions, pma)
plus the wrapper build/packaging layer around it.

## License (wrapper)

The wrapper files (scripts/, .github/, README.md, NOTICE, AUDIT-*.md)
are:

    Copyright (c) 2026 Li Junhao
    Licensed under the GNU General Public License, version 3 or later.
    See LICENSE for the full GPL-3.0 text.

## License (upstream gawk + bundled DLLs)

bin\gawk.exe, man\man1\gawk.1, and bundled bin\lib*.dll files
(libgmp, libmpfr, libreadline, libhistory, libncurses,
 bin\extension\*.dll) are derived from GNU Awk 5.4.1, vendored from
 the official GNU gawk 5.4.1 release tarball:
    https://ftp.gnu.org/gnu/gawk/gawk-5.4.1.tar.xz

Upstream gawk is Copyright (C) 1989-2026 Free Software Foundation,
Inc., licensed under GNU GPL-3.0-or-later.

Bundled third-party libraries retain their own licenses:
  - libgmp       : LGPL-3.0-or-later (GNU MP)
  - libmpfr      : LGPL-3.0-or-later (GNU MPFR)
  - libreadline  : GPL-3.0-or-later (GNU Readline)
  - libhistory   : GPL-3.0-or-later (GNU Readline companion)
  - libncurses   : MIT-like (ncurses)
  - libgcc_s     : GPL-3.0-or-later (GCC runtime)
  - libstdc++    : GPL-3.0-or-later (GCC runtime)
  - libwinpthread: LGPL-3.0-or-later (MinGW)

GPL-3.0 grants explicit redistribution rights for binary forms
provided that:
1. The GPL-3.0 license text accompanies the binary (LICENSE file).
2. Source code for the GPL-3.0 component is made available — it is,
   at upstream\gawk\ in the source repo and at
   https://git.savannah.gnu.org/cgit/gawk.git.
3. Modified versions are clearly marked — ljh-sh/gawk carries
   no source modifications to gawk 5.4.1 (byte-for-byte upstream).
"@ | Out-File -FilePath "$STAGE\NOTICE" -Encoding UTF8

# ─── 7. README (install + dispatch) ────────────────────────────────────
@'
# gawk — single-binary + bundled-libs release (Windows)

Self-contained archive from https://github.com/ljh-sh/gawk (release tag).

## Install

### Recommended: x-cmd `eget` (one-liner)

```powershell
x eget ljh-sh/gawk
```

`x eget` auto-detects your platform, downloads the matching archive,
verifies SHA256, extracts to %LOCALAPPDATA%\ljh-sh\gawk\<ver>\,
and adds the install location to your PATH (via x-cmd's PATH
management). x-cmd handles the dispatch wrapper internally — we
don't ship a shim in this archive.

### Manual install

```powershell
Expand-Archive gawk-$TARGET.zip
Move-Item gawk-$TARGET "$env:LOCALAPPDATA\ljh-sh\gawk\5.4.1"
```

Then run via full path:
```powershell
& "$env:LOCALAPPDATA\ljh-sh\gawk\5.4.1\bin\gawk.exe" --version
```

Or symlink to put on PATH:
```powershell
New-Item -ItemType SymbolicLink `
    -Path "$env:LOCALAPPDATA\ljh-sh\gawk\bin\gawk.exe" `
    -Target "$env:LOCALAPPDATA\ljh-sh\gawk\5.4.1\bin\gawk.exe"
```

### Optional: traditional awk.exe

```powershell
New-Item -ItemType SymbolicLink `
    -Path "$env:LOCALAPPDATA\ljh-sh\gawk\bin\awk.exe" `
    -Target "$env:LOCALAPPDATA\ljh-sh\gawk\5.4.1\bin\gawk.exe"
```

## What's in this archive

```
bin\gawk.exe                  # the CLI, dynamic-linked
bin\libgmp-*.dll              # GNU MP
bin\libmpfr-*.dll             # GNU MPFR
bin\libreadline-*.dll         # interactive REPL
bin\libhistory-*.dll          # readline companion
bin\libncurses-*.dll          # readline dependency
bin\libgcc_s_seh-*.dll        # GCC runtime
bin\libstdc++-*.dll           # GCC runtime
bin\libwinpthread-*.dll       # MinGW pthread
bin\extension\readfile.dll    # @load "readfile"
bin\extension\readdir.dll
bin\extension\filefuncs.dll
bin\extension\fnmatch.dll
bin\extension\fork.dll
bin\extension\inplace.dll
bin\extension\ordchr.dll
bin\extension\revoutput.dll
bin\extension\revtwoway.dll
bin\extension\rwarray.dll
bin\extension\intdiv.dll
bin\extension\time.dll
man\man1\gawk.1
LICENSE                      # GNU GPL-3.0 (upstream copy)
NOTICE                       # GPL-3.0 (wrapper) + GPL-3.0 (upstream) split
README.md                    # this file
```

## Build configuration

- `--enable-shared --enable-extensions`
- `--with-readline --with-mpfr --enable-pma`
- Windows: DLLs co-located with .exe (Windows app-local search)

See AUDIT-*.md in the GitHub release for the source-level security
review.

## License

GPL-3.0-or-later — see LICENSE and NOTICE.
'@ | Out-File -FilePath "$STAGE\README.md" -Encoding UTF8

# ─── 8. Zip it up ──────────────────────────────────────────────────────
$zipPath = "$DIST\gawk-$TARGET.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
[System.IO.Compression.ZipFile]::CreateFromDirectory($STAGE, $zipPath, `
    [System.IO.Compression.CompressionLevel]::Optimal, $false)

# Per-archive .sha256 (basename-keyed for portability)
$hash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
"$hash  gawk-$TARGET.zip" | Out-File -FilePath "$zipPath.sha256" -Encoding ASCII

Write-Host "==> packaged: $zipPath"
Get-ChildItem $zipPath, "$zipPath.sha256" | Select-Object Name, Length | Format-Table -AutoSize

Write-Host ""
Write-Host "==> Layout preview:"
Get-ChildItem $STAGE -Recurse | Select-Object FullName | Format-Table -AutoSize