#include "AEMotionUI271Bootstrap.h"

extern void AEMotionUI271Install(void) __attribute__((weak_import));

__attribute__((constructor)) static void AEMotionUI271BootstrapStart(void) {
    if (AEMotionUI271Install) { AEMotionUI271Install(); }
}

void AEMotionUI271BootstrapLinkAnchor(void) {}
