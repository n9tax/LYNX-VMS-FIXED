$ v = 'f$verify(0)
$!	PATCHVMS.COM -- apply the four Lynx compiler-flag edits in place.
$!	Run from the TOP of the Lynx tree (where BUILD.COM lives):  @PATCHVMS
$!	VMS versioning keeps your originals as the lower version numbers.
$!
$ q  = """"
$ mt = q + q
$ ka = q + "/ACCEPT=NOVAXC_KEYWORDS" + q
$ kd = q + "/ACCEPT=NOVAXC_KEYWORDS/DEBUG/NOOPT" + q
$ no = "@@nomatch@@"
$!
$ write sys$output ""
$ write sys$output "Patching Lynx VMS build procedures ..."
$!
$ f  = "BUILD.COM"
$ o1 = "$ cc_opts = " + mt
$ n1 = "$ cc_opts = " + ka
$ o2 = no
$ n2 = no
$ gosub patch
$!
$ f  = "[.WWW.LIBRARY.VMS]LIBMAKE.COM"
$ gosub patch
$!
$ f  = "[.SRC.CHRTRANS]BUILD-CHRTRANS.COM"
$ o1 = "$ CHRcc_opts = " + mt
$ n1 = "$      CHRcc_opts = " + ka
$ o2 = "$ CHRcc_opts = " + q + "/DEBUG/NOOPT" + q
$ n2 = "$      CHRcc_opts = " + kd
$ gosub patch
$!
$ write sys$output ""
$ write sys$output "Expect: BUILD 1, LIBMAKE 1, BUILD-CHRTRANS 2  (4 total)."
$ write sys$output ""
$ exit
$!
$ patch:
$   if f$search(f) .eqs. ""
$   then
$	write sys$output "  ''f' -- NOT FOUND, skipped"
$	return
$   endif
$   count = 0
$   open/read  inf 'f'
$   open/write outf 'f'
$ ploop:
$   read/end_of_file=pdone inf line
$   t = f$edit(line, "COMPRESS,TRIM")
$   if t .eqs. o1
$   then
$	line = n1
$	count = count + 1
$	write sys$output "    -> ''n1'"
$   endif
$   if t .eqs. o2
$   then
$	line = n2
$	count = count + 1
$	write sys$output "    -> ''n2'"
$   endif
$   write outf line
$   goto ploop
$ pdone:
$   close inf
$   close outf
$   write sys$output "  ''f' : ''count' line(s) changed"
$   return
