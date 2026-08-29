$ ! KITINSTAL.COM  -  VMSINSTAL install procedure for Lynx V2.9-3
$ ! Invoked by:  @SYS$UPDATE:VMSINSTAL LYNX293 device:[dir]
$ !
$ IF P1 .EQS. "VMI$_INSTALL" THEN GOTO INSTALL
$ EXIT VMI$_UNSUPPORTED
$ !
$ INSTALL:
$ ! VMSINSTAL already restored save set A into VMI$KWD; just copy the files.
$ ! Everything is world read+execute so that ordinary users, not just the
$ ! account running the install, can read the config and run the image.
$ !
$ ! The browser image.
$ COPY/PROTECTION=(S:RWED,O:RWED,G:RE,W:RE) -
      VMI$KWD:LYNX.EXE           VMI$ROOT:[SYSEXE]LYNX.EXE
$ !
$ ! Lynx_Dir holds lynx.cfg and friends.  Create it if this is a first install.
$ IF F$SEARCH("VMI$ROOT:[000000]LYNX.DIR") .NES. "" THEN GOTO HAVEDIR
$ CREATE/DIRECTORY VMI$ROOT:[LYNX]/PROTECTION=(S:RWED,O:RWED,G:RE,W:RE)
$ HAVEDIR:
$ ! Repair the protection on a directory left over from an older install that
$ ! created it without world access.  Not fatal if it fails.
$ SET NOON
$ SET PROTECTION=(S:RWED,O:RWED,G:RE,W:RE) VMI$ROOT:[000000]LYNX.DIR
$ SET ON
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
$ ! The default start page, beside lynx.cfg.  World:RE matters -- STARTFILE
$ ! points here, and a page users cannot read gives "Can't access startfile".
$ ! Replaced on every install: it is ours, not a file anyone customises.
$ COPY/PROTECTION=(S:RWED,O:RWED,G:RE,W:RE) -
      VMI$KWD:LYNXSTART.HTML     VMI$ROOT:[LYNX]LYNXSTART.HTML
$ !
$ ! VMS help text.
$ COPY/PROTECTION=(S:RWED,O:RWED,G:RE,W:RE) -
      VMI$KWD:LYNX.HLP           VMI$ROOT:[SYSHLP]LYNX.HLP
$ !
$ ! Command / logical name definitions.  SYLOGIN.COM runs this in each user's
$ ! own process, so it must be world executable.
$ COPY/PROTECTION=(S:RWED,O:RWED,G:RE,W:RE) -
      VMI$KWD:LYNX$STARTUP.COM   VMI$ROOT:[SYSMGR]LYNX$STARTUP.COM
$ !
$ ! Report where the config actually landed, rather than assuming SYS$COMMON.
$ CFGWHERE = "SYS$COMMON:[LYNX]"
$ IF F$SEARCH("SYS$COMMON:[000000]LYNX.DIR") .NES. "" THEN GOTO SAYIT
$ IF F$SEARCH("SYS$SPECIFIC:[000000]LYNX.DIR") .EQS. "" THEN GOTO SAYIT
$ CFGWHERE = "SYS$SPECIFIC:[LYNX]"
$ SAYIT:
$ !
$ ! Define Lynx_Dir system-wide now so Lynx works before the next reboot.
$ ! (VMSINSTAL runs privileged; the definition lasts until the node reboots,
$ !  which is why SYSTARTUP_VMS.COM must call the startup procedure too.)
$ SET NOON
$ IF F$PRIVILEGE("SYSNAM") THEN DEFINE/SYSTEM/NOLOG Lynx_Dir 'CFGWHERE'
$ SET ON
$ !
$ WRITE SYS$OUTPUT ""
$ WRITE SYS$OUTPUT "  Lynx V2.9-3 installed in SYS$SYSTEM:."
$ WRITE SYS$OUTPUT "  Configuration:  ''CFGWHERE'LYNX.CFG"
$ WRITE SYS$OUTPUT ""
$ WRITE SYS$OUTPUT "  TO MAKE LYNX AVAILABLE TO ALL USERS, add ONE line to EACH"
$ WRITE SYS$OUTPUT "  of these two files -- both are required:"
$ WRITE SYS$OUTPUT ""
$ WRITE SYS$OUTPUT "    SYS$MANAGER:SYSTARTUP_VMS.COM   $ @SYS$MANAGER:LYNX$STARTUP"
$ WRITE SYS$OUTPUT "        defines the Lynx_Dir logical system-wide at boot."
$ WRITE SYS$OUTPUT ""
$ WRITE SYS$OUTPUT "    SYS$MANAGER:SYLOGIN.COM         $ @SYS$MANAGER:LYNX$STARTUP"
$ WRITE SYS$OUTPUT "        defines the LYNX command.  DCL symbols are per-process"
$ WRITE SYS$OUTPUT "        and cannot be made system-wide, so every login needs it."
$ WRITE SYS$OUTPUT ""
$ WRITE SYS$OUTPUT "  Lynx_Dir has been defined system-wide for this boot already,"
$ WRITE SYS$OUTPUT "  so you can test right now:"
$ WRITE SYS$OUTPUT ""
$ WRITE SYS$OUTPUT "      $ @SYS$MANAGER:LYNX$STARTUP"
$ WRITE SYS$OUTPUT "      $ LYNX -version"
$ WRITE SYS$OUTPUT ""
$ WRITE SYS$OUTPUT "  To add Lynx to the system help library:"
$ WRITE SYS$OUTPUT "      $ LIBRARY/REPLACE SYS$HELP:HELPLIB.HLB SYS$HELP:LYNX.HLP"
$ WRITE SYS$OUTPUT ""
$ EXIT VMI$_SUCCESS
