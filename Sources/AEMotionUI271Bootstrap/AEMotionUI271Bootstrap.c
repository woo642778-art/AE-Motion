#include "AEMotionUI271Bootstrap.h"

extern void AEMotionUI272Install(void) __attribute__((weak_import));

__attribute__((constructor)) static void AEMotionUI272BootstrapStart(void) {
    if (AEMotionUI272Install) { AEMotionUI272Install(); }
}

void AEMotionUI272BootstrapLinkAnchor(void) {}
