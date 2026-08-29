$ ! KITINSTAL.COM  -  VMSINSTAL install procedure for Lynx V2.9-3
$ ! Invoked by:  @SYS$UPDATE:VMSINSTAL LYNX293 device:[dir]
$ !
$ IF P1 .EQS. "VMI$_INSTALL" THEN GOTO INSTALL
$ EXIT VMI$_UNSUPPORTED
$ !
$ INSTALL:
$ ! VMSINSTAL already restored save set A into VMI$KWD; just copy the files.
$ !
$ ! The browser image.
$ COPY/PROTECTION=(S:RWED,O:RWED,G:RE,W:RE) -
      VMI$KWD:LYNX.EXE           VMI$ROOT:[SYSEXE]LYNX.EXE
$ !
$ ! Lynx_Dir holds lynx.cfg and friends.  Create it if this is a first install.
$ IF F$SEARCH("VMI$ROOT:[000000]LYNX.DIR") .NES. "" THEN GOTO HAVEDIR
$ CREATE/DIRECTORY VMI$ROOT:[LYNX]/PROTECTION=(S:RWED,O:RWED,G:RE,W:RE)
$ HAVEDIR:
$ !
$ ! lynx.cfg is the global configuration.  Do not clobber a customised one.
$ IF F$SEARCH("VMI$ROOT:[LYNX]LYNX.CFG") .NES. "" THEN GOTO HAVECFG
$ COPY/PROTECTION=(S:RWED,O:RWED,G:RE,W:RE) -
      VMI$KWD:LYNX.CFG           VMI$ROOT:[LYNX]LYNX.CFG
$ GOTO CFGDONE
$ HAVECFG:
$ COPY/PROTECTION=(S:RWED,O:RWED,G:RE,W:RE) -
      VMI$KWD:LYNX.CFG           VMI$ROOT:[LYNX]LYNX.CFG-NEW
$ WRITE SYS$OUTPUT "  Kept your existing LYNX.CFG; new one is LYNX.CFG-NEW."
$ CFGDONE:
$ !
$ ! VMS help text.
$ COPY/PROTECTION=(S:RWED,O:RWED,G:RE,W:RE) -
      VMI$KWD:LYNX.HLP           VMI$ROOT:[SYSHLP]LYNX.HLP
$ !
$ ! Command / logical name definitions.
$ COPY/PROTECTION=(S:RWED,O:RWED,G:RE,W:RE) -
      VMI$KWD:LYNX$STARTUP.COM   VMI$ROOT:[SYSMGR]LYNX$STARTUP.COM
$ !
$ WRITE SYS$OUTPUT ""
$ WRITE SYS$OUTPUT "  Lynx V2.9-3 installed in SYS$SYSTEM:."
$ WRITE SYS$OUTPUT "  Configuration:  SYS$COMMON:[LYNX]LYNX.CFG"
$ WRITE SYS$OUTPUT ""
$ WRITE SYS$OUTPUT "  Enable the command with:  $ @SYS$MANAGER:LYNX$STARTUP"
$ WRITE SYS$OUTPUT "  (add that to SYS$MANAGER:SYLOGIN.COM for all users)."
$ WRITE SYS$OUTPUT ""
$ WRITE SYS$OUTPUT "  To add Lynx to the system help library:"
$ WRITE SYS$OUTPUT "      $ LIBRARY/REPLACE SYS$HELP:HELPLIB.HLB SYS$HELP:LYNX.HLP"
$ WRITE SYS$OUTPUT ""
$ EXIT VMI$_SUCCESS
