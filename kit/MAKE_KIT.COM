$ on error then goto fail
$ kit = "LYNX293"
$ !
$ ! MAKE_KIT.COM -- build the Lynx VMSINSTAL save set.
$ ! Run from the [.KIT] subdirectory of the Lynx tree, after @BUILD.
$ !
$ ! Bring the freshly-built image and config in flat, so the save set holds
$ ! them by bare name (VMSINSTAL restores into VMI$KWD with no subdirs).
$ !
$ if f$search("[-]LYNX.EXE") .eqs. "" then goto noimages
$ ! Control files live here, not in the parent, and all must be present.
$ if f$search("KITINSTAL.COM")    .eqs. "" then goto nocontrol
$ if f$search("LYNX$STARTUP.COM") .eqs. "" then goto nocontrol
$ if f$search("LYNXSTART.HTML")   .eqs. "" then goto nocontrol
$ if f$search("BOOKSKEL.HTML")    .eqs. "" then goto nocontrol
$ if f$search("BOOKSKEL.FDL")     .eqs. "" then goto nocontrol
$ copy [-]LYNX.EXE LYNX.EXE
$ copy [-]LYNX.CFG LYNX.CFG
$ copy [-]LYNX.HLP LYNX.HLP
$ !
$ ! The per-user bookmark skeleton MUST ship as Stream_LF.  Lynx appends to a
$ ! bookmark file by reopening it "a+", rewinding and re-reading it; on a
$ ! variable-length record file that read yields nothing, so Lynx decides the
$ ! file is empty and writes a second copy of the whole header.  DCL CREATE and
$ ! COPY both produce variable-record files, so convert here rather than trust
$ ! however BOOKSKEL.HTML arrived on this machine.
$ if f$search("LYNXBOOK.HTML") .nes. "" then delete LYNXBOOK.HTML;*
$ convert/fdl=BOOKSKEL.FDL BOOKSKEL.HTML LYNXBOOK.HTML
$ !
$ ! Sanity-check what we just picked up.  COPY takes the HIGHEST VERSION in the
$ ! parent directory, and a tree that has been used for testing can easily have
$ ! a small hand-made LYNX.CFG sitting on top of the real 320-block one -- ship
$ ! that by accident and every installation gets a three-line config.
$ exe_blocks = f$file_attributes("LYNX.EXE","EOF")
$ cfg_blocks = f$file_attributes("LYNX.CFG","EOF")
$ hlp_blocks = f$file_attributes("LYNX.HLP","EOF")
$ write sys$output "Picked up:  LYNX.EXE ''exe_blocks' blocks"
$ write sys$output "            LYNX.CFG ''cfg_blocks' blocks"
$ write sys$output "            LYNX.HLP ''hlp_blocks' blocks"
$ if exe_blocks .lt. 1000 then goto badexe
$ if cfg_blocks .lt. 100  then goto badcfg
$ if hlp_blocks .lt. 50   then goto badhlp
$ !
$ if f$search("''kit'.A") .nes. "" then delete 'kit'.A;*
$ write sys$output "Building saveset ''kit'.A ..."
$ ! ";0" means "latest version only".  Without it BACKUP takes EVERY version,
$ ! so a second build ships two KITINSTAL.COMs and VMSINSTAL restores both.
$ backup KITINSTAL.COM;0,LYNX$STARTUP.COM;0,LYNXSTART.HTML;0,LYNXBOOK.HTML;0, -
      LYNX.EXE;0,LYNX.CFG;0,LYNX.HLP;0 -
      'kit'.A/SAVE_SET/BLOCK_SIZE=2048/LOG
$ !
$ delete LYNX.EXE;*               ! remove the flat copies; keep the save set
$ delete LYNX.CFG;*
$ delete LYNX.HLP;*
$ delete LYNXBOOK.HTML;*         ! the converted copy; BOOKSKEL.HTML is the source
$ write sys$output "Kit built:  ''f$environment("DEFAULT")'''kit'.A"
$ write sys$output "Install:  $ @SYS$UPDATE:VMSINSTAL ''kit' ''f$environment("DEFAULT")'"
$ exit
$ noimages:  $ write sys$output "*** Build the images first: SET DEFAULT [-] then @BUILD ***"
$            $ exit
$ nocontrol: $ write sys$output "*** A control file is missing from this directory."
$            $ write sys$output "*** Need KITINSTAL.COM, LYNX$STARTUP.COM, LYNXSTART.HTML,"
$            $ write sys$output "*** BOOKSKEL.HTML and BOOKSKEL.FDL."
$            $ exit
$ badexe:    $ write sys$output "*** LYNX.EXE is only ''exe_blocks' blocks -- expected ~2600."
$            $ write sys$output "*** The build in [-] looks incomplete.  Not shipping it."
$            $ goto cleanup
$ badcfg:    $ write sys$output "*** LYNX.CFG is only ''cfg_blocks' blocks -- expected ~320."
$            $ write sys$output "*** [-]LYNX.CFG is probably a hand-made test config sitting"
$            $ write sys$output "*** on top of the real one.  Check DIRECTORY [-]LYNX.CFG;*"
$            $ write sys$output "*** and COPY the good version up so it is the highest."
$            $ goto cleanup
$ badhlp:    $ write sys$output "*** LYNX.HLP is only ''hlp_blocks' blocks -- expected ~109."
$            $ goto cleanup
$ cleanup:   $ set noon
$            $ if f$search("LYNX.EXE") .nes. "" then delete LYNX.EXE;*
$            $ if f$search("LYNX.CFG") .nes. "" then delete LYNX.CFG;*
$            $ if f$search("LYNX.HLP") .nes. "" then delete LYNX.HLP;*
$            $ if f$search("LYNXBOOK.HTML") .nes. "" then delete LYNXBOOK.HTML;*
$            $ write sys$output "*** KIT NOT BUILT ***"
$            $ exit
$ fail:      $ write sys$output "*** KIT BUILD FAILED (''$status') ***"
$            $ exit $status
