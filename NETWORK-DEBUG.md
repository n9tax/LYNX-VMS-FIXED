# Debugging the HTTP ACCVIO — Lynx 2.9.3 / OpenVMS VAX 7.3 / UCX

Continuation of `HANDOFF.md`. Local rendering works; every `http://` fetch
dies with

```
%SYSTEM-F-ACCVIO, access violation, reason mask=05, virtual address=7D700DE8, PC=8000033C
%SYSTEM-F-RADRMOD, reserved addressing fault at PC=7FEBE6CA, PSL=03C00020
```

Everything in **Verified** below was read out of this tree. Everything in
**Hypotheses** is a guess with a test attached. Run the tests before
believing any of it.

---

## Verified from the source

**1. The exact call sequence an `http://` fetch takes.**

`HTLoadHTTP` → `HTDoConnect` (`WWW/Library/Implementation/HTTCP.c:1814`), then:

| # | Call | Line |
|---|---|---|
| 1 | `HTParseInet(soc_in, host)` | 1916 |
| 2 | `socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)` | 1943 |
| 3 | `IOCTL(*s, FIONBIO, &val)` — set non-blocking | 1980 |
| 4 | `connect(*s, SOCKADDR_OF(sock_A), sizeof(sock_A))` | 2005 |
| 5 | `select()` loop, 0.1s ticks | 2070 |
| 6 | `IOCTL(*s, FIONBIO, &val)` — restore blocking | 2243 |
| 7 | `HTDoRead` → `select()` + `NETREAD` | 2403 |

**2. Step 3 is the only place in the whole HTTP path that calls a VMS
system service directly — and it never runs for a local file.**

On UCX, `www_tcp.h:350-353` redefines `IOCTL()` to `HTioctl()`, and
`HTioctl()` (`HTTCP.c:115-160`) does not go through the C RTL at all:

```c
if ((sdc = vaxc$get_sdc(d)) == 0) { ... }
...
status = sys$qiow(0, sdc, fun, iosb, 0, 0, 0, 0, 0, 0, p5, p6);
```

The reported `PC=8000033C` is in **system space** (S0), which is where a
system service executes, and `reason mask=05` is a write to an unmapped
address. A bad `$QIOW` argument list produces exactly that shape of
failure. This is consistent, not conclusive — a corrupted stack reaching
any system service would look the same, and the second exception
(`RADRMOD` at a different PC) suggests the condition handler also fell
over, which is itself a stack-corruption signature.

**3. There is a supported switch that removes step 3 entirely.**

`NO_IOCTL` is honoured at `HTTCP.c:1968`, `2233`, `2410` and `2444`. With
it defined, both `FIONBIO` calls disappear and `HTDoRead` does a plain
blocking read. The only functional loss is that a connect or a read can no
longer be interrupted with `z`. Nothing else changes, and on the UCX path
`NO_IOCTL` has no effect inside `www_tcp.h` (its uses there are in the
`WIN_TCP` and generic branches).

So if step 3 is the fault, the fix is one word in a `/DEFINE=`.

**4. A bare numeric IP genuinely never touches the resolver.**

`HTParseInet` (`HTTCP.c:1345-1377`) counts dots; on `dotcount_ip == 3` it
calls `inet_addr()` and returns. `LYGetHostByName` is only reached in the
`else`. The handoff was right to keep the DNS problem separate — but note
this also means **`LYGetHostByName` has never been exercised**, so it is
not exonerated, merely untested.

**5. The `VAXC`-conditional workarounds are inactive in this build.**

`HTTCP.c:1805` and `HTTCP.c:2504` are `#if defined(UCX) && defined(VAXC)`.
DEC C does not predefine `VAXC` unless `/STANDARD=VAXC` is in effect, so
both blocks are compiled out — the errno-modification guard and the
"EPIPE means EOF" read workaround. This is true of **both** build.com
branches, so it is not a difference between them, but it is worth knowing
that the code believes it is talking to DEC C, not VAX C.

**6. The trace log is not where the handoff says it is.**

`LYMain.c:1199-1203` runs `FNAME_LYNX_TRACE` through `LYAddPathToHome()`,
so it lands in **`SYS$LOGIN:LYNX.TRACE`**, not the current directory.
`userdefs.h:1524` sets the name. If a previous `-trace` run appeared to
produce nothing, look there. `LYNX_TRACE_FILE` overrides the path.

---

## Do this first — costs nothing, no rebuild

**A. Read the link map you already have.** `build.com` links with
`/MAP=LYNX`, so `[.SRC]LYNX.MAP` exists from the successful build.

```dcl
$ SEARCH [.SRC]LYNX.MAP "DECC$"
$ SEARCH [.SRC]LYNX.MAP "UCX$IPC_SHR","VAXCRTL"
$ SEARCH [.SRC]LYNX.MAP "GET_SDC"
```

This settles the handoff's leading hypothesis in ten seconds:

* **No `DECC$` symbols at all** → the objects were compiled without
  `/PREFIX=ALL`, i.e. build.com took its ELSE branch. Confirms it.
* **`DECC$` symbols present** → the DECC branch was used after all and the
  whole compiler-branch theory is dead. Say so and move on.

The second search shows which shareable images were bound, and in what
order. `build.com` links `UCXSHR.opt` **before** the RTL options file, so
`SYS$SHARE:UCX$IPC_SHR` is searched first and gets first claim on any
unprefixed name it exports.

**B. Confirm the stack works at all** (still outstanding from the handoff):

```dcl
$ TCPIP PING /NUMBER=3 188.184.67.127
$ TELNET 188.184.67.127 80
   GET / HTTP/1.0            ! then two Returns
```

**C. Get the trace, from the right place:**

```dcl
$ LYNX -trace -dump http://188.184.67.127/hypertext/WWW/TheProject.html
$ SEARCH SYS$LOGIN:LYNX.TRACE "HTParseInet","HTDoConnect","socket","Parsed address"
```

The tail may be lost to buffering when the image dies — that is expected,
and is why the probe below exists.

---

## Then run the probe — four builds, about a minute

`vaxprobe/probe3.c` and `vaxprobe/probe3.com` are new in this tree. The
probe reproduces steps 1-7 above with the same headers and a **verbatim
copy of `HTioctl()`**, printing and flushing before every call, so the
last line you see is the call that died.

```dcl
$ SET DEFAULT [.VAXPROBE]
$ @PROBE3 188.184.67.127
```

It builds the probe two ways and runs each twice:

| Run | Compiled | Linked | ioctl |
|---|---|---|---|
| A1 | `cc/accept=novaxc_keywords` | `sys$share:vaxcrtl/share` | yes |
| A2 | same | same | no |
| B1 | `cc/decc/prefix=all/nomember/accept=...` | `sys$library:vaxcrtl/library` | yes |
| B2 | same | same | no |

A mirrors how `LYNX.EXE` was actually built. B mirrors build.com's DECC
branch. Reading the result:

| Outcome | Meaning | Fix |
|---|---|---|
| **A1 crashes, A2 works** | `HTioctl`/`FIONBIO` is the fault | Fix 1 below |
| **A* crash, B* work** | compiler branch / RTL is the fault | Fix 2 below |
| **A1 crashes, B1 works, A2 works** | both are involved | Fix 2, then retest |
| **All four work** | the socket layer is fine; the fault is higher up in Lynx — go back to the trace | — |
| **All four crash** | UCX itself, or the probe's own headers | check step B above |

---

## PROBE RESULT — 2026-08-28: the socket layer is exonerated

All four runs completed and returned HTTP headers from CERN. Recorded here
so nobody re-runs this.

| Run | Compile | RTL | ioctl | Result |
|---|---|---|---|---|
| A1 | no `/PREFIX=ALL` | `sys$share:vaxcrtl/share` | yes | **215 bytes, clean** |
| A2 | no `/PREFIX=ALL` | `sys$share:vaxcrtl/share` | no | **215 bytes, clean** |
| B1 | `/decc/prefix=all/nomember` | `sys$library:vaxcrtl/library` | yes | **215 bytes, clean** |
| B2 | `/decc/prefix=all/nomember` | `sys$library:vaxcrtl/library` | no | **215 bytes, clean** |

**Both hypotheses are dead.**

* **`HTioctl`/`FIONBIO` is not the fault.** It works. `vaxc$get_sdc(3)`
  returned a valid channel (256 under branch A, 240 under branch B — the
  value differs because the two RTLs number channels differently, and both
  are fine), `sys$qiow` returned SS$_NORMAL with `iosb[0]=1`, both on the
  way into non-blocking mode and on the way back out. **Fix 1 below is not
  needed** — do not define `NO_IOCTL`.
* **The compiler branch is not the fault, at least not here.** Branch A —
  which is how `LYNX.EXE` was actually built — connected, wrote and read
  exactly as well as branch B. **Fix 2 below is not justified by this
  evidence.** Do not spend hours on that rebuild yet.
* Non-blocking connect behaved textbook-correct under both: `connect()`
  returned -1 with `errno = 36` (EINPROGRESS), `select()` reported the
  socket writable on the first 0.1s tick.
* UCX is healthy and `SYS$SHARE:UCX$IPC_SHR` is the image in use. PING and
  TELNET are no longer needed — we have a real HTTP transaction.
* Both branches compiled with 0 errors and 0 warnings. `FIONBIO` and
  `UCX$C_IOCTL` are reachable through the UCX header chain, which had been
  uncertain.

**So the fault is above the socket layer**, somewhere in Lynx's own code:
request assembly, the response reader, the MIME header stream, or the
stream stack. `HTDoConnect`'s system calls are proven good.

Note also, from the probe output: `188.184.67.127` answers `/` with a
**302** to `http://webafs902.cern.ch.web.cern.ch/...` and
`Content-Type: application/x-perl`. Following that redirect needs DNS,
which this box does not have, and it would route into `LYGetHostByName` —
code that has never been exercised. Test against a URL that returns 200
directly, or you will conflate two bugs.

---

## Next: bisect with the binary you already have

### First — `Lynx_Dir` must be defined, or nothing below runs

A missing `lynx.cfg` is **fatal**, not a warning:
`LYMain.c:1548-1554` prints `Configuration file "..." is not available.`
and calls `exit_immediately(EXIT_FAILURE)`. `userdefs.h:108` makes the
default `Lynx_Dir:lynx.cfg`, and `Lynx_Dir` is a process logical that dies
on logout — the same trap that lost `DECC$CC_DEFAULT` earlier in this
project. If you see that message, Lynx never started and the run tells you
nothing about the ACCVIO.

Put both of these in `LOGIN.COM` so it stops recurring:

```dcl
$ DEFINE Lynx_Dir DKA0:[000000.LYNX-VMS-FIXED]
$ LYNX :== $DKA0:[000000.LYNX-VMS-FIXED]LYNX.EXE
```

Or sidestep the logical entirely on each command — `-cfg` is parsed at
`LYMain.c:1394`, before the check, so this always works:

```dcl
$ LYNX -cfg=DKA0:[000000.LYNX-VMS-FIXED]LYNX.CFG -dump http://127.0.0.1:1/
```

Confirm Lynx is alive before trusting any bisect result:

```dcl
$ LYNX -version
```


No rebuild, no new files. Each command stops Lynx at a different depth.
**The first one that crashes names the layer.** Run them in order.

```dcl
$ LYNX -dump http://127.0.0.1:1/
```
Nothing listens on port 1, so the connect is refused immediately — this
never leaves the machine and needs no DNS.
* **Clean "Unable to connect to remote host"** → the whole connect path is
  fine in the real binary too, and the crash is in *response handling*.
  Go on to the next command.
* **ACCVIO** → the fault is at or before the connect, in Lynx's code
  *around* the syscalls the probe just cleared — progress messages, anchor
  setup, or `HTLoadHTTP`'s entry. That is a very different search.

```dcl
$ LYNX -head -dump http://188.184.67.127/hypertext/WWW/TheProject.html
```
Sends HEAD: status line and headers, no body.
* Works → the fault is in **body/stream handling**.
* Crashes → the fault is in **request assembly or MIME header parsing**.

```dcl
$ LYNX -mime_header -dump http://188.184.67.127/hypertext/WWW/TheProject.html
$ LYNX -source      -dump http://188.184.67.127/hypertext/WWW/TheProject.html
$ LYNX              -dump http://188.184.67.127/hypertext/WWW/TheProject.html
```
Raw headers + source; then source with no HTML parse; then the full stack.
The step at which it starts crashing is the layer at fault.

## BISECT RESULT — 2026-08-28: it is in the response path, and the stack is being smashed

```
$ LYNX -dump http://127.0.0.1:1/
Looking up 127.0.0.1:1
Making HTTP connection to 127.0.0.1:1
Alert!: Unable to connect to remote host.
lynx: Can't access startfile http://127.0.0.1:1/          <-- CLEAN, no crash

$ LYNX -head -dump http://188.184.67.127/hypertext/WWW/TheProject.html
%SYSTEM-F-ACCVIO, ... virtual address=7EC125FC, PC=84284A72, PSL=03C00004
%SYSTEM-F-RADRMOD, reserved addressing fault at PC=7FEBE6CA, PSL=03C00020
```

**The connect path is confirmed good in the real binary**, matching the
probe. `HTDoConnect` returns cleanly, the alert is the correct one, and
Lynx exits normally. Everything up to and including `connect()` is fine.

**The fault is between "connect succeeded" and "first response line
parsed".** `-head` sends a request and reads only the status line and
headers — no body — and that is enough to kill it. The deeper rungs
(`-mime_header`, `-source`, plain `-dump`) are therefore redundant; they
all include this window.

### Read the register dump, not the ACCVIO address

This is the important part, and it changes what to chase.

* `SP = 7FEBE7AC`, `FP = 7FEBE738` — the stack is at `7FEBE7xx`.
* The second exception is a **reserved addressing fault at
  `PC=7FEBE6CA`** — which is *on the stack*, about 0xE2 bytes below SP.
  The CPU was trying to execute stack memory.
* The first exception's PC **changed between runs**: `8000033C` on the
  original report, `84284A72` here. A stable bad pointer does not move.

Taken together: by the time the ACCVIO is signalled the **stack is already
corrupted**, condition dispatch transfers to garbage, and the RADRMOD is
the aftermath. **The ACCVIO PC and faulting address are downstream noise —
do not spend time decoding them.** Look for whatever overwrites the stack
in the window above.

### Ruled out by reading, so nobody re-checks

* `char temp[80]` at `HTTP.c:473`, `sprintf`-ed at `HTTP.c:700-706` during
  Accept-header assembly. `PRI_off_t`/`CAST_off_t` resolve consistently on
  this build: with no `config.h`, `HAVE_CONFIG_H`/`SIZEOF_OFF_T`/
  `HAVE_LONG_LONG` are all undefined, so `HTUtils.h:631-633` gives
  `PRI_off_t "ld"` with `CAST_off_t(n) (long)(n)` — 4-byte format, 4-byte
  argument, and the longest output is ~32 characters. Safe.
* The status-line read loop at `HTTP.c:1140-1265`. `line_buffer` is heap,
  doubles before each read, reads `buffer_length - length - 1`, and
  `MemCpy(line_kept_clean, line_buffer, buffer_length)` is same-sized.
  The `#ifdef UCX` EOF guard at 1233 is correct — and note the probe saw
  `read()` return **0** at EOF on this stack, not -1, so the normal
  `status == 0` path is what runs.
* `www_tcp.h:478`'s `#define off_t int` is gated on `_DECC_V4_SOURCE`,
  which `build.com` adds only for MULTINET and SOCKETSHR — not UCX. So
  `off_t` is consistent between `[.SRC]` and the library here.

### The strongest remaining lead: implicit function declarations

`libmake.com`'s DECC branch compiles the whole library with
`/warning=(disable=implicitfunc)`. That is not cosmetic. `HTUtils.h:71`
sets `NO_UNISTD_H` on VMS, so a number of functions are called with **no
prototype in scope**, and get default argument promotions instead of the
real parameter types. Where the callee actually expects an `off_t`, a
`double`, or a struct, the caller and callee then disagree about the
argument list — which writes and reads the wrong stack slots. That is a
textbook stack-corruption mechanism, and it would be invisible in a local
file render if the mismatched call only happens on the network path.

`HTReadProgress(off_t, off_t)` is called at `HTTP.c:1145` and `1231`,
inside exactly the failing window, and takes two `off_t` arguments.

**Next step, cheap:** the ELSE branch of `build.com` does *not* disable
that diagnostic, so a rebuild already prints every one. Rebuild and
collect the `%CC-I-IMPLICITFUNC` list for `HTTP.c`, `HTMIME.c` and
`HTTCP.c`, then check each named function's real signature. Any call whose
arguments are not all plain `int`/`char *` after promotion is a suspect.

**Next step, decisive:** the process dump below names the routine outright.

### Two ways to get a name for the failing routine

**The trace log is still worth having, despite the buffering.** It is
block-buffered stdio with no `setvbuf` anywhere in the tree, so the last
buffer is lost — but only the last buffer. Everything before it is on
disk, which localises the crash to within a few lines:

```dcl
$ LYNX -trace -dump http://188.184.67.127/hypertext/WWW/TheProject.html
$ TYPE SYS$LOGIN:LYNX.TRACE
```

`-tlog` does **not** redirect trace to stderr here: it is a mask-2
argument (`LYMain.c:4003`) and is parsed after `LYOpenTraceLog()` runs at
`LYMain.c:1211`. And making the log unopenable is not a workaround either
— `TracelogOpenFailed()` calls `exit_immediately()` when curses is off
(`LYMainLoop.c:257-266`).

**A process dump gives the actual call stack**, which is better:

```dcl
$ SET PROCESS/DUMP
$ LYNX -dump http://188.184.67.127/hypertext/WWW/TheProject.html
$ ANALYZE/PROCESS_DUMP LYNX.DMP
DBG> SHOW CALLS
DBG> EXIT
```

`build.com` links without `/NOTRACEBACK`, so the image carries a traceback
symbol table and `SHOW CALLS` should give routine names, not just
addresses. This is the single most informative thing left to try.

---

## Fix 1 — if the ioctl is the fault  (RULED OUT 2026-08-28)

`HTTCP.c` is compiled by `libmake.com`, so that is the file that matters.
In `WWW/Library/vms/libmake.com`, line 50:

```
$ extra_defs = ",ACCESS_AUTH"
```
becomes
```
$ extra_defs = ",ACCESS_AUTH,NO_IOCTL"
```

And in `build.com`, line 78, for consistency:

```
$ extra_defs = ""
```
becomes
```
$ extra_defs = ",NO_IOCTL"
```

Then `@CLEAN` and `@BUILD "UCX"`, answering **Y** to the library prompt —
the library must be recompiled, that is where `HTTCP.c` lives.

Cost: `z` no longer interrupts a hung connect or read. Everything else is
unaffected.

## Fix 2 — if the compiler branch is the fault  (NOT SUPPORTED BY THE PROBE)

The branch test is at `build.com:285`, `libmake.com:158` and
`build-chrtrans.com:40`. It depends on `DECC$CC_DEFAULT`, which is a
**process** logical and dies on logout — which is how the wrong branch got
taken in the first place.

Rather than re-defining the logical and hoping it survives, force it. In
each of the three files change

```
$ THEN
$  compiler := "DECC"
```

to be reached unconditionally, or more simply put this immediately before
each `IF f$getsyi("ARCH_NAME")` line:

```
$ DEFINE/JOB DECC$CC_DEFAULT "/DECC"
```

`/JOB` survives across the whole job tree including subprocesses, which
`/PROCESS` does not. If you have the privilege, `/SYSTEM/EXECUTIVE_MODE`
in `SYSTARTUP` is better still.

Then confirm from the build log that the compile line reads
`cc/decc/prefix=all/nomember` and the link pulls `DECC.opt`, not
`VAXC.opt`.

This is the expensive fix — a full `@CLEAN` and rebuild. **Do not start it
until the map search in step A or the probe says the branch is actually
implicated.**

---

## What has not been ruled out

* `LYGetHostByName` — untested, because the bare-IP repro skips it. Once
  HTTP works by IP, `http://info.cern.ch/` is the next test, and it needs
  the resolver configured first.
* Stack quota. The `RADRMOD` second exception is a stack-corruption
  signature as much as a bad-argument one. If the probe comes back clean
  on all four runs, `SHOW PROCESS/QUOTA` and the `BYTLM`/`PGFLQUOTA`
  values are worth a look — `PGFLQUOTA` was already raised to 250000 for
  the compiler, but that was for the compile, not the run.
* `HTDoRead`'s `select()` loop — exercised by probe steps 5 and 8, so the
  probe covers it.
