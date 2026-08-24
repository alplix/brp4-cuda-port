/*
 * Minimal stand-in for binutils' internal "sysdep.h" header.
 *
 * erp_execinfo_plus.c is derived from binutils' addr2line.c and expects the
 * private sysdep.h shipped in the binutils sources, which distributions do
 * not install. It provides the C library headers used throughout binutils,
 * the gettext shorthand (kept as identity - no NLS here) and the default
 * BFD target used when translating crash addresses of our own binary.
 */
#ifndef ERP_COMPAT_SYSDEP_H
#define ERP_COMPAT_SYSDEP_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

#ifndef _
#define _(String) (String)
#endif

/* native little-endian x86_64 ELF target of this executable */
#ifndef TARGET
#define TARGET "elf64-x86-64"
#endif

#endif /* ERP_COMPAT_SYSDEP_H */
