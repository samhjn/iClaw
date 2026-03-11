/*
 * mpy_module_requests.c
 * Injects a 'requests' module into MicroPython at runtime.
 * Uses a simple native function + Python bootstrap approach
 * to avoid QSTR pre-registration issues with the embed port.
 */

#include <stdio.h>
#include <string.h>
#include "py/runtime.h"
#include "py/compile.h"
#include "py/obj.h"
#include "py/objstr.h"
#include "py/objmodule.h"
#include "py/lexer.h"
#include "micropython_bridge.h"

/*
 * Native function: __http_request(url, method, body, headers_json)
 * Returns the response body as a string.
 * Called from the Python-level 'requests' wrapper module.
 */
static mp_obj_t mod_http_request(size_t n_args, const mp_obj_t *args) {
    const char *url = mp_obj_str_get_str(args[0]);
    const char *method = n_args > 1 ? mp_obj_str_get_str(args[1]) : "GET";
    const char *body = n_args > 2 ? mp_obj_str_get_str(args[2]) : "";
    const char *headers = n_args > 3 ? mp_obj_str_get_str(args[3]) : "{}";

    extern mpy_http_request_fn mpy_get_http_callback(void);
    mpy_http_request_fn callback = mpy_get_http_callback();
    if (!callback) {
        mp_raise_msg(&mp_type_RuntimeError, MP_ERROR_TEXT("HTTP not available"));
    }

    const char *result = callback(url, method, body, headers);
    if (!result) {
        mp_raise_msg(&mp_type_RuntimeError, MP_ERROR_TEXT("HTTP request failed"));
    }

    return mp_obj_new_str(result, strlen(result));
}
static MP_DEFINE_CONST_FUN_OBJ_VAR_BETWEEN(mod_http_request_obj, 1, 4, mod_http_request);

/*
 * Python bootstrap code that defines the 'requests' module
 * wrapping the native __http_request function.
 */
static const char *requests_bootstrap =
    "import json as _json\n"
    "class _Response:\n"
    "    def __init__(self, text, status_code=200):\n"
    "        self.text = text\n"
    "        self.content = text\n"
    "        self.status_code = status_code\n"
    "        self.ok = 200 <= status_code < 400\n"
    "    def json(self):\n"
    "        return _json.loads(self.text)\n"
    "    def __repr__(self):\n"
    "        return '<Response [%d]>' % self.status_code\n"
    "\n"
    "class _Requests:\n"
    "    def get(self, url, **kwargs):\n"
    "        return _Response(__http_request(url, 'GET', '', '{}'))\n"
    "    def post(self, url, **kwargs):\n"
    "        body = ''\n"
    "        ct = 'application/x-www-form-urlencoded'\n"
    "        if 'json' in kwargs:\n"
    "            body = _json.dumps(kwargs['json'])\n"
    "            ct = 'application/json'\n"
    "        elif 'data' in kwargs:\n"
    "            body = str(kwargs['data'])\n"
    "        headers = '{\"Content-Type\":\"%s\"}' % ct\n"
    "        return _Response(__http_request(url, 'POST', body, headers))\n"
    "    def put(self, url, **kwargs):\n"
    "        body = kwargs.get('data', '')\n"
    "        return _Response(__http_request(url, 'PUT', str(body), '{}'))\n"
    "    def delete(self, url, **kwargs):\n"
    "        return _Response(__http_request(url, 'DELETE', '', '{}'))\n"
    "\n"
    "import sys\n"
    "sys.modules['requests'] = _Requests()\n";

void mpy_register_requests_module(void) {
    qstr q_http = qstr_from_str("__http_request");
    mp_store_global(q_http, MP_OBJ_FROM_PTR(&mod_http_request_obj));

    mp_lexer_t *lex = mp_lexer_new_from_str_len(
        MP_QSTR__lt_stdin_gt_,
        requests_bootstrap,
        strlen(requests_bootstrap),
        0
    );
    qstr source_name = lex->source_name;
    mp_parse_tree_t parse_tree = mp_parse(lex, MP_PARSE_FILE_INPUT);
    mp_obj_t module_fun = mp_compile(&parse_tree, source_name, true);
    mp_call_function_0(module_fun);
}
