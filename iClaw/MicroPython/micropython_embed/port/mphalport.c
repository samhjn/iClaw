/*
 * Custom HAL port for iClaw iOS embedding.
 * Redirects MicroPython stdout to an in-memory buffer
 * that the Swift layer can read after execution.
 */

#include <string.h>
#include "py/mphal.h"

#define MPY_OUTPUT_BUF_SIZE (256 * 1024)

static char mpy_stdout_buf[MPY_OUTPUT_BUF_SIZE];
static size_t mpy_stdout_len = 0;

void mp_hal_stdout_tx_strn_cooked(const char *str, size_t len) {
    size_t remaining = MPY_OUTPUT_BUF_SIZE - 1 - mpy_stdout_len;
    size_t copy = len < remaining ? len : remaining;
    if (copy > 0) {
        memcpy(mpy_stdout_buf + mpy_stdout_len, str, copy);
        mpy_stdout_len += copy;
    }
}

mp_uint_t mp_hal_stdout_tx_strn(const char *str, size_t len) {
    mp_hal_stdout_tx_strn_cooked(str, len);
    return len;
}

const char *mpy_get_stdout_buf(void) {
    mpy_stdout_buf[mpy_stdout_len] = '\0';
    return mpy_stdout_buf;
}

size_t mpy_get_stdout_len(void) {
    return mpy_stdout_len;
}

void mpy_reset_stdout_buf(void) {
    mpy_stdout_len = 0;
    mpy_stdout_buf[0] = '\0';
}

int mp_hal_stdin_rx_chr(void) {
    return '\n';
}

void mp_hal_set_interrupt_char(int c) {
    (void)c;
}

mp_uint_t mp_hal_ticks_ms(void) {
    return 0;
}

mp_uint_t mp_hal_ticks_us(void) {
    return 0;
}

mp_uint_t mp_hal_ticks_cpu(void) {
    return 0;
}

/* Stubs for file system operations (not available on embedded iOS). */

#include "py/lexer.h"
#include "py/builtin.h"
#include "py/runtime.h"

mp_import_stat_t mp_import_stat(const char *path) {
    (void)path;
    return MP_IMPORT_STAT_NO_EXIST;
}

mp_lexer_t *mp_lexer_new_from_file(qstr filename) {
    (void)filename;
    mp_raise_msg(&mp_type_OSError, MP_ERROR_TEXT("no filesystem"));
    return NULL;
}
