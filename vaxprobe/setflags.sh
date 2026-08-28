#!/bin/bash
# Sets the DEC C compiler flags in Lynx's three VMS build procedures.
#   ./setflags.sh accept   -> /ACCEPT=NOVAXC_KEYWORDS      (recommended)
#   ./setflags.sh ansi     -> /STANDARD=ANSI89/WARNING=(DISABLE=DOLLARID)
#   ./setflags.sh restore  -> put the pristine files back
cd "$(dirname "$0")/.." || exit 1
B=build.com; L=WWW/Library/vms/libmake.com; C=src/chrtrans/build-chrtrans.com

case "$1" in
  accept) OPTS='/ACCEPT=NOVAXC_KEYWORDS' ;;
  ansi)   OPTS='/STANDARD=ANSI89/WARNING=(DISABLE=DOLLARID)' ;;
  restore) cp vaxprobe/orig/build.com "$B"
           cp vaxprobe/orig/libmake.com "$L"
           cp vaxprobe/orig/build-chrtrans.com "$C"
           echo "restored pristine files"; exit 0 ;;
  *) echo "usage: $0 {accept|ansi|restore}"; exit 1 ;;
esac

cp vaxprobe/orig/build.com "$B"
cp vaxprobe/orig/libmake.com "$L"
cp vaxprobe/orig/build-chrtrans.com "$C"

# Strict ANSI89 drops the predefined VMS/vms macros, so that route alone
# needs them re-added via extra_defs.  /ACCEPT keeps them (probe-confirmed).
if [ "$1" = ansi ]; then
  sed -i "73s|.*|\$ extra_defs = \",VMS=1,vms=1\"|"              "$B"
  sed -i "46s|.*|\$ extra_defs = \",ACCESS_AUTH,VMS=1,vms=1\"|"  "$L"
  DEFS='/DEFINE=(VMS=1,vms=1)'
else
  DEFS=''
fi

sed -i "152s|.*|\$ cc_opts = \"$OPTS\"|" "$B"
sed -i "148s|.*|\$ cc_opts = \"$OPTS\"|" "$L"
sed -i "18s|.*|\$      CHRcc_opts = \"$OPTS/DEBUG/NOOPT$DEFS\"|" "$C"
sed -i "21s|.*|\$      CHRcc_opts = \"$OPTS$DEFS\"|"             "$C"

echo "flags set to: $OPTS"
