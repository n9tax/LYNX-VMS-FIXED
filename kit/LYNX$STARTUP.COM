$ ! LYNX$STARTUP.COM  -  define the Lynx command and its configuration logical.
$ ! From SYS$MANAGER:SYLOGIN.COM (all users) or a personal LOGIN.COM:
$ !     $ @SYS$MANAGER:LYNX$STARTUP
$ !
$ ! Lynx_Dir is where Lynx looks for LYNX.CFG (see userdefs.h, LYNX_CFG_FILE).
$ ! Without it Lynx exits at once with "Configuration file is not available".
$ DEFINE/NOLOG Lynx_Dir SYS$COMMON:[LYNX]
$ !
$ LYNX == "$SYS$SYSTEM:LYNX.EXE"
