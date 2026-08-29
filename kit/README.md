# Lynx 2.9.3 — VMSINSTAL kit for OpenVMS VAX

A ready-to-install kit for OpenVMS VAX V7.3 (built and verified on a MicroVAX,
DEC C / Compaq C V6.4, TCP/IP Services "UCX"). Built to the recipe in
`VMS_dev_notes/VMSINSTAL_KIT_HOWTO.md`.

**This build contains a fix without which `http://` does not work at all** — see
[The fix this kit carries](#the-fix-this-kit-carries) below.

---

## Installing

The save set `LYNX293.A` is committed here, so you do not need a VAX build
toolchain to install Lynx — just get the file onto the VAX. It is 2,285,568
bytes (4464 blocks).

### Getting the save set onto the VAX

**Transfer it in binary/image mode.** A save set is fixed-length 2048-byte
records; ASCII mode silently corrupts it and the install fails at restore with
`INVBLKSIZE` or a CRC error.

By FTP, from a machine that can reach the VAX:

```
ftp> binary
ftp> put LYNX293.A
```

Then, on the VAX, **restore the record attributes**. A file arriving over FTP or
out of a zip usually lands as a stream file, and BACKUP will not read it:

```dcl
$ SET FILE/ATTRIBUTES=(RFM:FIX,MRS:2048,LRL:2048,RAT:NONE) LYNX293.A
```

Check it took — `DIRECTORY/FULL LYNX293.A` should say:

```
Record format:      Fixed length 2048 byte records
Record attributes:  None
Size:               4464/4464
```

If the record format says anything else, fix it before installing; every other
symptom you would chase from here is a consequence of this one.

### Running the install

Put `LYNX293.A` in a directory on the VAX, then:

```dcl
$ @SYS$UPDATE:VMSINSTAL LYNX293 device:[dir-containing-the-saveset]
```

VMSINSTAL asks two questions before it starts:

```
%VMSINSTAL-W-ACTIVE, The following processes are still active:
        TCPIP$FTP_1 ...
* Do you want to continue anyway [NO]?     -> YES
* Are you satisfied with the backup of your system disk [YES]?   -> YES
```

Answering `YES` to the first is normal and expected — those are the TCP/IP
service processes, and the install does not touch them.

The install then reports:

```
  Lynx V2.9-3 installed in SYS$SYSTEM:.
  Configuration:  SYS$COMMON:[LYNX]LYNX.CFG
```

### After installing

```dcl
$ @SYS$MANAGER:LYNX$STARTUP
$ LYNX -version
$ LYNX http://example.local/
```

Add the startup line to `SYS$MANAGER:SYLOGIN.COM` so every user gets it, or to a
personal `LOGIN.COM`.

Optionally add the VMS help text to the system help library:

```dcl
$ LIBRARY/REPLACE SYS$HELP:HELPLIB.HLB SYS$HELP:LYNX.HLP
```

### What gets installed where

| File | Destination | Why |
|---|---|---|
| `LYNX.EXE` | `SYS$SYSTEM:` | the browser |
| `LYNX.CFG` | `SYS$COMMON:[LYNX]` | global configuration; `Lynx_Dir` points here |
| `LYNX.HLP` | `SYS$HELP:` | VMS-format help text |
| `LYNX$STARTUP.COM` | `SYS$MANAGER:` | defines the `LYNX` command and `Lynx_Dir` |

`LYNX$STARTUP.COM` does two things, and **both matter**:

```dcl
$ DEFINE/NOLOG Lynx_Dir SYS$COMMON:[LYNX]
$ LYNX == "$SYS$SYSTEM:LYNX.EXE"
```

Without `Lynx_Dir`, Lynx exits immediately with

```
Configuration file "Lynx_Dir:lynx.cfg" is not available.
```

That is fatal, not a warning (`LYMain.c:1548` calls `exit_immediately`). `Lynx_Dir`
is a **process** logical, so it dies on logout — which is exactly why it belongs
in a startup procedure rather than being typed by hand.

Re-installing does **not** overwrite a `LYNX.CFG` you have customised; the new one
is left beside it as `LYNX.CFG-NEW`.

---

## Building the kit

You only need this if you have changed the source. To install, use the committed
`LYNX293.A` above.

On the VAX, after a successful `@BUILD` has produced `LYNX.EXE` at the top of the
source tree:

```dcl
$ SET DEFAULT device:[LYNX293.KIT]
$ @MAKE_KIT
```

That produces `LYNX293.A` in the same directory and prints the install command.
`MAKE_KIT.COM` copies `LYNX.EXE`, `LYNX.CFG` and `LYNX.HLP` in flat from the parent
directory, builds the save set, and deletes the flat copies again.

Two details in `MAKE_KIT.COM` are not optional:

- **`/BLOCK_SIZE=2048`.** BACKUP's disk default (32256) makes VMSINSTAL misframe
  the save set; it fails at restore with `INVBLKSIZE` or CRC errors.
- **Inputs are flat, by bare name.** VMSINSTAL restores save set A into `VMI$KWD:`
  with no subdirectories, and `KITINSTAL.COM` copies from there by bare name.

`KITINSTAL.COM` uses plain `COPY`, not the `VMI$CALLBACK PROVIDE_IMAGE` /
`PROVIDE_FILE` callbacks, which are unreliable across VMS versions.

No `*.RELEASE_NOTES` file is shipped inside the save set — VMSINSTAL auto-detects
one, moves it, then its deferred cleanup tries `[SYSHLP]*.RELEASE_NOTES` again and
dies with `%RMS-F-WLD`. Release notes ship as `RELEASE_NOTES.TXT` instead.

### Files here

| File | Role |
|---|---|
| `KITINSTAL.COM` | the install procedure; must be in save set A |
| `LYNX$STARTUP.COM` | goes to `SYS$MANAGER:`; defines the command and logical |
| `MAKE_KIT.COM` | builds `LYNX293.A` |
| `RELEASE_NOTES.TXT` | documentation only — deliberately **not** in the save set |
| `LYNX293.A` | the built save set; this is what you install |

### A cosmetic note on the version

VMSINSTAL parses the product name as `<FACILITY><VVU>`, so `LYNX293` is announced
as `LYNX V29.3` rather than `V2.9-3`. Three digits cannot express `2.9-3` in that
scheme. It is display-only and affects nothing.

---

## The fix this kit carries

Stock Lynx 2.9.3 **cannot fetch any URL over HTTP on OpenVMS when built with DEC C.**
Every attempt dies with:

```
%SYSTEM-F-ACCVIO, access violation, reason mask=05, virtual address=..., PC=...
%SYSTEM-F-RADRMOD, reserved addressing fault at PC=..., PSL=03C00020
```

The cause is unbounded recursion in `HTDoRead()`:

```c
/* WWW/Library/Implementation/HTTCP.c:2534 */
result = NETREAD(fildes, (char *) buf, nbyte);

/* WWW/Library/Implementation/www_tcp.h:46-47 */
#define NETREAD(s,p,n)  HTDoRead(s, p, (unsigned)(n))
```

`HTDoRead` calls itself. Every response read recurses until the stack is
destroyed, which is why the faulting PC moves between runs, why the second
exception executes *on the stack*, and why VMS prints no traceback — the
traceback handler cannot walk a corrupted stack. Local `file://` rendering is
unaffected because it uses stdio, not this path.

Three `#if` branches guard that line. `UCX && VAXC` and `UNIX` both correctly call
`SOCKET_READ`; the fall-through `#else` is the broken one, and it is what VMS with
DEC C reaches, because DEC C does not predefine `VAXC`.

This is an **upstream regression**: Lynx 2.8.8 had `SOCKET_READ` at the
corresponding line (2313). The fix restores it.

Verified on OpenVMS VAX V7.3 / DEC C / UCX: HEAD and GET both return real
responses and render correctly.
