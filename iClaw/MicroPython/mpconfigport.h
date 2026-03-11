/*
 * MicroPython configuration for iClaw iOS embedding.
 * Enables a rich feature set for use as an AI agent's Python interpreter.
 */

#include <port/mpconfigport_common.h>

// Use FULL_FEATURES to enable most standard library modules.
#define MICROPY_CONFIG_ROM_LEVEL            (MICROPY_CONFIG_ROM_LEVEL_FULL_FEATURES)

// Core interpreter features.
#define MICROPY_ENABLE_COMPILER             (1)
#define MICROPY_ENABLE_GC                   (1)
#define MICROPY_COMP_FSTRING                (1)

// Module-level features.
#define MICROPY_PY_GC                       (1)
#define MICROPY_PY_SYS                      (1)
#define MICROPY_PY_SYS_PLATFORM             (1)
#define MICROPY_PY_SYS_STDFILES             (0)
#define MICROPY_PY_SYS_STDIO_BUFFER         (0)
#define MICROPY_PY_IO                       (0)
#define MICROPY_PY_IO_FILEIO                (0)

// Math and number support.
#define MICROPY_PY_MATH                     (1)
#define MICROPY_PY_CMATH                    (1)
#define MICROPY_PY_BUILTINS_COMPLEX         (1)
#define MICROPY_FLOAT_IMPL                  (MICROPY_FLOAT_IMPL_DOUBLE)

// Data structures.
#define MICROPY_PY_BUILTINS_SET             (1)
#define MICROPY_PY_BUILTINS_FROZENSET       (1)
#define MICROPY_PY_BUILTINS_SLICE           (1)
#define MICROPY_PY_BUILTINS_SLICE_ATTRS     (1)
#define MICROPY_PY_BUILTINS_PROPERTY        (1)
#define MICROPY_PY_BUILTINS_ENUMERATE       (1)
#define MICROPY_PY_BUILTINS_FILTER          (1)
#define MICROPY_PY_BUILTINS_REVERSED        (1)
#define MICROPY_PY_BUILTINS_MIN_MAX         (1)
#define MICROPY_PY_BUILTINS_HELP            (1)
#define MICROPY_PY_BUILTINS_STR_COUNT       (1)
#define MICROPY_PY_BUILTINS_STR_OP_MODULO   (1)
#define MICROPY_PY_BUILTINS_BYTEARRAY       (1)
#define MICROPY_PY_BUILTINS_MEMORYVIEW      (1)
#define MICROPY_PY_BUILTINS_INPUT           (0)
#define MICROPY_PY_ATTRTUPLE                (1)
#define MICROPY_PY_COLLECTIONS              (1)
#define MICROPY_PY_COLLECTIONS_DEQUE        (1)
#define MICROPY_PY_COLLECTIONS_ORDEREDDICT  (1)

// String handling.
#define MICROPY_PY_BUILTINS_STR_UNICODE     (1)
#define MICROPY_PY_BUILTINS_STR_SPLITLINES  (1)

// Standard library modules.
#define MICROPY_PY_JSON                     (1)
#define MICROPY_PY_RE                       (1)
#define MICROPY_PY_HASHLIB                  (1)
#define MICROPY_PY_BINASCII                 (1)
#define MICROPY_PY_RANDOM                   (1)
#define MICROPY_PY_STRUCT                   (1)
#define MICROPY_PY_HEAPQ                    (1)
#define MICROPY_PY_ERRNO                    (1)
#define MICROPY_PY_SELECT                   (0)
#define MICROPY_PY_TIME                     (0)

// Advanced language features.
#define MICROPY_PY_GENERATOR_PEND_THROW     (1)
#define MICROPY_PY_ASYNC_AWAIT              (1)
#define MICROPY_PY_ASSIGN_EXPR              (1)
#define MICROPY_COMP_RETURN_IF_EXPR         (1)
#define MICROPY_PY_DESCRIPTORS              (1)
#define MICROPY_PY_BUILTINS_ROUND_INT       (1)

// Error handling.
#define MICROPY_ENABLE_SOURCE_LINE          (1)
#define MICROPY_ERROR_REPORTING             (MICROPY_ERROR_REPORTING_DETAILED)
#define MICROPY_WARNINGS                    (1)
#define MICROPY_PY_BUILTINS_EXCEPTIONS      (1)

// Use setjmp for NLR and GC register capture (avoids asm issues).
#define MICROPY_NLR_SETJMP                  (1)
#define MICROPY_GCREGS_SETJMP               (1)

// Disable interactive/terminal features not available in embedded mode.
#define MICROPY_KBD_EXCEPTION               (0)
#define MICROPY_REPL_EVENT_DRIVEN           (0)

// Disable file system and builtin open (not available in sandboxed iOS).
#define MICROPY_PY_BUILTINS_OPEN            (0)
#define MICROPY_READER_POSIX                (0)
#define MICROPY_READER_VFS                  (0)
#define MICROPY_PERSISTENT_CODE_LOAD        (0)
#define MICROPY_PY_UCTYPES                  (0)
#define MICROPY_HELPER_LEXER_UNIX           (0)
#define MICROPY_MODULE_FROZEN               (0)

// Disable hardware/OS features not available on iOS.
#define MICROPY_PY_MACHINE                  (0)
#define MICROPY_PY_NETWORK                  (0)
#define MICROPY_PY_SOCKET                   (0)
#define MICROPY_PY_OS                       (0)
#define MICROPY_PY_THREAD                   (0)
#define MICROPY_PY_FFI                      (0)
#define MICROPY_PY_TERMIOS                  (0)
#define MICROPY_VFS                         (0)
#define MICROPY_VFS_POSIX                   (0)
#define MICROPY_PY_CRYPTOLIB                (0)

// VM timeout hook: allows Swift to interrupt long-running scripts.
extern volatile int mpy_timeout_flag;
extern void mpy_check_timeout(void);
#define MICROPY_VM_HOOK_INIT
#define MICROPY_VM_HOOK_LOOP    mpy_check_timeout();
#define MICROPY_VM_HOOK_RETURN

// Platform identification.
#define MICROPY_PY_SYS_PLATFORM_VALUE       "ios"
#define MICROPY_BANNER_MACHINE              "iClaw iOS"
