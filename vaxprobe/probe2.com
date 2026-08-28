$ v = 'f$verify(0)
$!	PROBE2.COM -- compile-only test of the DECC/UCX header chain.
$!	Copy PROBE2.C into [.WWW.LIBRARY.VMS] and run this from there.
$!	Uses exactly the defines/includes libmake.com will use.
$!
$ on error then continue
$ define/nolog decc$cc_default "/DECC"
$ write sys$output ""
$ write sys$output "=== compiling probe2 with libmake's real flags ==="
$ cc/decc/prefix=all/nomember/accept=novaxc_keywords -
     /DEFINE=(UCX,ACCESS_AUTH) -
     /INCLUDE=([-.Implementation],[---.src],[---.src.chrtrans],[---]) -
     probe2.c
$ st = $status
$ write sys$output "   status = ''st'"
$ write sys$output ""
$ if st
$ then
$   write sys$output "PROBE2: header chain is SOUND -- go ahead and build."
$ else
$   write sys$output "PROBE2: *** header problem -- capture the messages above."
$ endif
$ write sys$output ""
$ v = 'f$verify(v)
