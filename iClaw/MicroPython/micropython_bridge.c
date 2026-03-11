/*
 * micropython_bridge.c
 * Implements the C bridge between Swift and MicroPython.
 */

#include "micropython_bridge.h"
#include "port/micropython_embed.h"

#include <string.h>
#include <stdio.h>
#include <time.h>
#include <os/log.h>

#include "py/compile.h"
#include "py/gc.h"
#include "py/runtime.h"
#include "py/stackctrl.h"
#include "py/mpstate.h"
#include "py/mpprint.h"
#include "py/objstr.h"
#include "py/nlr.h"
#include "mpy_bootstrap.h"

#define MPY_LOG(fmt, ...) os_log_error(OS_LOG_DEFAULT, "[MPY-C] " fmt, ##__VA_ARGS__)

/* ── GC heap ─────────────────────────────────────────────────────── */

#define MPY_GC_HEAP_SIZE (256 * 1024)
static char mpy_gc_heap[MPY_GC_HEAP_SIZE];

/* ── Stdout buffer (defined in mphalport.c) ──────────────────────── */

extern const char *mpy_get_stdout_buf(void);
extern size_t mpy_get_stdout_len(void);
extern void mpy_reset_stdout_buf(void);

/* ── Stderr capture buffer ───────────────────────────────────────── */

#define MPY_STDERR_BUF_SIZE (32 * 1024)
static char mpy_stderr_buf[MPY_STDERR_BUF_SIZE];
static size_t mpy_stderr_len = 0;

static void stderr_print_strn(void *env, const char *str, size_t len) {
    (void)env;
    size_t remaining = MPY_STDERR_BUF_SIZE - 1 - mpy_stderr_len;
    size_t copy = len < remaining ? len : remaining;
    if (copy > 0) {
        memcpy(mpy_stderr_buf + mpy_stderr_len, str, copy);
        mpy_stderr_len += copy;
    }
}

static const mp_print_t mpy_stderr_print = {NULL, stderr_print_strn};

static void set_stderr(const char *msg) {
    size_t len = strlen(msg);
    size_t copy = len < MPY_STDERR_BUF_SIZE - 1 ? len : MPY_STDERR_BUF_SIZE - 1;
    memcpy(mpy_stderr_buf, msg, copy);
    mpy_stderr_len = copy;
    mpy_stderr_buf[copy] = '\0';
}

/* ── Repr result buffer ──────────────────────────────────────────── */

#define MPY_REPR_BUF_SIZE (64 * 1024)
static char mpy_repr_buf[MPY_REPR_BUF_SIZE];
static size_t mpy_repr_len = 0;

static void repr_print_strn(void *env, const char *str, size_t len) {
    (void)env;
    size_t remaining = MPY_REPR_BUF_SIZE - 1 - mpy_repr_len;
    size_t copy = len < remaining ? len : remaining;
    if (copy > 0) {
        memcpy(mpy_repr_buf + mpy_repr_len, str, copy);
        mpy_repr_len += copy;
    }
}

static const mp_print_t mpy_repr_print = {NULL, repr_print_strn};

/* ── HTTP callback ───────────────────────────────────────────────── */

static mpy_http_request_fn g_http_callback = NULL;

void mpy_set_http_callback(mpy_http_request_fn fn) {
    g_http_callback = fn;
}

mpy_http_request_fn mpy_get_http_callback(void) {
    return g_http_callback;
}

/* ── VM timeout mechanism ────────────────────────────────────────── */

volatile int mpy_timeout_flag = 0;

void mpy_check_timeout(void) {
    if (mpy_timeout_flag) {
        mpy_timeout_flag = 0;
        mp_raise_msg(&mp_type_RuntimeError, MP_ERROR_TEXT("execution timed out"));
    }
}

void mpy_request_timeout(void) {
    MPY_LOG("mpy_request_timeout called");
    mpy_timeout_flag = 1;
}

void mpy_clear_timeout(void) {
    mpy_timeout_flag = 0;
}

/* ── Native helpers exposed to Python ────────────────────────────── */

static mp_obj_t mod_get_time(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    double t = (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
    return mp_obj_new_float(t);
}
static MP_DEFINE_CONST_FUN_OBJ_0(mod_get_time_obj, mod_get_time);

/* ── Bootstrap & Requests module ─────────────────────────────────── */

extern void mpy_register_requests_module(void);

static void mpy_register_native_helpers(void) {
    qstr q = qstr_from_str("__get_time");
    mp_store_global(q, MP_OBJ_FROM_PTR(&mod_get_time_obj));
}

static bool mpy_run_bootstrap(void) {
    MPY_LOG("bootstrap: registering native helpers");
    mpy_register_native_helpers();
    MPY_LOG("bootstrap: running stdlib modules bootstrap");
    mp_lexer_t *lex = mp_lexer_new_from_str_len(
        MP_QSTR__lt_stdin_gt_, mpy_bootstrap_script,
        strlen(mpy_bootstrap_script), 0);
    qstr source_name = lex->source_name;
    mp_parse_tree_t pt = mp_parse(lex, MP_PARSE_FILE_INPUT);
    mp_obj_t fun = mp_compile(&pt, source_name, true);
    mp_call_function_0(fun);
    MPY_LOG("bootstrap: stdlib modules OK (json,re,datetime,time,random,base64,heapq,binascii,hashlib)");
    return true;
}

/* ── Safe exception printing ─────────────────────────────────────── */

/*
 * After the outer nlr_push catches an exception, nlr_top is NULL.
 * mp_obj_print_exception can trigger secondary exceptions internally
 * (e.g. MemoryError during formatting). Without nlr_push protection
 * that would call nlr_jump_fail → infinite loop.
 *
 * This helper wraps the print call in a fresh nlr_push.
 */
static void safe_print_exception(mp_obj_t exc) {
    const char *type_name = "?";
    const char *msg_str = "";

    /* Extract type name. */
    nlr_buf_t nlr0;
    if (nlr_push(&nlr0) == 0) {
        const mp_obj_type_t *type = mp_obj_get_type(exc);
        type_name = qstr_str(type->name);
        MPY_LOG("Exception type: %{public}s", type_name);
        nlr_pop();
    }

    /* Extract message via mp_obj_print to a small buffer. */
    nlr_buf_t nlr1;
    if (nlr_push(&nlr1) == 0) {
        static char exc_msg_buf[256];
        static size_t exc_msg_len;
        exc_msg_len = 0;
        exc_msg_buf[0] = '\0';

        /* Print the exception value (not the traceback) into our buffer. */
        mp_print_t exc_print = {NULL, stderr_print_strn};
        /* Temporarily redirect stderr capture to our small buffer. */
        size_t saved_len = mpy_stderr_len;
        mpy_stderr_len = 0;
        mpy_stderr_buf[0] = '\0';

        mp_obj_print_helper(&mpy_stderr_print, exc, PRINT_EXC);
        mpy_stderr_buf[mpy_stderr_len] = '\0';
        msg_str = mpy_stderr_buf[0] ? mpy_stderr_buf : "(no message)";
        MPY_LOG("Exception value: %{public}s", msg_str);

        /* Copy to our small buffer and reset stderr. */
        snprintf(exc_msg_buf, sizeof(exc_msg_buf), "%s", mpy_stderr_buf);
        msg_str = exc_msg_buf;
        mpy_stderr_len = saved_len;

        nlr_pop();
    }

    /* Try full traceback. */
    nlr_buf_t nlr2;
    if (nlr_push(&nlr2) == 0) {
        mp_obj_print_exception(&mpy_stderr_print, exc);
        nlr_pop();
        MPY_LOG("Full traceback written to stderr buffer");
    } else {
        /* Full formatting failed; build a minimal error message. */
        char buf[512];
        snprintf(buf, sizeof(buf), "%s: %s", type_name, msg_str);
        set_stderr(buf);
        MPY_LOG("Traceback formatting failed, using minimal: %{public}s", buf);
    }
}

/* Safe deinit — also protected against secondary exceptions. */
static void safe_deinit(void) {
    nlr_buf_t nlr;
    if (nlr_push(&nlr) == 0) {
        mp_embed_deinit();
        nlr_pop();
    }
}

/* ── Reset output buffers ────────────────────────────────────────── */

static void reset_all_buffers(void) {
    mpy_reset_stdout_buf();
    mpy_stderr_len = 0;
    mpy_stderr_buf[0] = '\0';
    mpy_repr_len = 0;
    mpy_repr_buf[0] = '\0';
}

/* ── Public API ──────────────────────────────────────────────────── */

void mpy_init(void) {
}

void mpy_deinit(void) {
}

bool mpy_exec_script(const char *code) {
    MPY_LOG("exec_script: START, code(first 120)=%{public}.120s", code);
    reset_all_buffers();
    mpy_timeout_flag = 0;

    MP_STATE_THREAD(nlr_top) = NULL;

    int stack_top;
    bool inited = false;

    nlr_buf_t nlr;
    if (nlr_push(&nlr) == 0) {
        MPY_LOG("exec_script: calling mp_embed_init");
        mp_embed_init(mpy_gc_heap, sizeof(mpy_gc_heap), &stack_top);
        mp_stack_set_limit(128 * 1024);
        inited = true;
        MPY_LOG("exec_script: mp_embed_init OK");

        mpy_run_bootstrap();
        MPY_LOG("exec_script: registering requests module");
        mpy_register_requests_module();
        MPY_LOG("exec_script: requests module OK");

        MPY_LOG("exec_script: compiling code (len=%zu)", strlen(code));
        mp_lexer_t *lex = mp_lexer_new_from_str_len(
            MP_QSTR__lt_stdin_gt_, code, strlen(code), 0);
        qstr source_name = lex->source_name;
        mp_parse_tree_t parse_tree = mp_parse(lex, MP_PARSE_FILE_INPUT);
        mp_obj_t module_fun = mp_compile(&parse_tree, source_name, true);
        MPY_LOG("exec_script: executing");
        mp_call_function_0(module_fun);
        MPY_LOG("exec_script: execution OK");

        nlr_pop();
        mp_embed_deinit();
        MPY_LOG("exec_script: DONE (success)");
        return true;
    } else {
        MPY_LOG("exec_script: EXCEPTION caught, printing...");
        safe_print_exception((mp_obj_t)nlr.ret_val);
        MPY_LOG("exec_script: exception printed");
        if (inited) {
            safe_deinit();
        }
        MPY_LOG("exec_script: DONE (failure), stderr=%{public}s", mpy_stderr_buf);
        return false;
    }
}

const char *mpy_eval_repr(const char *expr) {
    MPY_LOG("eval_repr: START, expr(first 120)=%{public}.120s", expr);
    reset_all_buffers();
    mpy_timeout_flag = 0;

    MP_STATE_THREAD(nlr_top) = NULL;

    int stack_top;
    bool inited = false;

    nlr_buf_t nlr;
    if (nlr_push(&nlr) == 0) {
        MPY_LOG("eval_repr: calling mp_embed_init");
        mp_embed_init(mpy_gc_heap, sizeof(mpy_gc_heap), &stack_top);
        mp_stack_set_limit(128 * 1024);
        inited = true;
        MPY_LOG("eval_repr: mp_embed_init OK");

        mpy_run_bootstrap();
        MPY_LOG("eval_repr: registering requests module");
        mpy_register_requests_module();
        MPY_LOG("eval_repr: requests module OK");

        MPY_LOG("eval_repr: compiling expression (len=%zu)", strlen(expr));
        mp_lexer_t *lex = mp_lexer_new_from_str_len(
            MP_QSTR__lt_stdin_gt_, expr, strlen(expr), 0);
        qstr source_name = lex->source_name;
        mp_parse_tree_t parse_tree = mp_parse(lex, MP_PARSE_EVAL_INPUT);
        mp_obj_t module_fun = mp_compile(&parse_tree, source_name, false);
        MPY_LOG("eval_repr: calling function");
        mp_obj_t eval_result = mp_call_function_0(module_fun);

        mp_obj_print_helper(&mpy_repr_print, eval_result, PRINT_REPR);
        mpy_repr_buf[mpy_repr_len] = '\0';

        nlr_pop();
        mp_embed_deinit();
        MPY_LOG("eval_repr: DONE (success)");
        return mpy_repr_buf;
    } else {
        MPY_LOG("eval_repr: EXCEPTION caught, printing...");
        safe_print_exception((mp_obj_t)nlr.ret_val);
        MPY_LOG("eval_repr: exception printed");
        if (inited) {
            safe_deinit();
        }
        MPY_LOG("eval_repr: DONE (failure), stderr=%{public}s", mpy_stderr_buf);
        return NULL;
    }
}

/* ── Output access ───────────────────────────────────────────────── */

const char *mpy_get_stdout(void) {
    return mpy_get_stdout_buf();
}

const char *mpy_get_stderr(void) {
    mpy_stderr_buf[mpy_stderr_len] = '\0';
    return mpy_stderr_buf;
}
