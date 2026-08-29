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
$ copy [-]LYNX.EXE LYNX.EXE
$ copy [-]LYNX.CFG LYNX.CFG
$ copy [-]LYNX.HLP LYNX.HLP
$ !
$ if f$search("KITINSTAL.COM")     .eqs. "" then goto nocontrol
$ if f$search("LYNX$STARTUP.COM")  .eqs. "" then goto nocontrol
$ !
$ if f$search("''kit'.A") .nes. "" then delete 'kit'.A;*
$ write sys$output "Building saveset ''kit'.A ..."
$ backup KITINSTAL.COM,LYNX$STARTUP.COM,LYNX.EXE,LYNX.CFG,LYNX.HLP -
      'kit'.A/SAVE_SET/BLOCK_SIZE=2048/LOG
$ !
$ delete LYNX.EXE;*               ! remove the flat copies; keep the save set
$ delete LYNX.CFG;*
$ delete LYNX.HLP;*
$ write sys$output "Kit built:  ''f$environment("DEFAULT")'''kit'.A"
$ write sys$output "Install:  $ @SYS$UPDATE:VMSINSTAL ''kit' ''f$environment("DEFAULT")'"
$ exit
$ noimages:  $ write sys$output "*** Build the images first: SET DEFAULT [-] then @BUILD ***"
$            $ exit
$ nocontrol: $ write sys$output "*** KITINSTAL.COM / LYNX$STARTUP.COM missing here ***"
$            $ exit
$ fail:      $ write sys$output "*** KIT BUILD FAILED (''$status') ***"
$            $ exit $status
