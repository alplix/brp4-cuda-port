/* ARM64-Windows stand-in for BOINC's x86-only stackwalker_win.cpp.
 * The generic CONTEXT register dump does not exist on ARM64; emit a
 * minimal notice instead of a register/stack trace. */
#include <windows.h>
#include <stdio.h>

#include "stackwalker_win.h"

void StackwalkThread(HANDLE hThread, CONTEXT *c) {
    (void)hThread;
    (void)c;
    fprintf(stderr,
            "\nCallstack dumps are not implemented for this architecture "
            "(aarch64); skipping stack walk.\n");
}

DWORD StackwalkFilter(EXCEPTION_POINTERS *ep, DWORD status) {
    (void)ep;
    (void)status;
    fprintf(stderr,
            "\nException caught; callstack dumps are not implemented for "
            "this architecture (aarch64).\n");
    return EXCEPTION_EXECUTE_HANDLER;
}

int DebuggerInitialize(LPCSTR pszBOINCLocation, LPCSTR pszSymbolStore,
                       BOOL bProxyEnabled, LPCSTR pszProxyServer) {
    (void)pszBOINCLocation;
    (void)pszSymbolStore;
    (void)bProxyEnabled;
    (void)pszProxyServer;
    return 0; /* FALSE: debugger support not available */
}

int DebuggerDisplayDiagnostics() {
    return 0;
}
