/* No-op replacement for exchndl (crash dump handler).
 * Used when libbfd/libiberty/libintl are not available.
 * To enable real crash dumps, build exchndl64.c instead and link
 * against bfd/liberty/intl, replacing this object in the Makefile. */

#include "exchndl.h"

void ExchndlSetup(void) {}
void ExchndlShutdown(void) {}
