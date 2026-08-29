# Lynx 2.9.3 — VMSINSTAL kit for OpenVMS VAX

A ready-to-install kit for OpenVMS VAX V7.3 (built and verified on a MicroVAX,
DEC C / Compaq C V6.4, TCP/IP Services "UCX"). Built to the recipe in
`VMS_dev_notes/VMSINSTAL_KIT_HOWTO.md`.

**This build contains a fix without which `http://` does not work at all** — see
[The fix this kit carries](#the-fix-this-kit-carries) below.

---

## Installing

The save set `LYNX293.A` is committed here, so you do not need a VAX build
toolchain to install Lynx — just get the file onto the VAX. It is 2,324,480
bytes (4540 blocks).

The save set was rebuilt on the VAX on 29 Aug 2026 and **includes the multi-user
fix** — `Lynx_Dir` is defined `/SYSTEM`, not per-process. Verified on GOZER
(OpenVMS VAX V7.3) by rendering a page from an account holding only `TMPMBX` and
`NETMBX`; see [Verified](#verified) below.

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
Size:               4540/4545
```

The first number is what matters — 4540 blocks used. The allocated figure after
the slash depends on the disk's cluster size and may differ on your system.

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

Check it runs, as the account you installed from:

```dcl
$ @SYS$MANAGER:LYNX$STARTUP
$ LYNX -version
$ LYNX http://example.local/
```

Then wire it up for **everyone** — this is two separate edits, and skipping
either is what leaves Lynx working only for the account that installed it:

```dcl
$ ! 1. SYS$MANAGER:SYSTARTUP_VMS.COM  -- add this line
$ @SYS$MANAGER:LYNX$STARTUP

$ ! 2. SYS$MANAGER:SYLOGIN.COM        -- add the same line
$ @SYS$MANAGER:LYNX$STARTUP
```

They do different jobs and one does not substitute for the other:

| Edit | Runs | Gives you |
|---|---|---|
| `SYSTARTUP_VMS.COM` | once, at boot, privileged | `Lynx_Dir` defined `/SYSTEM`, visible to every process |
| `SYLOGIN.COM` | at every login, as that user | the `LYNX` symbol, which **cannot** be system-wide |

A DCL symbol lives in one process and nowhere else — there is no `DEFINE/SYSTEM`
for symbols — so every user's login really does have to define `LYNX` for
itself. The logical name is the opposite: define it once, `/SYSTEM`, at boot.
Calling the procedure from both places is correct; the login call finds the
system logical already there and only adds the symbol.

If you would rather not touch `SYLOGIN.COM`, each user can put that same line in
their own `SYS$LOGIN:LOGIN.COM`; you still need the `SYSTARTUP_VMS.COM` edit.

> **Editing those two files: mind the search list.** `SYS$MANAGER` resolves
> `SYS$SPECIFIC:[SYSMGR]` *before* `SYS$COMMON:[SYSMGR]`. Anything that writes a
> new file rather than a new version — including `OPEN/WRITE` in DCL — reads the
> common copy but creates its output in `SYS$SPECIFIC:[SYSMGR]`, which then
> silently shadows the real one. This bit us during the 29 Aug 2026 rebuild.
> Name `SYS$COMMON:[SYSMGR]SYLOGIN.COM` explicitly, and confirm afterwards:
>
> ```dcl
> $ DIRECTORY SYS$SPECIFIC:[SYSMGR]SYLOGIN.COM,SYS$SPECIFIC:[SYSMGR]SYSTARTUP_VMS.COM
> ```
>
> `%DIRECT-W-NOFILES` is the answer you want. Anything else is a shadow copy
> that will diverge from the file you think you are maintaining.

`LYNXWIRE.COM` in this directory does the two edits for you, correctly: it
writes a new *version*, stamps the protection explicitly (a `SYLOGIN.COM`
without `World:RE` locks every non-privileged user out at login), and refuses to
touch anything if it cannot find the anchor line.

```dcl
$ @LYNXWIRE "SYS$COMMON:[SYSMGR]SYLOGIN.COM" "TTFT" "$@SYS$MANAGER:LYNX$STARTUP"
$ @LYNXWIRE "SYS$COMMON:[SYSMGR]SYSTARTUP_VMS.COM" "TCPIP$STARTUP" "$ @SYS$MANAGER:LYNX$STARTUP"
```

The second argument is an anchor string that must already appear in the file,
and the new line goes immediately after it. Those two anchors suit a stock
`SYLOGIN.COM` (the `TTFT` line sits inside the "ADD COMMANDS BELOW" block) and a
system running TCP/IP Services; check yours and pick your own if they differ.
Name `SYS$COMMON:` explicitly, as above — that is the search-list trap.

Optionally add the VMS help text to the system help library:

```dcl
$ LIBRARY/REPLACE SYS$HELP:HELPLIB.HLB SYS$HELP:LYNX.HLP
```

### Already installed from an older kit?

Any kit built before 29 Aug 2026 shipped a `LYNX$STARTUP.COM` that defined
`Lynx_Dir` as a *process* logical, so Lynx worked only for the account that ran
the startup procedure. Reinstalling with the current save set fixes it outright.
If you would rather not reinstall, the section below patches a live system.

Symptom: `LYNX` runs for `SYSTEM` (or whoever ran the startup procedure) and for
nobody else. Another user gets

```
%DCL-W-IVVERB, unrecognized command verb - check validity and spelling
```

or, if they have the symbol but not the logical,

```
Configuration file "Lynx_Dir:lynx.cfg" is not available.
```

`LYNX$STARTUP.COM` is plain text, so this needs no reinstall:

1. Copy this directory's `LYNX$STARTUP.COM` to the VAX in **ASCII** mode (it is
   text, unlike the save set) and put it over the installed one:

   ```dcl
   $ COPY LYNX$STARTUP.COM SYS$MANAGER:LYNX$STARTUP.COM
   $ SET PROTECTION=(S:RWED,O:RWED,G:RE,W:RE) SYS$MANAGER:LYNX$STARTUP.COM
   ```

   That last line matters — `SYLOGIN.COM` runs the procedure in each user's own
   process, so an ordinary user has to be able to read it.

2. Add `$ @SYS$MANAGER:LYNX$STARTUP` to **both** `SYS$MANAGER:SYSTARTUP_VMS.COM`
   and `SYS$MANAGER:SYLOGIN.COM`, per the table above.

3. Define the logical now, so you need not reboot to test:

   ```dcl
   $ @SYS$MANAGER:LYNX$STARTUP          ! as a user holding SYSNAM
   $ SHOW LOGICAL/SYSTEM Lynx_Dir
   ```

4. Check as an ordinary user — log in fresh, so `SYLOGIN.COM` runs:

   ```dcl
   $ LYNX -version
   ```

While you are there, confirm the file protections let non-privileged users in:

```dcl
$ DIRECTORY/PROTECTION SYS$SYSTEM:LYNX.EXE, SYS$COMMON:[000000]LYNX.DIR, -
                       SYS$COMMON:[LYNX]LYNX.CFG, SYS$MANAGER:LYNX$STARTUP.COM
```

All four want `W:RE`. The current `KITINSTAL.COM` sets that; fix any that are
short with `SET PROTECTION=(S:RWED,O:RWED,G:RE,W:RE)`.

### Verified

Installed and tested on GOZER (real MicroVAX, OpenVMS VAX V7.3) on 29 Aug 2026.

The multi-user behaviour was checked from an account that could not possibly
have inherited anything from the installing session: `ABLACK`, UIC `[200,20]`,
authorised privileges `NETMBX` and `TMPMBX` only. The job was run with
`SUBMIT/USER=ABLACK`, so it executed `SYLOGIN.COM` exactly as a real login does,
under that account's UIC and privileges — and needed no password.

```
===== RENDER TEST AS ABLACK =====
Privs: TMPMBX,NETMBX
Lynx_Dir: SYS$COMMON:[LYNX]

                              Lynx multi-user test
   If an unprivileged account rendered this, the kit is installed
   correctly.
  status = %X00000001
```

Both branches of `LYNX$STARTUP.COM` were exercised:

| Branch | How | Result |
|---|---|---|
| Privileged | `@SYS$MANAGER:LYNX$STARTUP` as SYSTEM | `LYNX_DIR` appears in `LNM$SYSTEM_TABLE`; `LYNX` symbol defined |
| Unprivileged fallback | `DEASSIGN/SYSTEM LYNX_DIR`, then the batch job as ABLACK | process logical defined instead; Lynx still rendered, status `%X00000001` |

The earlier state, for contrast: before reinstalling, `SHOW LOGICAL/SYSTEM
LYNX_DIR` on the same machine returned `%SHOW-S-NOTRAN, no translation for
logical name LYNX_DIR`. That is the whole bug in one line.

Not re-tested in this pass: `http:` fetching (the fix in the C source is
unchanged and was verified in an earlier session) and the boot-time
`SYSTARTUP_VMS.COM` path, which cannot be confirmed without a reboot — the line
is in place and the identical command was proven to work when run by hand.

### Per-user bookmarks, and bookmarks as the start page

Each user gets their own bookmark file with **no configuration at all**. Lynx
resolves `DEFAULT_BOOKMARK_FILE` against the home directory, which on VMS is
`SYS$LOGIN`, so the built-in default already lands at
`SYS$LOGIN:lynx_bookmarks.html` per user.

The rule that matters: **`DEFAULT_BOOKMARK_FILE` must be a bare filename.**

```
DEFAULT_BOOKMARK_FILE:lynx_bookmarks.html      <- per user, correct
DEFAULT_BOOKMARK_FILE:SYS$LOGIN:lynx_bookmarks.html   <- wrong, path is prepended
BOOKMARK_FILE:anything                         <- not a keyword at all, ignored
```

`BOOKMARK_FILE` is worth calling out: it is **not** a `lynx.cfg` setting. Only
`DEFAULT_BOOKMARK_FILE` exists, so a `BOOKMARK_FILE:` line is read and discarded
without any complaint.

To make each user's own bookmarks their start page, `LYNX$STARTUP.COM` defines
`WWW_HOME` at login pointing at that user's file. Lynx's startfile precedence is

```
command line  >  WWW_HOME  >  STARTFILE in lynx.cfg
```

so bookmarks become the default page while `LYNX http://something/` still goes
where it was told. The procedure defines `WWW_HOME` only once the file exists —
aiming the startfile at a missing file makes Lynx quit with `Can't access
startfile` — so a user with no bookmarks yet simply gets `STARTFILE`.

**Do not use `lynx -book` for this.** It looks like the obvious answer, and it
does use the bookmark page, but it *also* overrides a URL given on the command
line: with `-book` in the `LYNX` symbol, `LYNX http://example.com/` silently
opens bookmarks instead. Verified on GOZER. `-book` remains fine to type by hand.

### The shipped start page, and the two lynx.cfg changes

`lynx.cfg` in this tree is the stock 2.9.3 file with exactly two settings
changed, both because of VMS:

```
#STARTFILE:https://lynx.invisible-island.net/          <- upstream default
STARTFILE:file://localhost/Lynx_Dir:lynxstart.html     <- ours
DEFAULT_BOOKMARK_FILE:lynx_bookmarks.html              <- ours (was commented)
```

The upstream default start page is an **https:** URL, and this build has no SSL,
so out of the box every user's first experience would be a failed page load. The
kit installs a small local `LYNXSTART.HTML` beside `lynx.cfg` and points
`STARTFILE` at it — it needs no network at all, and explains bookmarks and the
main keys.

`Lynx_Dir:` is used deliberately rather than a hard path. A logical name works
inside a `file:` URL (tested), so the setting stays correct no matter where the
kit was installed.

Re-installing never overwrites a `lynx.cfg` you have customised — you get
`LYNX.CFG-NEW` beside it — so these defaults only apply to a fresh install.

### `Can't Access` on a start page: check the protection first

```
Can't Access `file://localhost/sys$common:[lynx]bookmarks.html'
Alert!: Unable to access document.
lynx: Can't access startfile
```

The usual cause is **file protection, not URL syntax**. A page in
`SYS$COMMON:[LYNX]` that every user is meant to open must be `World:RE`; files
put there by hand often end up `(RWED,RWED,RE,)` with no world access, and only
the owner can read them.

```dcl
$ DIRECTORY/PROTECTION SYS$COMMON:[LYNX]
$ SET PROTECTION=(S:RWED,O:RWED,G:RE,W:RE) SYS$COMMON:[LYNX]BOOKMARKS.HTML
```

Confirmed by direct comparison on GOZER: two files in that directory, same URL
form, both present — the `World:RE` one rendered for an unprivileged account and
the `World:` one produced exactly the message above.

On URL syntax, for reference — tested, all as an unprivileged user:

| Form | Works |
|---|---|
| `file://localhost/DKA0:[DIR]FILE.HTML` | yes |
| `file://localhost/SYS$LOGIN:FILE.HTML` | yes — logical names are fine |
| `file://localhost/SYS$COMMON:[LYNX]FILE.HTML` | yes — rooted logicals too |
| `file://localhost/~/FILE.HTML` | **no** — expands to a doubled slash |

### What gets installed where

| File | Destination | Why |
|---|---|---|
| `LYNX.EXE` | `SYS$SYSTEM:` | the browser |
| `LYNX.CFG` | `SYS$COMMON:[LYNX]` | global configuration; `Lynx_Dir` points here |
| `LYNXSTART.HTML` | `SYS$COMMON:[LYNX]` | default start page; `STARTFILE` points here |
| `LYNX.HLP` | `SYS$HELP:` | VMS-format help text |
| `LYNX$STARTUP.COM` | `SYS$MANAGER:` | defines the `LYNX` command per-process and `Lynx_Dir` system-wide |

`LYNX$STARTUP.COM` does two things, and **both matter**:

```dcl
$ DEFINE/SYSTEM/NOLOG Lynx_Dir SYS$COMMON:[LYNX]   ! when the caller has SYSNAM
$ LYNX == "$SYS$SYSTEM:LYNX.EXE"
```

Without `Lynx_Dir`, Lynx exits immediately with

```
Configuration file "Lynx_Dir:lynx.cfg" is not available.
```

That is fatal, not a warning (`LYMain.c:1548` calls `exit_immediately`).

The procedure defines `Lynx_Dir` in the **system** table when the caller holds
`SYSNAM` (i.e. at boot from `SYSTARTUP_VMS.COM`), and falls back to a process
logical for an unprivileged caller so an ordinary user is not left broken if the
system-wide definition is missing. It also copes with VMSINSTAL having placed
the directory in `SYS$SPECIFIC:[LYNX]` instead of `SYS$COMMON:[LYNX]`, and
defines the `LYNX` symbol only if `SYS$SYSTEM:LYNX.EXE` is actually there.
`SET NOON` at the top means a failure can never break `SYLOGIN.COM` for the
whole system.

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

Rebuilding is also how the current `KITINSTAL.COM` and `LYNX$STARTUP.COM` — the
ones that set Lynx up for all users — get into the save set. The committed
`LYNX293.A` was built before them.

Four details in `MAKE_KIT.COM` are not optional. The last two were added after a
rebuild on 29 Aug 2026 tripped over both:

- **`/BLOCK_SIZE=2048`.** BACKUP's disk default (32256) makes VMSINSTAL misframe
  the save set; it fails at restore with `INVBLKSIZE` or CRC errors.
- **Inputs are flat, by bare name.** VMSINSTAL restores save set A into `VMI$KWD:`
  with no subdirectories, and `KITINSTAL.COM` copies from there by bare name.
- **`;0` on every BACKUP input.** BACKUP defaults to *all versions*. The first
  rebuild shipped `KITINSTAL.COM;2` **and** `;1`, so VMSINSTAL would restore two
  of each control file. `;0` means "latest version only".
- **The size guard.** `COPY [-]LYNX.CFG` takes the *highest version* in the
  parent, and a tree used for testing readily has a hand-made three-line
  `LYNX.CFG` sitting on top of the real 320-block one. `MAKE_KIT.COM` now prints
  the block counts it picked up and refuses to build if `LYNX.EXE` is under 1000
  blocks, `LYNX.CFG` under 100, or `LYNX.HLP` under 50.

`KITINSTAL.COM` uses plain `COPY`, not the `VMI$CALLBACK PROVIDE_IMAGE` /
`PROVIDE_FILE` callbacks, which are unreliable across VMS versions.

No `*.RELEASE_NOTES` file is shipped inside the save set — VMSINSTAL auto-detects
one, moves it, then its deferred cleanup tries `[SYSHLP]*.RELEASE_NOTES` again and
dies with `%RMS-F-WLD`. Release notes ship as `RELEASE_NOTES.TXT` instead.

### Files here

| File | Role |
|---|---|
| `KITINSTAL.COM` | the install procedure; must be in save set A |
| `LYNX$STARTUP.COM` | goes to `SYS$MANAGER:`; call it from **both** `SYSTARTUP_VMS.COM` and `SYLOGIN.COM` |
| `MAKE_KIT.COM` | builds `LYNX293.A` |
| `LYNXSTART.HTML` | the default start page, installed beside `lynx.cfg` |
| `LYNXWIRE.COM` | adds a line to `SYLOGIN.COM` / `SYSTARTUP_VMS.COM` safely; not in the save set |
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
