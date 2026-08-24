/* Minimal stand-in for erp_execinfo_plus.c used by builds where the
 * binutils bfd library is unavailable for the target architecture
 * (e.g. the aarch64 cross build). Prints the raw backtrace symbol list
 * without the addr2line-based enhancement.
 *
 * Same interface: int backtrace_symbols_fd_plus(const char *const *, int, int)
 */
#include <unistd.h>

#include "erp_execinfo_plus.h"

int backtrace_symbols_fd_plus(const char *const *symbols, int size, int fd) {
  if (symbols == NULL || size <= 0 || fd < 0) return -1;
  for (int i = 0; i < size; i++) {
    const char *s = symbols[i];
    if (s == NULL) s = "(null)";
    size_t len = 0;
    while (s[len] != '\0') len++;
    if (len > 0 && write(fd, s, len) < 0) return -1;
    if (write(fd, "\n", 1) < 0) return -1;
  }
  return 0;
}
