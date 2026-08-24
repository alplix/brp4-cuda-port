#pragma once
/* Shim for llvm-mingw aarch64-w64-mingw32: BSD string helpers that
 * BOINC expects but the MinGW-w64 headers do not declare here. */
#include <string.h>
#include <strings.h>
#include <ctype.h>

#ifndef HAVE_STRLCPY
#define HAVE_STRLCPY 1
static inline size_t strlcpy(char *dst, const char *src, size_t siz) {
  size_t len = strlen(src);
  if (siz) {
    size_t copy = len >= siz ? siz - 1 : len;
    memcpy(dst, src, copy);
    dst[copy] = '\0';
  }
  return len;
}
#endif

#ifndef HAVE_STRLCAT
#define HAVE_STRLCAT 1
static inline size_t strlcat(char *dst, const char *src, size_t siz) {
  size_t dlen = strnlen(dst, siz);
  if (dlen == siz) return dlen + strlen(src);
  return dlen + strlcpy(dst + dlen, src, siz - dlen);
}
#endif

#ifndef HAVE_STRCASESTR
#define HAVE_STRCASESTR 1
static inline char *strcasestr(const char *haystack, const char *needle) {
  size_t nl = strlen(needle);
  if (!nl) return (char *)haystack;
  for (; *haystack; haystack++) {
    if (!strncasecmp(haystack, needle, nl)) return (char *)haystack;
  }
  return NULL;
}
#endif
