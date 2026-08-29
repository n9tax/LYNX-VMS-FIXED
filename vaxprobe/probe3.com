$ v = 'f$verify(0)
$!	PROBE3.COM -- find where Lynx's HTTP path dies on OpenVMS VAX.
$!
$!	Put PROBE3.C in the same directory and run:
$!	    $ @PROBE3
$!	    $ @PROBE3 188.184.67.127        ! or any reachable IP
$!
$!	Builds the same probe TWO ways -- the way the current LYNX.EXE was
$!	built (branch A: no /PREFIX=ALL, shareable VAXCRTL) and the way
$!	build.com's DECC branch would build it (branch B: /PREFIX=ALL,
$!	VAXCRTL object library) -- then runs each one twice, with and
$!	without the FIONBIO ioctl.
$!
$!	Four runs, about a minute.  Read the LAST line each one prints.
$!
$!	The linker only accepts /SHARE and /LIBRARY as input-file
$!	qualifiers inside an options file, which is why build.com uses
$!	.OPT files and why this procedure writes two of them.  Putting
$!	them on the LINK command line makes LINK read /SHARE as the
$!	output qualifier and go looking for UCX$IPC_SHR.OBJ.
$!
$ on error then continue
$ target = p1
$ if target .eqs. "" then target = "188.184.67.127"
$!
$!	Compile qualifiers.  /warning=(disable=implicitfunc) mirrors what
$!	libmake.com's DECC branch does -- read/write/close are implicitly
$!	declared in the real Lynx build too, because HTUtils.h line 71
$!	sets NO_UNISTD_H on VMS.  The informationals are expected.
$!
$ warn = "/warning=(disable=implicitfunc)"
$!
$ write sys$output ""
$ write sys$output "############ target = ''target' port 80"
$!
$!	Which socket shareable image is actually on this system?
$!	build.com's UCXSHR.OPT hardwires UCX$IPC_SHR; TCP/IP Services
$!	installs TCPIP$IPC_SHR and usually a UCX$ compatibility name.
$!	Use whichever is really there, and say which.
$!
$ netimg = "sys$share:ucx$ipc_shr"
$ if f$search("sys$share:ucx$ipc_shr.exe") .eqs. "" then netimg = "sys$share:tcpip$ipc_shr"
$ write sys$output ""
$ write sys$output "---- socket shareable image in use: ''netimg'"
$ if f$search("''netimg'.exe") .eqs. "" then write sys$output "**** NEITHER UCX$IPC_SHR.EXE NOR TCPIP$IPC_SHR.EXE FOUND IN SYS$SHARE"
$!
$!	Write the two options files.
$!
$ open/write opt probe3a.opt
$ write opt "''netimg'/share"
$ write opt "sys$share:vaxcrtl/share"
$ close opt
$!
$ open/write opt probe3b.opt
$ write opt "''netimg'/share"
$ write opt "sys$library:vaxcrtl/library"
$ close opt
$!
$!	Branch A -- mirrors build.com's ELSE branch (what you have now)
$!
$ write sys$output ""
$ write sys$output "############ A: compile WITHOUT /decc/prefix=all"
$ write sys$output "############    link  sys$share:vaxcrtl/share   (VAXC.OPT)"
$ if f$search("probe3.obj")  .nes. "" then delete/nolog probe3.obj;*
$ if f$search("probe3a.exe") .nes. "" then delete/nolog probe3a.exe;*
$ cc/accept=novaxc_keywords'warn' probe3.c
$ if .not. $status then goto skip_a
$ link/exe=probe3a.exe probe3.obj, sys$disk:[]probe3a.opt/opt
$ if .not. $status then goto skip_a
$ if f$search("probe3a.exe") .eqs. "" then goto skip_a
$ probe3a :== $sys$disk:[]probe3a.exe
$ write sys$output ""
$ write sys$output "---- A1: with ioctl (this is what Lynx does today)"
$ probe3a 'target' IOCTL
$ write sys$output ""
$ write sys$output "---- A2: without ioctl (blocking connect)"
$ probe3a 'target' NOIOCTL
$ goto do_b
$ skip_a:
$ write sys$output "**** branch A did not build -- see the errors above"
$!
$ do_b:
$!
$!	Branch B -- mirrors build.com's DECC branch
$!
$ write sys$output ""
$ write sys$output "############ B: compile WITH /decc/prefix=all/nomember"
$ write sys$output "############    link  sys$library:vaxcrtl/library  (DECC.OPT)"
$ if f$search("probe3.obj")  .nes. "" then delete/nolog probe3.obj;*
$ if f$search("probe3b.exe") .nes. "" then delete/nolog probe3b.exe;*
$ cc/decc/prefix=all/nomember/accept=novaxc_keywords'warn' probe3.c
$ if .not. $status then goto skip_b
$ link/exe=probe3b.exe probe3.obj, sys$disk:[]probe3b.opt/opt
$ if .not. $status then goto skip_b
$ if f$search("probe3b.exe") .eqs. "" then goto skip_b
$ probe3b :== $sys$disk:[]probe3b.exe
$ write sys$output ""
$ write sys$output "---- B1: with ioctl"
$ probe3b 'target' IOCTL
$ write sys$output ""
$ write sys$output "---- B2: without ioctl"
$ probe3b 'target' NOIOCTL
$ goto summary
$ skip_b:
$ write sys$output "**** branch B did not build -- see the errors above"
$!
$ summary:
$ write sys$output ""
$ write sys$output "############ how to read this"
$ write sys$output "  All four print HTTP headers  -> the bug is NOT in the socket"
$ write sys$output "                                  path; look higher in Lynx."
$ write sys$output "  A* crash, B* work            -> compiler branch / RTL is it."
$ write sys$output "                                  Rebuild via the DECC branch."
$ write sys$output "  *1 crash, *2 work            -> HTioctl/FIONBIO is it."
$ write sys$output "                                  Rebuild with NO_IOCTL defined."
$ write sys$output "  All four crash               -> UCX itself.  Check PING/TELNET."
$ write sys$output ""
$ v = 'f$verify(v)
