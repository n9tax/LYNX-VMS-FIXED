# Licensing and redistribution

Short answer: **yes, you can redistribute this**, including the prebuilt
`kit/LYNX293.A`, provided you keep the licence files and ship the source
alongside the binary. This repository already satisfies both.

Not legal advice — this is what the licence files in this tree actually say.

## What licence applies

| Component | Licence | File |
|---|---|---|
| Lynx itself | GNU GPL **version 2 only** | `COPYING` |
| Copyright notice and overrides | Thomas E. Dickey, 1997-2026 | `COPYHEADER` |
| libwww-FM (`WWW/Library/`) | GNU **Library** GPL version 2 | `WWW/Library/vms/COPYING.LIB` |

**Version 2 only, not "or later".** `COPYHEADER` says the developers agreed to
"the GNU General Public License (Version 2)", and adds that "the License text
after the terms and conditions is advisory in nature, and contains neither terms
nor conditions." That advisory text is the part that normally suggests "or any
later version." So label this repository **GPL-2.0**, not GPL-2.0-or-later.

`COPYHEADER` also states its own terms **override** `COPYING` where they differ,
and that it "must be included in all copies or substantial portions of Lynx."
It is not optional and not merely historical.

## What you must do when redistributing

1. **Ship the licence files.** `COPYING`, `COPYHEADER`, and
   `WWW/Library/vms/COPYING.LIB`. All three are tracked here.

2. **Ship source with any binary.** GPL v2 §3 — distributing an executable means
   accompanying it with the complete corresponding source, or a written offer to
   supply it. `kit/LYNX293.A` contains `LYNX.EXE`, so this matters. It is
   satisfied because the full source sits beside it in the same repository.
   **If you hand someone the bare `.A` file** — on a disk, as a forum
   attachment, in a Release with no source — you must include the source or a
   written offer with it. Linking to this repository is the easy way.

3. **Mark modified files.** GPL v2 §2(a) — changed files must carry notices
   saying they changed and when. Already done:

   | File | Notice |
   |---|---|
   | `build.com` | `MODIFIED 2026-08-28 for OpenVMS VAX 7.3 / DEC C` |
   | `WWW/Library/vms/libmake.com` | same |
   | `src/chrtrans/build-chrtrans.com` | same |
   | `WWW/Library/Implementation/HTTCP.c` | dated comment at the fix, line ~2538 |

   Keep this up if you change anything else.

4. **No extra restrictions**, and don't strip the warranty disclaimers.

## What you may do

Sell it, put it on a CD, mirror it, fork it, ship it inside a larger
distribution, or hand it to a friend with a VAX. GPL v2 permits commercial
redistribution; the obligations above travel with it either way.

## Third-party libraries

`COPYHEADER` grants explicit permission to use Lynx with OpenSSL, GnuTLS,
libbsd, libidn, zlib, libbz2, libiconv, libutf8, and nss_compat_ossl,
"regardless of the manner in which the libraries are connected to the Lynx
program" — which removes the usual OpenSSL/GPL linking argument.

**Not relevant to this build:** it is compiled without SSL, so no OpenSSL is
linked in. If you later build with `SSL`, that grant is what covers you.

## The fix in this fork

The `HTDoRead()` recursion fix is a two-line change restoring what Lynx 2.8.8
did. It is a derivative work of Lynx and is under the same GPL v2. It should go
upstream to `lynx-dev@nongnu.org` rather than living only in a fork.

## Practical checklist for a GitHub release

- [ ] Repository licence set to **GPL-2.0** (not "or later")
- [ ] `COPYING`, `COPYHEADER`, `WWW/Library/vms/COPYING.LIB` present
- [ ] Any Release carrying `LYNX293.A` links to the source in this repo
- [ ] Modified files keep their change notices
- [ ] README states this is a modified Lynx, not the official release
