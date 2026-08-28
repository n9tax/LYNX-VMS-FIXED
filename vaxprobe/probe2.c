/* probe2.c - validates the DECC + UCX header maze that PROBLEMS warns about.
 * Mirrors HTTCP.c's include set, which is the module most exposed to
 * TCP-stack header incompatibilities.  Compile-only; nothing is linked.
 *
 * Copy into [.WWW.LIBRARY.VMS] and run @PROBE2 from there. */

#include <HTUtils.h>		/* pulls www_tcp.h and the whole UCX chain */
#include <HTParse.h>
#include <HTAlert.h>
#include <HTTCP.h>
#include <LYGlobalDefs.h>
#include <LYUtils.h>
#include <HTioctl.h>

/* 1. struct timeval -- the exact symptom PROBLEMS describes for MultiNet.
 *    Under UCX it must already come from the system headers. */
static struct timeval probe_tv;

/* 2. the socket types HTTCP.c actually uses */
static struct sockaddr_in probe_sin;
static struct hostent *probe_he;

int probe2_check(void)
{
    int s;
    fd_set rfds;

    probe_tv.tv_sec = 1;
    probe_tv.tv_usec = 0;

    /* 3. prototypes -- any IMPLICITFUNC here means a header did not load */
    s = socket(AF_INET, SOCK_STREAM, 0);
    probe_sin.sin_family = AF_INET;
    probe_sin.sin_port = htons((unsigned short) 80);
    probe_he = gethostbyname("localhost");

    FD_ZERO(&rfds);
    FD_SET(s, &rfds);
    (void) select(s + 1, &rfds, NULL, NULL, &probe_tv);
    (void) connect(s, (struct sockaddr *) &probe_sin, sizeof(probe_sin));

    return (probe_he == 0) ? 1 : 0;
}
