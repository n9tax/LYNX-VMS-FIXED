/* probe.c - settles the Lynx/VMS compiler-flag question in one compile. */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

/* 1. The actual Lynx failure: "readonly" as a struct member. */
struct probe_form {
    int disabled;
    int readonly;
};

/* 2. Do the VMS predefined macros survive the chosen flags? */
#ifdef VMS
#define HAVE_VMS "yes"
#else
#define HAVE_VMS "NO  <-- must add /DEFINE=(VMS=1,vms=1)"
#endif

#ifdef vms
#define HAVE_vms "yes"
#else
#define HAVE_vms "NO  <-- must add /DEFINE=(VMS=1,vms=1)"
#endif

int main(void)
{
    struct probe_form f;
    char buf[256];

    f.disabled = 0;
    f.readonly = 1;

    /* 3. Are the non-ANSI VMS/POSIX prototypes still visible?  If these
     * warn IMPLICITFUNC, strict ANSI89 has hidden the headers and the
     * build will be full of silent wrong-return-type bugs. */
    (void) getcwd(buf, sizeof(buf));
    (void) getpid();
    (void) unlink("nl:");

    printf("readonly-as-member: OK\n");
    printf("VMS macro         : %s\n", HAVE_VMS);
    printf("vms macro         : %s\n", HAVE_vms);
    printf("getcwd/getpid     : see compile warnings above\n");
    return f.readonly ? 0 : 1;
}
