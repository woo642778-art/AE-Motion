#include "AEMotionBootstrap.h"
extern void AEMotionExtensionsInstall(void) __attribute__((weak_import));
__attribute__((constructor)) static void AEMotionBootstrapStart(void) {
    if (AEMotionExtensionsInstall) { AEMotionExtensionsInstall(); }
}
