$ ! LYNXWIRE.COM -- add a line to a DCL procedure, immediately after the first
$ ! record containing a marker string.
$ !
$ !     @LYNXWIRE "file" "marker" "line to add" ["protection"]
$ !
$ ! Writes a NEW VERSION, so the previous one remains as the backup, and stamps
$ ! the protection explicitly.  That last part is not cosmetic: a SYLOGIN.COM
$ ! created without World:RE locks every non-privileged user out at login.
$ !
$ on error then goto fail
$ if p1 .eqs. "" then goto usage
$ if p2 .eqs. "" then goto usage
$ if p3 .eqs. "" then goto usage
$ prot = p4
$ if prot .eqs. "" then prot = "(S:RWED,O:RWED,G:RWED,W:RE)"
$ !
$ src = f$search(p1)
$ if src .eqs. "" then goto nofile
$ write sys$output "Source:  ''src'"
$ !
$ open/read  fin  'src'
$ open/write fout 'p1'
$ n = 0
$ hit = 0
$ loop:
$ read/end_of_file=eof fin rec
$ write fout rec
$ n = n + 1
$ if hit .eq. 1 then goto loop
$ if f$locate(p2,rec) .eq. f$length(rec) then goto loop
$ write fout p3
$ hit = n
$ goto loop
$ eof:
$ close fin
$ close fout
$ if hit .eq. 0 then goto nomarker
$ set protection='prot' 'p1'
$ write sys$output "Copied ''n' records; inserted after record ''hit'."
$ write sys$output "New version:  ''f$search(p1)'"
$ exit
$ !
$ nomarker:
$ write sys$output "*** Marker ""''p2'"" not found -- nothing inserted."
$ write sys$output "*** Deleting the useless new version."
$ delete 'p1';
$ exit 2
$ nofile:
$ write sys$output "*** No such file: ''p1'"
$ exit 2
$ usage:
$ write sys$output "Usage:  @LYNXWIRE ""file"" ""marker"" ""line"" [""prot""]"
$ exit 2
$ fail:
$ status = $status
$ set noon
$ close fin
$ close fout
$ write sys$output "*** LYNXWIRE FAILED (''status')"
$ exit 'status'
