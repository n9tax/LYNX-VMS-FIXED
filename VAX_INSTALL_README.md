# Building Lynx 2.9.3 on OpenVMS VAX

Reproduction notes for building Lynx 2.9.3 on a MicroVAX running OpenVMS VAX 7.2/7.3
with DEC C and UCX (TCP/IP Services).

Everything here was worked out against a real system (`GOZER$`). Steps marked
**[verified]** produced the stated result on that machine; steps marked
**[open]** had not been reached at the time of writing.

---

## TL;DR

Stock Lynx 2.9.3 will not compile with DEC C on VMS. The fix is **four lines**,
all of them compiler-flag assignments:

| File | Line | Change to |
|---|---|---|
| `BUILD.COM` | 157 | `$ cc_opts = "/ACCEPT=NOVAXC_KEYWORDS"` |
| `[.WWW.LIBRARY.VMS]LIBMAKE.COM` | 152 | `$ cc_opts = "/ACCEPT=NOVAXC_KEYWORDS"` |
| `[.SRC.CHRTRANS]BUILD-CHRTRANS.COM` | 26 | `$      CHRcc_opts = "/ACCEPT=NOVAXC_KEYWORDS/DEBUG/NOOPT/DEFINE=(UCX)"` |
| `[.SRC.CHRTRANS]BUILD-CHRTRANS.COM` | 29 | `$      CHRcc_opts = "/ACCEPT=NOVAXC_KEYWORDS/DEFINE=(UCX)"` |

No source files need editing. No `extra_defs` changes. The only `#define`
added is the transport (`UCX`) for `makeuctb`, explained below.

(Line numbers are for this tree, which carries GPL §2(a) change notices in the
three procedures. In a pristine 2.9.3 tarball they are 152, 148, 18 and 21.
`PATCHVMS.COM` matches on content rather than line number, so it works on
either.)

---

## The root cause

`readonly` is a **VAX C storage-class keyword**. DEC C reserves it in its
default (relaxed) mode. Lynx uses `readonly` as an ordinary struct member in
two places:

- `[.SRC]HTFORMS.H` line 38 — `int readonly;` in `struct _InputFieldData`
- `[.SRC]HTFORMS.H` line 96 — `int readonly;` in `FormInfo`

So every module that includes `HTForms.h` dies with:

```
	    int readonly;
	........^
%CC-E-DECLARATOR, Invalid declarator.
```

`/ACCEPT=NOVAXC_KEYWORDS` tells DEC C to stop reserving the VAX C keywords
(`readonly`, `globaldef`, `globalref`, `variant_struct`, `noshare`, ...)
and nothing else. **[verified]**

### Why `makeuctb` also needs `/DEFINE=(UCX)`

`BUILD-CHRTRANS.COM` is invoked with no parameters, so it never receives the
transport. That is fine for the *includes* — with no transport defined,
`WWW_TCP.H` falls through to its `#ifndef TCP_INCLUDES_DONE` branch and pulls
only `types.h`, `errno.h`, `time.h`. But further down, **outside every
transport guard**, it declares:

```c
typedef union {
    struct sockaddr_in soc_in;
    struct sockaddr soc_address;
} LY_SOCKADDR;
```

`makeuctb.c` reaches this via `UCDefs.h` → `HTUtils.h` → `WWW_TCP.H`, and
without a transport the socket headers were never included, so:

```
	    struct sockaddr_in soc_in;
	.......................^
%CC-E-INCOMPMEM, The member "soc_in" has an incomplete type.
```

Hence `/DEFINE=(UCX)` on both `CHRcc_opts` branches. Change it to match your
transport (`TCPIP`, `MULTINET`, `SOCKETSHR_TCP`) if not using UCX. **[verified]**

### Why not `/STANDARD=ANSI89`

Strict ANSI89 also drops the VAX C keywords, so it "works" too — but it is a
much bigger hammer:

- it un-defines the predefined `VMS` and `vms` macros, which Lynx tests in
  250 places, so you must add `/DEFINE=(VMS=1,...)` to compensate;
- it sets `__HIDE_FORBIDDEN_NAMES`, which can hide the non-ANSI prototypes in
  the VMS headers. Functions then degrade to implicit `int`-returning
  declarations. For anything returning a pointer that is silently wrong code
  on a 32-bit VAX, and it compiles with only a *warning* — so a clean
  `SEARCH BUILD.LOG "%CC-E"` will not catch it.

On the test system the header-hiding did **not** actually bite (`getcwd`,
`getpid`, `unlink` stayed visible), so ANSI89 is a usable fallback. `/ACCEPT`
is still preferred: it changes exactly one thing.

One trap if you do use the ANSI89 route: **DCL uppercases unquoted command
text**, so `/DEFINE=(vms=1)` arrives at the compiler as `VMS=1`. To get a
genuinely lowercase macro you must quote it: `/DEFINE=("vms=1")`. Lynx never
tests lowercase `vms`, so this does not matter here — but it is why the
obvious-looking `,VMS=1,vms=1` is really just `VMS=1` twice.

---

## Prerequisites

```dcl
$ DIR SYS$SHARE:UCX$IPC_SHR.EXE          ! named by [.SRC]UCXSHR.OPT
$ DIR SYS$LIBRARY:VAXCRTL.OLB            ! named by [.SRC]DECC.OPT
$ DIR SYS$LIBRARY:VAXCCURSE.OLB          ! named by [.SRC]DECC.OPT
$ DIR SYS$LIBRARY:UCX$INETDEF.H          ! needed once UCX is #defined
$ DIR [.SRC]DECC.OPT,UCXSHR.OPT          ! both ship in the tarball
```

`VAXCCURSE.OLB` is the one most likely to be missing — `DECC.OPT` names it
unconditionally, but it only ships if VAX C was installed. On the test system
it was present and the link succeeded. If absent, edit the relevant `.OPT`
rather than fighting the linker; `BUILD.COM` compiles with `__VMS_CURSES`, so
DEC C's own curses in the RTL should cover it. **[verified present]**

Disk: the test system had 1,560,411 free blocks (~760 MB). The build needs
room for ~90 `.OBJ` plus the `.OLB`; anything over ~100,000 blocks is fine.

### Process quotas

`GridText.c` is 15,075 lines / 404 KB — by far the largest file in Lynx — and
the DEC C optimizer needs a lot of process virtual memory for it. With default
quotas the compile dies:

```
$ cc GridText
%CLI-F-TEXT, Compiler abort - virtual memory limits exceeded.
%SYSTEM-F-ABORT, abort
```

Check and raise:

```dcl
$ SHOW PROCESS/QUOTA                     ! look at PGFLQUOTA
$ RUN SYS$SYSTEM:AUTHORIZE
UAF> MODIFY <youruser> /PGFLQUOTA=250000/WSQUOTA=8000/WSEXTENT=32000
UAF> EXIT
```

Then **log out and back in** — quotas are read at login. Two things gate it:
the page file must be big enough to back the quota (`SHOW MEMORY/FILES`), and
the SYSGEN parameter `VIRTUALPAGECNT` must be at least PGFLQUOTA (it is not
dynamic, so raising it needs a reboot).

If the quota cannot go that high, compile that one file unoptimized instead —
`BUILD.COM` line 347, `$ cc GridText` becomes `$ cc/nooptimize GridText`. The
optimizer is what consumes the memory. Upstream already does exactly this for
`LYCurses` at line 358.

### Batch queue

`BUILD.COM` is normally submitted to batch. On a freshly built system the
queue manager often was never started:

```
%SUBMIT-F-CREJOB, error creating job
-JBC-E-JOBQUEDIS, system job queue manager is not running
```

Fix once, with SYSPRV/OPER:

```dcl
$ START/QUEUE/MANAGER                    ! add /NEW_VERSION if no queue database exists
$ INITIALIZE/QUEUE/BATCH/START/JOB_LIMIT=1 SYS$BATCH
$ SHOW QUEUE SYS$BATCH
```

Add `START/QUEUE/MANAGER` to `SYS$STARTUP:SYSTARTUP_VMS.COM` so it survives a
reboot.

---

## Procedure

### 1. Unpack

Unzip into a **fresh** directory. Do not layer over a previous attempt — VMS
file versioning will leave you with a `;1`/`;2` mix of patched and unpatched
procedures, and a stale `.OBJ` from a failed run can get linked into the final
image without warning.

```dcl
$ RENAME [000000]LYNX293.DIR;1 LYNX293_OLD.DIR   ! if an old tree exists
$ UNZIP lynx293.zip
```

Plain `UNZIP` is correct. Every file in the tree is plain text (only
`[.SAMPLES]LYNX.ICO` is binary), and VMS 7.3 executes Stream_LF `.COM` files
and reads Stream_LF `#include`s without complaint. Only if DCL rejects a
procedure's record format should you re-extract with `UNZIP -a`.

Eight files have two dots in their names (`.vcxproj.filters`, DJGPP/MinGW
scripts). ODS-2 turns the extra dot into an underscore. All eight are
Windows/DOS build files — ignore it.

### 2. Apply the four edits

If they are not already in your tree, either edit by hand or run
`@[.VAXPROBE]PATCHVMS` from the tree top. Verify either way:

```dcl
$ SET DEFAULT [000000.LYNX293]
$ SEARCH BUILD.COM "cc_opts ="
$ SEARCH [.WWW.LIBRARY.VMS]LIBMAKE.COM "cc_opts ="
$ SEARCH [.SRC.CHRTRANS]BUILD-CHRTRANS.COM "CHRcc_opts ="
```

`SEARCH` reads the highest version, which is what DCL will execute. Every
`cc_opts`/`CHRcc_opts` **assignment** must show `/ACCEPT=NOVAXC_KEYWORDS`.
The `cc_opts = cc_opts + "/DEBUG/NOOPT"` lines are *appends* and correctly
show no `/ACCEPT` — they concatenate onto the value set above them.

### 3. Select the compiler

```dcl
$ DEFINE DECC$CC_DEFAULT "/DECC"
```

`BUILD.COM` tests this logical to decide between its DECC, GNUC and VAXC
branches.

**This logical is critical, and it is a process logical — it disappears when
you log out.** That matters, because raising PGFLQUOTA requires exactly that.

If it is not set, build.com takes its `ELSE` branch, which changes far more
than the `.OPT` file:

| | DECC branch | VAXC branch (no logical) |
|---|---|---|
| compile | `cc/decc/prefix=all/nomember` | `cc` |
| defines | `ACCESS_AUTH,<transport>,__VMS_CURSES` | `ACCESS_AUTH,<transport>` |
| links | `[.SRC]DECC.OPT` | `[.SRC]VAXC.OPT` |

`/PREFIX=ALL` governs how C RTL calls are resolved, and `DECC.OPT` links
`sys$library:vaxcrtl/library` where `VAXC.OPT` links the shareable
`sys$share:vaxcrtl/share`. Take the DECC branch.

(`/NOMEMBER` is `/NOMEMBER_ALIGNMENT`, struct packing — but on OpenVMS **VAX**
that is already the default, so it is a no-op here. It matters on Alpha/I64.)

Make it persistent before building:

```dcl
$ DEFINE/SYSTEM/EXECUTIVE_MODE DECC$CC_DEFAULT "/DECC"
```

or add `$ DEFINE DECC$CC_DEFAULT "/DECC"` to `LOGIN.COM`. Verify mid-build that
the log shows `cc/decc/prefix=all/nomember` and that the link pulls `DECC.opt`,
not `VAXC.opt`. If you ever build the two halves in different states, `@CLEAN`
and rebuild everything — a partial rebuild will not fix it.

### 4. Pre-flight

```dcl
$ SET DEFAULT [000000.LYNX293]
$ @PREFLIGHT
```

Checks the compiler logical, the four patched lines, both `.OPT` files, what
those `.OPT` files point at, the UCX headers, and free space. It locates the
tree top itself if run from a subdirectory. **[verified]**

### 5. Probe the header chain

```dcl
$ SET DEFAULT [.WWW.LIBRARY.VMS]
$ @PROBE2
$ SET DEFAULT [---]
```

Compile-only test that mirrors `HTTCP.c`'s include set — the module most
exposed to TCP-stack header incompatibilities — using libmake's exact
`/DEFINE=(UCX,ACCESS_AUTH)` and four-directory `/INCLUDE`. It declares
`struct timeval`, `struct sockaddr_in`, `struct hostent` and calls
`socket`/`connect`/`select`/`gethostbyname`/`htons`/`FD_SET`.

Expect `PROBE2: header chain is SOUND`. This takes ~30 seconds and tells you
in advance what you would otherwise learn 40 minutes into the library
build. **[verified]**

### 6. Build

```dcl
$ SUBMIT/NOPRINT/LOG=BUILD.LOG/NOTIFY BUILD.COM/PARAMETERS=("UCX")
```

Expect a long run. Order is: libwww-FM library (36 modules) → `makeuctb.exe`
and the chrtrans headers → the 46 `[.SRC]` modules → link.

Without a batch queue, run it in the foreground and log the session instead:

```dcl
$ SET HOST 0/LOG=BUILD.LOG
   ... log in again ...
$ SET DEFAULT [000000.LYNX293]
$ @BUILD "UCX"
$ LOGOUT
```

On a fresh tree neither "already exists — update it?" prompt fires. In batch
they auto-take the update path anyway.

### 7. Check the log

```dcl
$ SEARCH BUILD.LOG "%CC-E","%CC-F","%LINK-W","%LINK-E","%LIB-"
$ SEARCH BUILD.LOG "IMPLICITFUNC"
```

The first thing to confirm is that libmake's `SHOW SYM CC` echoes
`/ACCEPT=NOVAXC_KEYWORDS`. If that is right and `HTString`, `HTParse` and
`HTAccess` compile clean, every remaining module uses the same symbol.

`BUILD.COM` links in `[.SRC]` and then copies the image up:

```dcl
$ DIR [000000.LYNX293]LYNX.EXE
```

---

## Post-build

```dcl
$ DEFINE/SYSTEM Lynx_Dir DKA0:[000000.LYNX293]
$ LYNX :== $DKA0:[000000.LYNX293]LYNX.EXE
```

`Lynx_Dir` is the logical Lynx's VMS defaults are built around —
`userdefs.h` sets `LYNX_CFG_FILE` to `Lynx_Dir:lynx.cfg`, and likewise
`Lynx_Dir:mime.types` and `Lynx_Dir:mailcap`. The `LYNX_CFG` logical
overrides the config file location if you want it elsewhere.

### No SSL in this build

`BUILD.COM` was run without the `SSL` option, so this image has **no TLS**.
`https://` URLs will fail outright — which is most of the modern web. Options:
build against an OpenSSL port for VMS VAX (difficult), or run an
HTTP-to-HTTPS proxy on another machine and point Lynx at it with the
`http_proxy` logical.

Optional, to put the help text in the system help library:

```dcl
$ LIBRARY/REPLACE SYS$HELP:HELPLIB.HLB LYNX.HLP
```

`HELPFILE` in `userdefs.h` defaults to the upstream URL. To use the bundled
`[.LYNX_HELP]` tree offline, set `HELPFILE` in `lynx.cfg`.

---

## Things that look relevant but are not

The `PROBLEMS` file describes two long-standing VMS issues. **Neither applies
to a DEC C + UCX build:**

- **MultiNet `struct timeval` "has no linkage"** — the workaround lives
  entirely inside `#ifdef MULTINET` in
  `[.WWW.LIBRARY.IMPLEMENTATION]WWW_TCP.H` (lines 444–530). UCX is the
  separate branch at lines 544–563. The `PROBLEMS` text is also stale: it
  tells you to delete `#ifdef NOT_DEFINED`/`#endif` lines, but upstream
  replaced that years ago with a `/*#define NO_TIMEVAL*/` toggle you
  uncomment.
- **SOCKETSHR 0.9D / NETLIB 2 breaking ftp** — `#ifdef SOCKETSHR_TCP` only,
  and it is a bug inside SOCKETSHR's own `getsockname()`/`getpeername()`,
  not in Lynx. The KCL fileserver URLs in `PROBLEMS` are long dead.

Also checked and found clear, so do not go hunting here:

- **No C99 constructs.** The `//` hits in `HTMIME.c` and `SGML.c` are inside
  `/* */` blocks; `long long` in `HTUtils.h` is behind `HAVE_LONG_LONG`,
  which the VMS build never defines.
- **The module lists are correct for 2.9.3.** `BUILD.COM` compiles 46 of the
  57 files in `[.SRC]`. The 11 it skips are all feature-gated —
  `USE_COLOR_STYLE` (`LYHash`, `LYStyle`), `DIRED_SUPPORT` (`LYLocal`),
  `USE_EXTERNALS` (`LYExtern`), `USE_PRETTYSRC`, `EBCDIC`, Win32/DOS
  (`Xsystem`), gnutls (`tidy_tls`), and the `mktime`/`strstr`/`wcwidth`
  fallbacks. `LIBMAKE.COM` likewise compiles 36 of the 39 files in
  `[.WWW.LIBRARY.IMPLEMENTATION]`, skipping `HTDOS.c` (`_WINDOWS`),
  `HTTLS.c` (`USE_SSL`) and `dtd_util.c` (a standalone utility, not part of
  the library).
- **`globaldef`/`globalref` are safe under either flag.** `WWW_TCP.H` line
  646 only uses them under `#if defined(VAXC) && !defined(__DECC)`, which is
  false for a DEC C build; everything falls through to the
  `#ifndef GLOBALREF` defaults.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| `%CC-E-DECLARATOR` on `int readonly;` | the `/ACCEPT` flag did not reach the compiler — check `SHOW SYM CC` in the log |
| `%DCL-W-SYMDEL, invalid symbol or value delimiter` | DCL has no `;` statement separator; one statement per `$` line |
| `%SEARCH-W-OPENIN ... BUILD.COM` | run from the tree top; these procedures use paths relative to the *current* default, not their own location |
| `%DCL-E-OPENIN ... PROBE2.COM` | `PROBE2` must be run from `[.WWW.LIBRARY.VMS]` — its `/INCLUDE` is written relative to that directory |
| `-JBC-E-JOBQUEDIS` | queue manager not started — see Prerequisites |
| `%CC-E-INCOMPMEM` on `soc_in` in `WWW_TCP.H` | `CHRcc_opts` is missing the transport define — see above |
| `%CLI-F-TEXT, Compiler abort - virtual memory limits exceeded` | PGFLQUOTA too low for `GridText.c` — see Process quotas |
| `-version` and local `file://` work, but `http://` gives `%SYSTEM-F-ACCVIO` | fault is confined to the network path; get `lynx -trace` output before rebuilding |
| `%LINK-W-USEUNDEF` on curses symbols | `VAXCCURSE.OLB` missing; adjust `[.SRC]DECC.OPT` |
| build succeeds but behaves oddly | check `SEARCH BUILD.LOG "IMPLICITFUNC"` — implicit declarations return `int`, which corrupts pointer returns |

---

## Helper files

These are not part of stock Lynx; they were written for this build and live
in `[.VAXPROBE]` unless noted.

| File | Run from | Purpose |
|---|---|---|
| `PROBE.C` / `PROBE.COM` | anywhere | compiles one 46-line file three ways to prove which flag fixes `readonly` |
| `PROBE2.C` / `PROBE2.COM` | `[.WWW.LIBRARY.VMS]` | compile-only test of the DECC/UCX header chain |
| `PREFLIGHT.COM` | tree top (also in `[000000.LYNX293]`) | checks link prerequisites before a long build |
| `PATCHVMS.COM` | tree top | applies the four edits in place, for when pasting beats file transfer |

`PROBE.COM` is worth keeping: if a future DEC C or TCP/IP upgrade breaks the
build, it re-answers the flag question in 30 seconds.

If pasting these through a serial terminal, `SET TERMINAL/HOSTSYNC/TTSYNC`
first to avoid overruns.

---

## License

Lynx is **GPL v2** (version 2 only). See `COPYING` and `COPYHEADER`; the
libwww-FM code under `[.WWW.LIBRARY]` is **LGPL v2**, see
`[.WWW.LIBRARY.VMS]COPYING.LIB`. Copyright 1997-2025,2026 Thomas E. Dickey and
the lynx-dev contributors; original Lynx copyright 1995 University of Kansas.

Redistribution, including of modified versions, is permitted. `COPYHEADER`
grants explicit permission covering "building, modifying, distributing modified
versions." If you redistribute this tree:

- keep `COPYING`, `COPYHEADER` and `COPYING.LIB` intact — `COPYHEADER` requires
  inclusion in all copies or substantial portions;
- the three build procedures carry GPL §2(a) notices recording what was changed
  and when;
- label the whole as **GPL-2.0**, not "GPL-2.0-or-later" — Lynx is version-2-only.

Upstream lives at <https://lynx.invisible-island.net/>. Licensing questions go
to lynx-dev@nongnu.org.

The helper files (`PROBE.C`, `PROBE2.C`, `PREFLIGHT.COM`, `PATCHVMS.COM`,
`PROBE.COM`, `PROBE2.COM`) are new work, not derived from Lynx source. Pick a
license for them or mark them public domain.
