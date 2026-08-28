$ v = 'f$verify(0)
$!	PROBE.COM -- settle the Lynx/VMS compiler-flag question.
$!	Put PROBE.C in the same directory and run:  @PROBE
$!
$ on error then continue
$ define/nolog decc$cc_default "/DECC"
$ write sys$output ""
$ write sys$output "=== A: default (relaxed) -- expect this one to FAIL ==="
$ cc/decc/prefix=all/nomember probe.c
$ write sys$output "   status = ''$status'"
$!
$ write sys$output ""
$ write sys$output "=== B: /ACCEPT=NOVAXC_KEYWORDS  (recommended) ==="
$ cc/decc/prefix=all/nomember/accept=novaxc_keywords probe.c
$ write sys$output "   status = ''$status'"
$ if $status then link/exe=probeb.exe probe.obj,sys$disk:[]decc.opt/opt
$ if f$search("probeb.exe") .nes. "" then run probeb.exe
$!
$ write sys$output ""
$ write sys$output "=== C: /STANDARD=ANSI89 (fallback) ==="
$ cc/decc/prefix=all/nomember/standard=ansi89 -
     /warning=(disable=dollarid) -
     /define=(VMS=1) probe.c
$ write sys$output "   status = ''$status'"
$ if $status then link/exe=probec.exe probe.obj,sys$disk:[]decc.opt/opt
$ if f$search("probec.exe") .nes. "" then run probec.exe
$!
$ write sys$output ""
$ write sys$output "=== done.  B should compile silently and print 3 OK lines."
$ write sys$output "=== If C emits %CC-W-IMPLICITFUNC on getcwd/getpid/unlink,"
$ write sys$output "=== strict ANSI89 has hidden the VMS headers -- use B."
$ v = 'f$verify(v)
