// Minimal SjLj unwind shims for the armv7s iOS toolchain used by this iPad.
// Safe for this app because it does not use exception handling.
#include <stdlib.h>

typedef struct _Unwind_FunctionContext *_Unwind_FunctionContext_t;

void _Unwind_SjLj_Register(_Unwind_FunctionContext_t fc) {
    (void)fc;
}

void _Unwind_SjLj_Unregister(_Unwind_FunctionContext_t fc) {
    (void)fc;
}

void _Unwind_SjLj_Resume(void *exc) {
    (void)exc;
    abort();
}
