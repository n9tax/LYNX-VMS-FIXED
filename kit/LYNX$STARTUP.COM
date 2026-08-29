$ ! LYNX$STARTUP.COM  -  make Lynx usable on this system.
$ !
$ ! This procedure sets up two things, and they have DIFFERENT SCOPES.  Getting
$ ! that wrong is why an install can appear to work only for the account that
$ ! ran it:
$ !
$ !   Lynx_Dir   A LOGICAL NAME.  Lynx builds its config path from it
$ !              (userdefs.h: LYNX_CFG_FILE "Lynx_Dir:lynx.cfg").  Without it
$ !              Lynx exits at once with "Configuration file is not available".
$ !              Defined /SYSTEM below when the caller holds SYSNAM, so every
$ !              process on the node sees it.  Otherwise a process logical is
$ !              defined as a fallback, which lasts only for that process.
$ !
$ !   LYNX       A DCL SYMBOL.  Symbols are per-process and CANNOT be made
$ !              system-wide.  Every user's login must define it, so this
$ !              procedure has to run in every user's process.
$ !
$ ! Therefore install it in BOTH places:
$ !
$ !   SYS$MANAGER:SYSTARTUP_VMS.COM     $ @SYS$MANAGER:LYNX$STARTUP
$ !       (run at boot by a privileged process -> system-wide Lynx_Dir)
$ !
$ !   SYS$MANAGER:SYLOGIN.COM           $ @SYS$MANAGER:LYNX$STARTUP
$ !       (run at every login -> the LYNX symbol for every user)
$ !
$ ! Running it from both is correct and harmless; the second call sees the
$ ! system logical already defined and only adds the symbol.
$ !
$ SET NOON                       ! never break SYLOGIN.COM for anybody
$ !
$ ! ---- Where does LYNX.CFG live? -------------------------------------------
$ ! VMSINSTAL may have put it in the common root or the system-specific root.
$ LX_DIR = "SYS$COMMON:[LYNX]"
$ IF F$SEARCH("SYS$COMMON:[000000]LYNX.DIR") .NES. "" THEN GOTO GOT_DIR
$ IF F$SEARCH("SYS$SPECIFIC:[000000]LYNX.DIR") .EQS. "" THEN GOTO GOT_DIR
$ LX_DIR = "SYS$SPECIFIC:[LYNX]"
$ GOT_DIR:
$ !
$ ! ---- Lynx_Dir: system-wide if we are allowed, process-wide if not --------
$ IF F$TRNLNM("LYNX_DIR","LNM$SYSTEM_TABLE") .NES. "" THEN GOTO DO_SYMBOL
$ IF F$PRIVILEGE("SYSNAM") THEN GOTO SYSTEM_WIDE
$ ! Unprivileged caller: at least make Lynx work for this process.
$ IF F$TRNLNM("LYNX_DIR") .EQS. "" THEN DEFINE/NOLOG Lynx_Dir 'LX_DIR'
$ GOTO DO_SYMBOL
$ SYSTEM_WIDE:
$ DEFINE/SYSTEM/NOLOG Lynx_Dir 'LX_DIR'
$ !
$ ! ---- The LYNX command: per-process, so every user needs this -------------
$ DO_SYMBOL:
$ IF F$SEARCH("SYS$SYSTEM:LYNX.EXE") .EQS. "" THEN GOTO DONE
$ LYNX == "$SYS$SYSTEM:LYNX.EXE"
$ !
$ ! ---- Personal start page: the user's own bookmark file -------------------
$ ! lynx.cfg sets DEFAULT_BOOKMARK_FILE to a BARE FILENAME, so Lynx resolves it
$ ! against the home directory -- SYS$LOGIN on VMS -- and every user gets their
$ ! own bookmark file with no per-user setup at all.  An absolute path there
$ ! would instead give the whole system one shared bookmark file.
$ !
$ ! Lynx's startfile precedence is:
$ !         command line  >  WWW_HOME  >  STARTFILE in lynx.cfg
$ ! so defining WWW_HOME makes a user's own bookmarks their start page, while
$ ! "LYNX http://something/" still goes where it was told.  Verified on GOZER.
$ !
$ ! Do NOT use "LYNX -book" for this.  -book ALSO overrides a URL given on the
$ ! command line, so putting it in the symbol above would break "LYNX <url>".
$ !
$ ! Only define WWW_HOME once the file exists: pointing the startfile at a
$ ! missing file makes Lynx quit with "Can't access startfile".  Until the user
$ ! adds their first bookmark they simply get the STARTFILE from lynx.cfg.
$ !
$ ! Keep BM_FILE in step with DEFAULT_BOOKMARK_FILE in lynx.cfg.
$ BM_FILE = "LYNX_BOOKMARKS.HTML"
$ IF F$TRNLNM("WWW_HOME") .NES. "" THEN GOTO DONE      ! user set their own
$ !
$ ! Give a new user an empty bookmark file, so WWW_HOME can point at it from
$ ! the very first login.  Without this the start page only switches to the
$ ! user's bookmarks at their NEXT login after adding the first one, because
$ ! this procedure runs before the file exists.
$ !
$ ! It MUST be copied from the shipped skeleton, not created here with CREATE
$ ! or OPEN/WRITE.  Those produce a variable-length record file, and Lynx
$ ! cannot append to one: adding a bookmark reopens the file "a+", rewinds and
$ ! re-reads it, that read yields nothing on a variable-record file, so Lynx
$ ! concludes the file is empty and writes a SECOND copy of the whole header.
$ ! The shipped skeleton is Stream_LF, which is what Lynx itself writes, and
$ ! COPY preserves the record format.  Verified both ways on GOZER.
$ IF F$SEARCH("SYS$LOGIN:''BM_FILE'") .NES. "" THEN GOTO HAVE_BM
$ IF F$SEARCH("LYNX_DIR:LYNXBOOK.HTML") .EQS. "" THEN GOTO DONE
$ COPY LYNX_DIR:LYNXBOOK.HTML SYS$LOGIN:'BM_FILE'
$ IF F$SEARCH("SYS$LOGIN:''BM_FILE'") .EQS. "" THEN GOTO DONE
$ HAVE_BM:
$ ! A logical name works fine inside a file: URL -- SYS$LOGIN: and even rooted
$ ! ones like SYS$COMMON: were both tested.  What does NOT work is the "~/"
$ ! form: Lynx expands it to an extra leading slash and cannot open the result.
$ DEFINE/NOLOG WWW_HOME "file://localhost/SYS$LOGIN:''BM_FILE'"
$ DONE:
$ EXIT
