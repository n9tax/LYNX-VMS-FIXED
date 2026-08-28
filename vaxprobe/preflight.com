$ v = 'f$verify(0)
$!	PREFLIGHT.COM -- check everything BUILD.COM will need, before you
$!	spend hours finding out the hard way.  Run from the top of the tree.
$!
$ ok = 1
$!	Locate the top of the tree, whether we were run from there or
$!	from a subdirectory such as [.VAXPROBE].
$ if f$search("BUILD.COM") .eqs. ""
$ then
$   if f$search("[-]BUILD.COM") .nes. ""
$   then
$	set default [-]
$	write sys$output ""
$	write sys$output "  (moved up one level to the tree top)"
$   else
$	write sys$output ""
$	write sys$output "  *** BUILD.COM not found here or one level up."
$	write sys$output "  *** SET DEFAULT to the top of the Lynx tree first."
$	exit
$   endif
$ endif
$ write sys$output ""
$ write sys$output "Tree top:"
$ show default
$ write sys$output ""
$ write sys$output "---- 1. compiler selection -------------------------------"
$ show logical DECC$CC_DEFAULT
$ write sys$output "   (must translate to /DECC -- if not: $ DEFINE DECC$CC_DEFAULT ""/DECC"")"
$ write sys$output ""
$ write sys$output "---- 2. the four patched lines ---------------------------"
$ search BUILD.COM "cc_opts ="
$ search [.WWW.LIBRARY.VMS]LIBMAKE.COM "cc_opts ="
$ search [.SRC.CHRTRANS]BUILD-CHRTRANS.COM "CHRcc_opts ="
$ write sys$output "   (each assignment must show /ACCEPT=NOVAXC_KEYWORDS)"
$ write sys$output ""
$ write sys$output "---- 3. linker option files ------------------------------"
$ gosub chkfile_SRC
$ write sys$output ""
$ write sys$output "---- 4. what those .OPT files point at -------------------"
$ f = "SYS$SHARE:UCX$IPC_SHR.EXE"
$ gosub chk
$ f = "SYS$LIBRARY:VAXCRTL.OLB"
$ gosub chk
$ f = "SYS$LIBRARY:VAXCCURSE.OLB"
$ gosub chk
$ write sys$output ""
$ write sys$output "---- 5. UCX headers (needed when UCX is defined) ---------"
$ f = "SYS$LIBRARY:UCX$INETDEF.H"
$ gosub chk
$ f = "SYS$LIBRARY:NETDB.H"
$ gosub chk
$ write sys$output ""
$ write sys$output "---- 6. free space on this disk --------------------------"
$ fb = f$getdvi(f$parse("SYS$DISK:",,,"DEVICE"),"FREEBLOCKS")
$ write sys$output "   free blocks = ''fb'   (want well over 100000)"
$ if fb .lt. 100000 then write sys$output "   *** LOW -- the build needs room for ~90 .OBJ + .OLB"
$ write sys$output ""
$ if ok
$ then
$   write sys$output "PREFLIGHT: all checked items present."
$ else
$   write sys$output "PREFLIGHT: *** something above is MISSING -- fix before building."
$ endif
$ write sys$output ""
$ exit
$!
$ chk:
$   if f$search(f) .nes. ""
$   then
$	write sys$output "   OK       ''f'"
$   else
$	write sys$output "   MISSING  ''f'"
$	ok = 0
$   endif
$   return
$!
$ chkfile_SRC:
$   f = "[.SRC]DECC.OPT"
$   gosub chk
$   f = "[.SRC]UCXSHR.OPT"
$   gosub chk
$   return
