/*
 * micropython_bridge.h
 * C bridge between Swift and the embedded MicroPython interpreter.
 */

#ifndef MICROPYTHON_BRIDGE_H
#define MICROPYTHON_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Callback type for HTTP requests from Python code.
 * Parameters: url, method, body, headers_json
 * Returns: JSON string with {status, headers, body, error}
 * The returned string must remain valid until the next call.
 */
typedef const char *(*mpy_http_request_fn)(const char *url,
                                           const char *method,
                                           const char *body,
                                           const char *headers_json);

/* Initialize the MicroPython interpreter with a GC heap. */
void mpy_init(void);

/* Shut down the MicroPython interpreter and free resources. */
void mpy_deinit(void);

/* Execute a Python script. Returns true on success, false on exception. */
bool mpy_exec_script(const char *code);

/* Evaluate a Python expression and return its repr() as a string.
   Returns NULL on error. The returned pointer is valid until the next call. */
const char *mpy_eval_repr(const char *expr);

/* Get the captured stdout output after execution. */
const char *mpy_get_stdout(void);

/* Get the captured stderr/exception output after execution. */
const char *mpy_get_stderr(void);

/* Register a callback for HTTP requests from Python code. */
void mpy_set_http_callback(mpy_http_request_fn fn);

/* Get the current HTTP callback. */
mpy_http_request_fn mpy_get_http_callback(void);

/* Request the VM to stop execution at the next opportunity. */
void mpy_request_timeout(void);

/* Clear the timeout flag. Call before starting execution. */
void mpy_clear_timeout(void);

#ifdef __cplusplus
}
#endif

#endif /* MICROPYTHON_BRIDGE_H */
