# NOTICE

This repository (`ljh-sh/gawk`) provides self-contained, multi-platform
builds of **GNU Awk 5.4.1** with all upstream features enabled
(readline, mpfr, extensions, persistent memory allocator) plus the
build/packaging layer around it.

## License (wrapper — this repo's own files)

`scripts/`, `.github/workflows/`, `README.md`, `NOTICE.md`,
`AUDIT-*.md`, `.gitattributes`, `.gitignore`, and `LICENSE` are:

    Copyright (c) 2026 Li Junhao
    Licensed under the GNU General Public License, version 3 or later.
    See LICENSE for the full GPL-3.0 text.

## License (upstream gawk + bundled libraries)

`upstream/gawk/` is an unmodified copy of GNU Awk 5.4.1, vendored from
the official GNU gawk 5.4.1 release tarball
(https://ftp.gnu.org/gnu/gawk/gawk-5.4.1.tar.xz). The tarball was
verified against its GPG signature before extraction.

Upstream gawk is Copyright (C) 1989-2026 Free Software Foundation,
Inc., licensed under GNU GPL-3.0-or-later. See `upstream/gawk/COPYING`
for the full GPL-3.0 text.

Bundled third-party libraries (in each release archive's `lib/` or
`bin/`) retain their own licenses:

| Library | License | Upstream |
|---------|---------|----------|
| libgmp | LGPL-3.0-or-later | https://gmplib.org |
| libmpfr | LGPL-3.0-or-later | https://www.mpfr.org |
| libreadline | GPL-3.0-or-later | https://tiswww.case.edu/chet/readline |
| libhistory | GPL-3.0-or-later | (part of readline) |
| libncurses | MIT-like | https://invisible-island.net/ncurses |
| libgcc_s / libstdc++ | GPL-3.0-or-later (GCC runtime exception) | https://gcc.gnu.org |
| libwinpthread | LGPL-3.0-or-later (MinGW) | https://mingw-w64.org |

GPL-3.0 grants explicit redistribution rights for binary forms
(`x eget ljh-sh/gawk`, distro packages, embedded use) provided that:

1. The GPL-3.0 license text accompanies the binary (LICENSE file in
   each release archive).
2. Source code for the GPL-3.0 component is made available — it is,
   at `upstream/gawk/` in this repository and at
   https://git.savannah.gnu.org/cgit/gawk.git.
3. Modified versions are clearly marked — ljh-sh/gawk carries no
   source modifications to gawk 5.4.1 (byte-for-byte upstream from
   the official 5.4.1 tarball).

## Vendor integrity

This repository vendors upstream gawk byte-for-byte from the official
GNU gawk 5.4.1 release tarball. No source patches are applied. To
verify the upstream tarball before vendoring:

```sh
curl -L -O https://ftp.gnu.org/gnu/gawk/gawk-5.4.1.tar.xz
curl -L -O https://ftp.gnu.org/gnu/gawk/gawk-5.4.1.tar.xz.sig
gpg --verify gawk-5.4.1.tar.xz.sig gawk-5.4.1.tar.xz
```

The tarball was verified against the FSF-maintained GPG signature
(Arnold Robbins <arnold@skeeve.com>, key 0xA5BD9986610A11B8 or
similar — see https://www.gnu.org/software/gawk/) before the initial
vendoring commit.