/*
 * probe3.c -- isolate the Lynx/VMS network failure.
 *
 * Reproduces exactly the call sequence HTDoConnect() uses in
 * WWW/Library/Implementation/HTTCP.c, in the same order, with the same
 * headers, so that the ACCVIO can be pinned to one call without
 * rebuilding Lynx.
 *
 * The include list below is copied verbatim from the UCX branch of
 * www_tcp.h (lines 544-563).  HTioctl() is copied verbatim from
 * HTTCP.c lines 115-160.  Do not "clean these up" -- the point is to
 * be byte-for-byte what Lynx does.
 *
 * Usage (see probe3.com):
 *     $ probe3 188.184.67.127 IOCTL
 *     $ probe3 188.184.67.127 NOIOCTL
 *
 * Every step prints and flushes before it runs, so the last line you
 * see is the call that died.
 *
 * Not derived from Lynx source except for the two marked blocks
 * (GPL-2.0, as the rest of the tree).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* --- exactly www_tcp.h's UCX include chain --- */
#include <types.h>
#include <errno.h>
#include <time.h>
#include <socket.h>
#include <in.h>
#include <inet.h>
#include <netdb.h>
#include <ucx$inetdef.h>
/* --- end www_tcp.h chain --- */

#include <iodef.h>

/* from HTioctl.h */
#define IOC_OUT (int)0x40000000
extern int vaxc$get_sdc(), sys$qiow();

#ifndef UCX$C_IOCTL
#define UCX$C_IOCTL TCPIP$C_IOCTL
#endif

#define SAY(s)      do { printf("%s\n", s);       fflush(stdout); } while (0)
#define SAYD(s,d)   do { printf("%s %d\n", s, d); fflush(stdout); } while (0)

/* ------------------------------------------------------------------
 * Verbatim from HTTCP.c lines 115-160.
 * ------------------------------------------------------------------ */
int HTioctl(int d,
	    int request,
	    int *argp)
{
    int sdc, status;
    unsigned short fun, iosb[4];
    char *p5, *p6;
    struct comm {
	int command;
	char *addr;
    } ioctl_comm;
    struct it2 {
	unsigned short len;
	unsigned short opt;
	struct comm *addr;
    } ioctl_desc;

    if ((sdc = vaxc$get_sdc(d)) == 0) {
	printf("        HTioctl: vaxc$get_sdc(%d) returned 0 (EBADF)\n", d);
	fflush(stdout);
	errno = EBADF;
	return -1;
    }
    printf("        HTioctl: vaxc$get_sdc(%d) = %d (0x%x)\n", d, sdc, sdc);
    fflush(stdout);

    ioctl_desc.opt = UCX$C_IOCTL;
    ioctl_desc.len = sizeof(struct comm);

    ioctl_desc.addr = &ioctl_comm;
    if (request & IOC_OUT) {
	fun = IO$_SENSEMODE;
	p5 = 0;
	p6 = (char *) &ioctl_desc;
    } else {
	fun = IO$_SETMODE;
	p5 = (char *) &ioctl_desc;
	p6 = 0;
    }
    ioctl_comm.command = request;
    ioctl_comm.addr = (char *) argp;

    SAY("        HTioctl: about to call sys$qiow ...");
    status = sys$qiow(0, sdc, fun, iosb, 0, 0, 0, 0, 0, 0, p5, p6);
    printf("        HTioctl: sys$qiow returned %d (0x%x), iosb[0]=%d\n",
	   status, status, (int) iosb[0]);
    fflush(stdout);

    if (!(status & 01)) {
	errno = status;
	return -1;
    }
    if (!(iosb[0] & 01)) {
	errno = iosb[0];
	return -1;
    }
    return 0;
}
/* ------------------------------------------------------------------ */

int main(int argc, char **argv)
{
    struct sockaddr_in sock_A;
    struct sockaddr_in *soc_in = &sock_A;
    char *ip;
    int use_ioctl = 1;
    int s, status, val, ret, n, total;
    char buf[512];
    static char req[] = "GET / HTTP/1.0\r\n\r\n";
    fd_set writefds, readfds;
    struct timeval tv;
    int tries;

    ip = (argc > 1) ? argv[1] : "188.184.67.127";
    if (argc > 2 && (argv[2][0] == 'N' || argv[2][0] == 'n'))
	use_ioctl = 0;

    printf("probe3: target %s port 80, ioctl=%s\n",
	   ip, use_ioctl ? "yes" : "no");
    printf("        sizeof(struct sockaddr_in) = %d\n",
	   (int) sizeof(struct sockaddr_in));
    fflush(stdout);

    /* --- step 1: fill in the address, as HTParseInet does --- */
    SAY("[1] memset + inet_addr ...");
    memset(soc_in, 0, sizeof(*soc_in));
    soc_in->sin_family = AF_INET;
    soc_in->sin_port = htons((unsigned short) 80);
    soc_in->sin_addr.s_addr = inet_addr(ip);
    printf("    sin_addr = %d.%d.%d.%d  sin_port = %d\n",
	   (int) *((unsigned char *) (&soc_in->sin_addr) + 0),
	   (int) *((unsigned char *) (&soc_in->sin_addr) + 1),
	   (int) *((unsigned char *) (&soc_in->sin_addr) + 2),
	   (int) *((unsigned char *) (&soc_in->sin_addr) + 3),
	   (int) ntohs(soc_in->sin_port));
    fflush(stdout);

    /* --- step 2: socket() --- */
    SAY("[2] socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) ...");
    s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    SAYD("    socket() =", s);
    if (s == -1) {
	perror("    socket");
	return 2;
    }

    /* --- step 3: the non-blocking ioctl (prime suspect) --- */
    if (use_ioctl) {
	SAY("[3] HTioctl(s, FIONBIO, &1)  <-- prime suspect ...");
	val = 1;
	ret = HTioctl(s, FIONBIO, &val);
	SAYD("    HTioctl returned", ret);
	if (ret == -1)
	    perror("    HTioctl");
    } else {
	SAY("[3] skipped (NOIOCTL) -- socket stays blocking");
    }

    /* --- step 4: connect() --- */
    SAY("[4] connect() ...");
    status = connect(s, (struct sockaddr *) &sock_A, sizeof(sock_A));
    SAYD("    connect() =", status);
    if (status < 0) {
	printf("    errno = %d\n", errno);
	fflush(stdout);
	perror("    connect");
	if (!use_ioctl) {
	    SAY("    blocking connect failed outright -- stack problem, not Lynx");
	    return 3;
	}
    }

    /* --- step 5: select() for writability, as HTDoConnect does --- */
    if (use_ioctl && status < 0) {
	SAY("[5] select() waiting for connect to complete ...");
	for (tries = 0; tries < 100; tries++) {
	    FD_ZERO(&writefds);
	    FD_SET(s, &writefds);
	    tv.tv_sec = 0;
	    tv.tv_usec = 100000;
	    ret = select(s + 1, NULL, &writefds, NULL, &tv);
	    if (ret > 0)
		break;
	    if (ret < 0) {
		printf("    select() = %d errno = %d\n", ret, errno);
		fflush(stdout);
		perror("    select");
		return 4;
	    }
	}
	SAYD("    select() ready after tries =", tries);
	if (tries >= 100) {
	    SAY("    timed out waiting for connect");
	    return 4;
	}
	SAY("[6] HTioctl(s, FIONBIO, &0)  restore blocking ...");
	val = 0;
	ret = HTioctl(s, FIONBIO, &val);
	SAYD("    HTioctl returned", ret);
    } else {
	SAY("[5] [6] skipped");
    }

    /* --- step 7: write the request --- */
    SAY("[7] send request ...");
    n = write(s, req, (int) strlen(req));
    SAYD("    write() =", n);
    if (n < 0) {
	perror("    write");
	return 5;
    }

    /* --- step 8: read the response --- */
    SAY("[8] read response ...");
    total = 0;
    while (total < 400) {
	FD_ZERO(&readfds);
	FD_SET(s, &readfds);
	tv.tv_sec = 10;
	tv.tv_usec = 0;
	ret = select(s + 1, &readfds, NULL, NULL, &tv);
	if (ret <= 0) {
	    SAYD("    select-for-read returned", ret);
	    break;
	}
	n = read(s, buf, (int) sizeof(buf) - 1);
	if (n <= 0) {
	    SAYD("    read() =", n);
	    break;
	}
	buf[n] = '\0';
	fputs(buf, stdout);
	fflush(stdout);
	total += n;
    }
    printf("\n    total bytes read = %d\n", total);
    fflush(stdout);

    SAY("[9] close ...");
    close(s);
    SAY("=== probe3 completed without crashing ===");
    return 0;
}
