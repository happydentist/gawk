# Security Policy

## Reporting a vulnerability

**Please DO NOT open a public GitHub issue for security vulnerabilities.**

### Issues in the ljh-sh/gawk wrapper itself

For issues in the wrapper (build scripts, CI, packaging, distribution
metadata), report privately to:

- Email: ljh-sh-security@duck.com
- Expected response time: best-effort, usually within 7 days

### Issues in upstream GNU Awk (the `gawk` binary itself)

For issues in upstream GNU Awk's source code, report to the FSF gawk
maintainer team:

- Mailing list: <bug-gawk@gnu.org>
- Savannah: <https://savannah.gnu.org/bugs/?group=gawk>
- See also: <https://www.gnu.org/software/gawk/manual/html_node/Bugs.html>

**ljh-sh/gawk carries no source modifications to upstream gawk 5.4.1**
(byte-for-byte vendor from the official tarball). Almost all gawk
security issues should be reported to upstream first.

## Threat model

`gawk` is a **script interpreter**. Its primary job is to execute
user-provided AWK programs — so by design, any AWK script is
attacker-controlled code running inside the gawk process with the
caller's UID. The trust boundary is **NOT** "gawk filters AWK input";
it's "the operator trusts the AWK program enough to run it as their
own user".

### Operator requirements

**DO:**
- Run untrusted AWK scripts in a sandbox (separate UID, no network,
  tmpdir-only filesystem).
- Sanitize `AWKPATH`, `AWKLIBPATH`, `GAWK_*`, `POSIXLY_CORRECT` env
  vars before invoking gawk.
- Use the upstream gawk build (with extensions enabled) if you need
  features this wrapper disables.

**DO NOT:**
- Invoke `gawk` with `sudo`, `setuid`, or as a privileged service
  binary. gawk is **not setuid-safe** (upstream INSTALL file
  explicitly warns about this).
- Run AWK scripts from untrusted sources with your user credentials.

## CVE history

As of 2026-07-15, GNU Awk has **no known unpatched security
advisories**. Historical advisories are listed in the
[upstream gawk Savannah page](https://savannah.gnu.org/project/member-list.php?group=gawk).

This wrapper does not introduce new vulnerabilities beyond the
documented AWK language features. See [`AUDIT-2026-07-15.md`](AUDIT-2026-07-15.md)
for the source-level audit.