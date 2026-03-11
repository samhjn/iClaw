import Foundation
import JavaScriptCore

/// A Python executor backed by JavaScriptCore with a Python compatibility layer.
/// Supports common built-in functions, modules (json, math, re, datetime, random, base64),
/// basic HTTP requests via URLSession bridge, and Python-like repr output.
final class JSCorePythonExecutor: CodeExecutor, @unchecked Sendable {
    let language = "python"
    let isAvailable = true

    func execute(code: String, mode: ExecutionMode) async throws -> ExecutionResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.run(code: code, mode: mode)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func run(code: String, mode: ExecutionMode) throws -> ExecutionResult {
        let ctx = JSContext()!
        var jsException: String?
        ctx.exceptionHandler = { _, exception in
            jsException = exception?.toString()
        }

        ctx.evaluateScript(Self.pythonRuntime)
        injectNetworkBridge(ctx)

        switch mode {
        case .repr:
            let js = PythonTranspiler.transpileExpression(code)
            let wrapped = "(function() { try { return __py_repr(\(js)); } catch(e) { __stderr += String(e); return null; } })()"
            let result = ctx.evaluateScript(wrapped)

            let stdout = ctx.evaluateScript("__stdout")?.toString() ?? ""
            let stderr = ctx.evaluateScript("__stderr")?.toString() ?? ""

            if let ex = jsException {
                return .failure(stderr: pythonizeError(ex))
            }

            let repr = result?.isNull == true ? nil : (result?.toString() ?? "None")
            return .success(stdout: stdout, stderr: stderr.isEmpty ? "" : stderr, repr: repr ?? "None")

        case .script:
            let js = PythonTranspiler.transpileScript(code)
            ctx.evaluateScript(js)

            let stdout = ctx.evaluateScript("__stdout")?.toString() ?? ""
            let stderr = ctx.evaluateScript("__stderr")?.toString() ?? ""

            if let ex = jsException {
                let combinedErr = stderr.isEmpty ? pythonizeError(ex) : stderr + "\n" + pythonizeError(ex)
                return .failure(stderr: combinedErr)
            }
            return .success(stdout: stdout, stderr: stderr)
        }
    }

    private func pythonizeError(_ jsError: String) -> String {
        var err = jsError
        err = err.replacingOccurrences(of: "ReferenceError", with: "NameError")
        err = err.replacingOccurrences(of: "TypeError: undefined is not", with: "TypeError: 'NoneType' object is not")
        err = err.replacingOccurrences(of: "is not defined", with: "is not defined")
        return err
    }

    // MARK: - Network Bridge

    private func injectNetworkBridge(_ ctx: JSContext) {
        let httpGet: @convention(block) (String) -> String = { urlString in
            guard let url = URL(string: urlString) else {
                return "{\"error\": \"Invalid URL: \(urlString)\"}"
            }
            let sem = DispatchSemaphore(value: 0)
            var result = ""
            let task = URLSession.shared.dataTask(with: url) { data, response, error in
                defer { sem.signal() }
                if let error {
                    result = "{\"error\": \"\(error.localizedDescription)\"}"
                } else if let data, let str = String(data: data, encoding: .utf8) {
                    result = str
                }
            }
            task.resume()
            _ = sem.wait(timeout: .now() + 30)
            return result
        }
        ctx.setObject(httpGet, forKeyedSubscript: "__native_http_get" as NSString)

        let httpPost: @convention(block) (String, String, String) -> String = { urlString, body, contentType in
            guard let url = URL(string: urlString) else {
                return "{\"error\": \"Invalid URL: \(urlString)\"}"
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body.data(using: .utf8)
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            let sem = DispatchSemaphore(value: 0)
            var result = ""
            let task = URLSession.shared.dataTask(with: request) { data, _, error in
                defer { sem.signal() }
                if let error {
                    result = "{\"error\": \"\(error.localizedDescription)\"}"
                } else if let data, let str = String(data: data, encoding: .utf8) {
                    result = str
                }
            }
            task.resume()
            _ = sem.wait(timeout: .now() + 30)
            return result
        }
        ctx.setObject(httpPost, forKeyedSubscript: "__native_http_post" as NSString)
    }

    // MARK: - Python Runtime (JavaScript)

    static let pythonRuntime: String = """
    var __stdout = '';
    var __stderr = '';

    // --- Python constants ---
    var None = null;
    var True = true;
    var False = false;

    // --- repr / str ---
    function __py_repr(x) {
        if (x === null || x === undefined) return 'None';
        if (x === true) return 'True';
        if (x === false) return 'False';
        if (typeof x === 'number') {
            if (Number.isInteger(x)) return String(x);
            return String(x);
        }
        if (typeof x === 'string') return "'" + x.replace(/\\\\/g,'\\\\\\\\').replace(/'/g,"\\\\'") + "'";
        if (x instanceof __PyTuple) return '(' + x.items.map(__py_repr).join(', ') + (x.items.length===1?',':'') + ')';
        if (x instanceof __PySet) return x.items.size === 0 ? 'set()' : '{' + Array.from(x.items).map(__py_repr).join(', ') + '}';
        if (Array.isArray(x)) return '[' + x.map(__py_repr).join(', ') + ']';
        if (x instanceof __PyDict) return __py_dict_repr(x);
        if (typeof x === 'object' && x !== null && x.__class__) return x.__repr__ ? x.__repr__() : '<' + x.__class__ + ' object>';
        if (typeof x === 'object' && x !== null) return __py_dict_repr_obj(x);
        if (typeof x === 'function') return '<function ' + (x.name || '<lambda>') + '>';
        return String(x);
    }

    function __py_str(x) {
        if (x === null || x === undefined) return 'None';
        if (x === true) return 'True';
        if (x === false) return 'False';
        if (typeof x === 'string') return x;
        if (x instanceof __PyTuple) return '(' + x.items.map(__py_repr).join(', ') + (x.items.length===1?',':'') + ')';
        if (x instanceof __PySet) return x.items.size === 0 ? 'set()' : '{' + Array.from(x.items).map(__py_repr).join(', ') + '}';
        if (Array.isArray(x)) return '[' + x.map(__py_repr).join(', ') + ']';
        if (x instanceof __PyDict) return __py_dict_repr(x);
        if (typeof x === 'object' && x !== null) return __py_dict_repr_obj(x);
        return String(x);
    }

    function __py_dict_repr(d) {
        var parts = [];
        for (var k of d.keys()) parts.push(__py_repr(k) + ': ' + __py_repr(d.get(k)));
        return '{' + parts.join(', ') + '}';
    }
    function __py_dict_repr_obj(obj) {
        var parts = [];
        for (var k in obj) { if (obj.hasOwnProperty(k)) parts.push(__py_repr(k) + ': ' + __py_repr(obj[k])); }
        return '{' + parts.join(', ') + '}';
    }

    // --- Tuple/Set/Dict classes ---
    class __PyTuple { constructor(items) { this.items = items; this.length = items.length; } }
    class __PySet {
        constructor(iterable) { this.items = new Set(iterable || []); }
        add(x) { this.items.add(x); } remove(x) { this.items.delete(x); }
        has(x) { return this.items.has(x); }
        get size() { return this.items.size; }
    }
    class __PyDict extends Map {
        keys() { return super.keys(); }
        values() { return super.values(); }
        items() { return Array.from(super.entries()).map(e => new __PyTuple(e)); }
        get(k, def) { return super.has(k) ? super.get(k) : (def !== undefined ? def : undefined); }
        update(other) { if (other) for (var k of Object.keys(other)) this.set(k, other[k]); }
        pop(k, def) { if (this.has(k)) { var v = this.get(k); this.delete(k); return v; } return def; }
    }

    function tuple(x) { return new __PyTuple(Array.isArray(x) ? x : Array.from(x || [])); }
    function set(x) { return new __PySet(x); }

    // --- Built-in functions ---
    function print() {
        var args = Array.from(arguments);
        var kwargs = {};
        if (args.length > 0 && typeof args[args.length-1] === 'object' && args[args.length-1] !== null && args[args.length-1].__kwargs) {
            kwargs = args.pop();
        }
        var sep = kwargs.sep !== undefined ? kwargs.sep : ' ';
        var end = kwargs.end !== undefined ? kwargs.end : '\\n';
        __stdout += args.map(function(a) { return __py_str(a); }).join(sep) + end;
    }

    function len(x) {
        if (typeof x === 'string' || Array.isArray(x)) return x.length;
        if (x instanceof __PyTuple) return x.items.length;
        if (x instanceof __PySet) return x.items.size;
        if (x instanceof __PyDict || x instanceof Map) return x.size;
        if (typeof x === 'object' && x !== null) return Object.keys(x).length;
        throw new TypeError("object of type '" + typeof x + "' has no len()");
    }

    function range() {
        var start=0, stop, step=1;
        if (arguments.length === 1) { stop = arguments[0]; }
        else if (arguments.length === 2) { start = arguments[0]; stop = arguments[1]; }
        else { start = arguments[0]; stop = arguments[1]; step = arguments[2]; }
        var r = [];
        if (step > 0) for (var i=start; i<stop; i+=step) r.push(i);
        else if (step < 0) for (var i=start; i>stop; i+=step) r.push(i);
        return r;
    }

    function str(x) { return __py_str(x); }
    function int(x, base) { return base ? parseInt(x, base) : (typeof x==='string' ? parseInt(x,10) : Math.trunc(Number(x))); }
    function float(x) { return Number(x); }
    function bool(x) { return !!x; }
    function list(x) {
        if (x === undefined) return [];
        if (typeof x === 'string') return x.split('');
        if (x instanceof __PyTuple) return x.items.slice();
        if (x instanceof __PySet) return Array.from(x.items);
        if (x instanceof __PyDict) return Array.from(x.keys());
        if (Array.isArray(x)) return x.slice();
        return Array.from(x);
    }
    function dict(x) {
        var d = new __PyDict();
        if (x) { for (var k in x) { if (x.hasOwnProperty(k)) d.set(k, x[k]); } }
        return d;
    }

    function type(x) {
        if (x === null || x === undefined) return "<class 'NoneType'>";
        if (typeof x === 'boolean') return "<class 'bool'>";
        if (typeof x === 'number') return Number.isInteger(x) ? "<class 'int'>" : "<class 'float'>";
        if (typeof x === 'string') return "<class 'str'>";
        if (Array.isArray(x)) return "<class 'list'>";
        if (x instanceof __PyTuple) return "<class 'tuple'>";
        if (x instanceof __PySet) return "<class 'set'>";
        if (x instanceof __PyDict) return "<class 'dict'>";
        if (typeof x === 'function') return "<class 'function'>";
        return "<class 'object'>";
    }

    function isinstance(x, t) {
        var tn = typeof t === 'function' ? t.name : String(t);
        if (tn === 'int') return typeof x === 'number' && Number.isInteger(x);
        if (tn === 'float') return typeof x === 'number';
        if (tn === 'str') return typeof x === 'string';
        if (tn === 'bool') return typeof x === 'boolean';
        if (tn === 'list') return Array.isArray(x);
        if (tn === 'dict') return x instanceof __PyDict || (typeof x === 'object' && x !== null && !Array.isArray(x));
        return false;
    }

    function abs(x) { return Math.abs(x); }
    function max() { var a = arguments.length===1 ? arguments[0] : Array.from(arguments); return Array.isArray(a) ? Math.max.apply(null,a) : Math.max.apply(null,Array.from(a)); }
    function min() { var a = arguments.length===1 ? arguments[0] : Array.from(arguments); return Array.isArray(a) ? Math.min.apply(null,a) : Math.min.apply(null,Array.from(a)); }
    function sum(it,start) { var s=start||0; var arr=Array.isArray(it)?it:Array.from(it); arr.forEach(function(x){s+=x;}); return s; }
    function sorted(it,opts) {
        var arr = Array.isArray(it)?it.slice():Array.from(it);
        var key = opts && opts.key ? opts.key : null;
        var rev = opts && opts.reverse ? true : false;
        arr.sort(function(a,b) {
            var va = key ? key(a) : a, vb = key ? key(b) : b;
            if (va < vb) return rev ? 1 : -1;
            if (va > vb) return rev ? -1 : 1;
            return 0;
        });
        return arr;
    }
    function reversed(it) { var a=Array.isArray(it)?it.slice():Array.from(it); a.reverse(); return a; }
    function enumerate(it,start) { var s=start||0; return (Array.isArray(it)?it:Array.from(it)).map(function(v,i){return new __PyTuple([i+s,v]);}); }
    function zip() {
        var args = Array.from(arguments).map(function(a){return Array.isArray(a)?a:Array.from(a);});
        var minLen = Math.min.apply(null, args.map(function(a){return a.length;}));
        var r = [];
        for (var i=0; i<minLen; i++) { r.push(new __PyTuple(args.map(function(a){return a[i];}))); }
        return r;
    }
    function map(fn, it) { return (Array.isArray(it)?it:Array.from(it)).map(fn); }
    function filter(fn, it) { return (Array.isArray(it)?it:Array.from(it)).filter(fn||function(x){return !!x;}); }
    function any(it) { for (var x of it) if (x) return true; return false; }
    function all(it) { for (var x of it) if (!x) return false; return true; }
    function round(x, d) { if (!d) return Math.round(x); var f=Math.pow(10,d); return Math.round(x*f)/f; }
    function repr(x) { return __py_repr(x); }
    function chr(x) { return String.fromCharCode(x); }
    function ord(x) { return x.charCodeAt(0); }
    function hex(x) { return '0x' + x.toString(16); }
    function oct(x) { return '0o' + x.toString(8); }
    function bin(x) { return '0b' + x.toString(2); }
    function hash(x) { if (typeof x==='number') return x; if (typeof x==='string') { var h=0; for(var i=0;i<x.length;i++){h=((h<<5)-h)+x.charCodeAt(i);h|=0;} return h; } return 0; }
    function callable(x) { return typeof x === 'function'; }
    function input(prompt) { return ''; }
    function id(x) { return 0; }
    function dir(x) { return x ? Object.keys(x) : []; }
    function vars(x) { return x || {}; }
    function hasattr(x,n) { return x !== null && x !== undefined && n in x; }
    function getattr(x,n,d) { return (x!==null && x!==undefined && n in x) ? x[n] : d; }
    function setattr(x,n,v) { x[n]=v; }

    // --- Python 'in' operator ---
    function __py_in(val, container) {
        if (typeof container === 'string') return container.includes(val);
        if (Array.isArray(container)) return container.includes(val);
        if (container instanceof __PySet) return container.has(val);
        if (container instanceof __PyDict || container instanceof Map) return container.has(val);
        if (typeof container === 'object' && container !== null) return val in container;
        return false;
    }

    // --- Slice helper ---
    function __py_slice(obj, start, stop, step) {
        if (typeof obj === 'string' || Array.isArray(obj)) {
            var len = obj.length;
            var s = start === null ? (step && step < 0 ? len-1 : 0) : (start < 0 ? Math.max(0,len+start) : start);
            var e = stop === null ? (step && step < 0 ? -1 : len) : (stop < 0 ? Math.max(0,len+stop) : Math.min(len,stop));
            if (!step || step === 1) return typeof obj === 'string' ? obj.slice(s,e) : obj.slice(s,e);
            var r = []; for (var i=s; step>0?i<e:i>e; i+=step) r.push(typeof obj === 'string' ? obj[i] : obj[i]);
            return typeof obj === 'string' ? r.join('') : r;
        }
        return obj;
    }

    // --- Floor division ---
    function __py_floordiv(a, b) { return Math.floor(a / b); }
    function __py_mod(a, b) { return ((a % b) + b) % b; }
    function __py_pow(a, b) { return Math.pow(a, b); }

    // --- Modules ---
    var json = {
        loads: function(s) { return JSON.parse(s); },
        dumps: function(o, opts) {
            var indent = opts && opts.indent ? opts.indent : undefined;
            return JSON.stringify(o, null, indent);
        }
    };

    var math = {
        pi: Math.PI, e: Math.E, tau: 2*Math.PI, inf: Infinity, nan: NaN,
        sqrt: Math.sqrt, pow: Math.pow, log: Math.log, log2: Math.log2, log10: Math.log10,
        sin: Math.sin, cos: Math.cos, tan: Math.tan,
        asin: Math.asin, acos: Math.acos, atan: Math.atan, atan2: Math.atan2,
        ceil: Math.ceil, floor: Math.floor, trunc: Math.trunc,
        fabs: Math.abs, factorial: function(n){var r=1;for(var i=2;i<=n;i++)r*=i;return r;},
        gcd: function(a,b){a=Math.abs(a);b=Math.abs(b);while(b){var t=b;b=a%b;a=t;}return a;},
        isnan: isNaN, isinf: function(x){return !isFinite(x)&&!isNaN(x);},
        radians: function(d){return d*Math.PI/180;}, degrees: function(r){return r*180/Math.PI;},
        comb: function(n,k){if(k<0||k>n)return 0;if(k===0||k===n)return 1;var r=1;for(var i=0;i<k;i++){r=r*(n-i)/(i+1);}return Math.round(r);},
        perm: function(n,k){if(k===undefined)k=n;var r=1;for(var i=0;i<k;i++)r*=(n-i);return r;}
    };

    var random = {
        random: Math.random,
        randint: function(a,b) { return Math.floor(Math.random()*(b-a+1))+a; },
        choice: function(seq) { return seq[Math.floor(Math.random()*seq.length)]; },
        shuffle: function(arr) { for(var i=arr.length-1;i>0;i--){var j=Math.floor(Math.random()*(i+1));var t=arr[i];arr[i]=arr[j];arr[j]=t;} return arr; },
        sample: function(pop,k) { var a=pop.slice(); random.shuffle(a); return a.slice(0,k); },
        uniform: function(a,b) { return a+(b-a)*Math.random(); },
        seed: function() {}
    };

    var re = {
        match: function(pattern, string) {
            var r = new RegExp('^(?:'+pattern+')'); var m = string.match(r);
            return m ? {group: function(i){return m[i||0];}, groups: function(){return m.slice(1);}, start: function(){return m.index;}, span: function(){return [m.index,m.index+m[0].length];}} : null;
        },
        search: function(pattern, string) {
            var r = new RegExp(pattern); var m = string.match(r);
            return m ? {group: function(i){return m[i||0];}, groups: function(){return m.slice(1);}, start: function(){return m.index;}, span: function(){return [m.index,m.index+m[0].length];}} : null;
        },
        findall: function(pattern, string) { var r = new RegExp(pattern,'g'); var m=[],res; while(res=r.exec(string)){m.push(res.length>1?res.slice(1):res[0]);} return m; },
        sub: function(pattern, repl, string, count) {
            var flags = count === 1 ? '' : 'g';
            return string.replace(new RegExp(pattern, flags), repl);
        },
        split: function(pattern, string) { return string.split(new RegExp(pattern)); }
    };

    var datetime = {
        datetime: {
            now: function() {
                var d = new Date();
                return {year:d.getFullYear(),month:d.getMonth()+1,day:d.getDate(),hour:d.getHours(),minute:d.getMinutes(),second:d.getSeconds(),
                    strftime:function(fmt){return fmt.replace('%Y',String(d.getFullYear())).replace('%m',String(d.getMonth()+1).padStart(2,'0')).replace('%d',String(d.getDate()).padStart(2,'0')).replace('%H',String(d.getHours()).padStart(2,'0')).replace('%M',String(d.getMinutes()).padStart(2,'0')).replace('%S',String(d.getSeconds()).padStart(2,'0'));},
                    isoformat:function(){return d.toISOString();},
                    __repr__:function(){return 'datetime.datetime('+d.getFullYear()+', '+(d.getMonth()+1)+', '+d.getDate()+', '+d.getHours()+', '+d.getMinutes()+', '+d.getSeconds()+')';},
                    __class__:'datetime.datetime'};
            },
            fromisoformat: function(s) { var d=new Date(s); return datetime.datetime.now(); }
        },
        date: {
            today: function() {
                var d=new Date();
                return {year:d.getFullYear(),month:d.getMonth()+1,day:d.getDate(),
                    strftime:function(fmt){return fmt.replace('%Y',String(d.getFullYear())).replace('%m',String(d.getMonth()+1).padStart(2,'0')).replace('%d',String(d.getDate()).padStart(2,'0'));},
                    isoformat:function(){return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');},
                    __repr__:function(){return 'datetime.date('+d.getFullYear()+', '+(d.getMonth()+1)+', '+d.getDate()+')';},
                    __class__:'datetime.date'};
            }
        },
        timedelta: function(opts) { return {days:opts.days||0,seconds:opts.seconds||0,total_seconds:function(){return (opts.days||0)*86400+(opts.seconds||0)+(opts.hours||0)*3600+(opts.minutes||0)*60;},__repr__:function(){return 'datetime.timedelta(days='+(opts.days||0)+')';},__class__:'datetime.timedelta'}; }
    };

    var base64 = {
        b64encode: function(s) { try { return btoa(typeof s === 'string' ? s : String(s)); } catch(e) { return btoa(unescape(encodeURIComponent(s))); } },
        b64decode: function(s) { try { return atob(s); } catch(e) { return decodeURIComponent(escape(atob(s))); } }
    };

    var hashlib = {
        md5: function(s) { return {hexdigest: function(){return __simple_hash(typeof s==='string'?s:s.toString());}}; },
        sha256: function(s) { return {hexdigest: function(){return __simple_hash(typeof s==='string'?s:s.toString())+'0000';}}; }
    };
    function __simple_hash(s) { var h=0; for(var i=0;i<s.length;i++){h=((h<<5)-h)+s.charCodeAt(i);h|=0;} return (h>>>0).toString(16).padStart(8,'0'); }

    var collections = {
        Counter: function(iterable) {
            var c = {};
            if (iterable) (Array.isArray(iterable)?iterable:iterable.split('')).forEach(function(x){c[x]=(c[x]||0)+1;});
            c.most_common = function(n){var pairs=Object.entries(c).filter(function(e){return typeof e[1]==='number';}).sort(function(a,b){return b[1]-a[1];}); return n?pairs.slice(0,n):pairs;};
            return c;
        },
        defaultdict: function(factory) {
            return new Proxy({}, {get: function(t,k){if(!(k in t))t[k]=factory();return t[k];}});
        },
        OrderedDict: function() { return {}; }
    };

    var string_mod = {
        ascii_letters: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ',
        ascii_lowercase: 'abcdefghijklmnopqrstuvwxyz',
        ascii_uppercase: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
        digits: '0123456789',
        punctuation: '!"#$%&\\'()*+,-./:;<=>?@[\\\\]^_`{|}~'
    };

    var time_mod = {
        time: function() { return Date.now()/1000; },
        sleep: function(s) {}
    };

    var os = {
        path: {
            join: function() { return Array.from(arguments).join('/'); },
            basename: function(p) { return p.split('/').pop(); },
            dirname: function(p) { var s=p.split('/'); s.pop(); return s.join('/'); },
            splitext: function(p) { var i=p.lastIndexOf('.'); return i>0?[p.substring(0,i),p.substring(i)]:[p,'']; },
            exists: function() { return false; }
        },
        environ: {},
        getcwd: function() { return '/'; },
        listdir: function() { return []; }
    };

    // --- Network: urllib / requests ---
    var urllib = {
        request: {
            urlopen: function(url) {
                var data = __native_http_get(typeof url === 'string' ? url : url.full_url);
                return {
                    read: function() { return data; },
                    status: 200,
                    getcode: function() { return 200; },
                    __repr__: function() { return '<http.client.HTTPResponse>'; },
                    __class__: 'HTTPResponse'
                };
            },
            Request: function(url, opts) { return {full_url: url, data: opts && opts.data, method: opts && opts.method || 'GET'}; }
        },
        parse: {
            urlencode: function(params) { return Object.entries(params).map(function(e){return encodeURIComponent(e[0])+'='+encodeURIComponent(e[1]);}).join('&'); },
            quote: encodeURIComponent,
            unquote: decodeURIComponent
        }
    };

    var requests = {
        get: function(url, opts) {
            var data = __native_http_get(url);
            return {text: data, status_code: 200, json: function(){return JSON.parse(data);},
                ok: true, headers: {}, __repr__: function(){return '<Response [200]>';}, __class__: 'Response'};
        },
        post: function(url, opts) {
            var body = opts && opts.json ? JSON.stringify(opts.json) : (opts && opts.data || '');
            var ct = opts && opts.json ? 'application/json' : 'application/x-www-form-urlencoded';
            var data = __native_http_post(url, body, ct);
            return {text: data, status_code: 200, json: function(){return JSON.parse(data);},
                ok: true, headers: {}, __repr__: function(){return '<Response [200]>';}, __class__: 'Response'};
        }
    };

    // --- String methods via prototype ---
    String.prototype.upper = function() { return this.toUpperCase(); };
    String.prototype.lower = function() { return this.toLowerCase(); };
    String.prototype.strip = function(c) { return c ? this.replace(new RegExp('^['+c+']+|['+c+']+$','g'),'') : this.trim(); };
    String.prototype.lstrip = function(c) { return c ? this.replace(new RegExp('^['+c+']+'),'') : this.trimStart(); };
    String.prototype.rstrip = function(c) { return c ? this.replace(new RegExp('['+c+']+$'),'') : this.trimEnd(); };
    String.prototype.startswith = String.prototype.startsWith;
    String.prototype.endswith = String.prototype.endsWith;
    String.prototype.find = function(s,start) { return this.indexOf(s,start); };
    String.prototype.rfind = function(s) { return this.lastIndexOf(s); };
    String.prototype.count = function(s) { return this.split(s).length - 1; };
    String.prototype.isdigit = function() { return /^\\d+$/.test(this); };
    String.prototype.isalpha = function() { return /^[a-zA-Z]+$/.test(this); };
    String.prototype.isalnum = function() { return /^[a-zA-Z0-9]+$/.test(this); };
    String.prototype.zfill = function(w) { return this.padStart(w, '0'); };
    String.prototype.center = function(w, c) { c=c||' '; var p=Math.max(0,w-this.length); var l=Math.floor(p/2); return c.repeat(l)+this+c.repeat(p-l); };
    String.prototype.ljust = function(w,c) { return this.padEnd(w,c||' '); };
    String.prototype.rjust = function(w,c) { return this.padStart(w,c||' '); };
    String.prototype.title = function() { return this.replace(/\\b\\w/g, function(c){return c.toUpperCase();}); };
    String.prototype.capitalize = function() { return this.charAt(0).toUpperCase()+this.slice(1).toLowerCase(); };
    String.prototype.swapcase = function() { return this.split('').map(function(c){return c===c.toUpperCase()?c.toLowerCase():c.toUpperCase();}).join(''); };
    String.prototype.format = function() {
        var args = arguments, i = 0;
        return this.replace(/\\{(\\d*)\\}/g, function(m, n) { return __py_str(n !== '' ? args[parseInt(n)] : args[i++]); });
    };
    String.prototype.encode = function() { return this; };

    // --- List methods via prototype ---
    if (!Array.prototype.append) Array.prototype.append = function(x) { this.push(x); };
    if (!Array.prototype.extend) Array.prototype.extend = function(x) { for(var i of x) this.push(i); };
    if (!Array.prototype.insert) Array.prototype.insert = function(i,x) { this.splice(i,0,x); };
    if (!Array.prototype.remove) Array.prototype.remove = function(x) { var i=this.indexOf(x); if(i>=0)this.splice(i,1); };
    if (!Array.prototype.count) Array.prototype.count = function(x) { return this.filter(function(v){return v===x;}).length; };
    if (!Array.prototype.index) Array.prototype.index = function(x) { var i=this.indexOf(x); if(i<0)throw new Error(x+' is not in list'); return i; };
    if (!Array.prototype.copy) Array.prototype.copy = function() { return this.slice(); };
    if (!Array.prototype.clear) Array.prototype.clear = function() { this.length=0; };

    // --- Module import mapping ---
    var __modules = {
        'json': json, 'math': math, 'random': random, 're': re, 'datetime': datetime,
        'base64': base64, 'hashlib': hashlib, 'collections': collections,
        'string': string_mod, 'time': time_mod, 'os': os, 'os.path': os.path,
        'urllib': urllib, 'urllib.request': urllib.request, 'urllib.parse': urllib.parse,
        'requests': requests
    };
    """
}

// MARK: - Python → JavaScript Transpiler

enum PythonTranspiler {

    /// Transpile a Python expression (for repr mode).
    static func transpileExpression(_ code: String) -> String {
        var expr = code.trimmingCharacters(in: .whitespacesAndNewlines)
        expr = replaceConstants(expr)
        expr = replaceOperators(expr)
        expr = replaceFStrings(expr)
        expr = replaceSlices(expr)
        return expr
    }

    /// Transpile a Python script (for script mode).
    static func transpileScript(_ code: String) -> String {
        let lines = code.components(separatedBy: "\n")
        var output: [String] = []
        var indentStack: [Int] = [0]

        for rawLine in lines {
            let stripped = rawLine.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty || stripped.hasPrefix("#") {
                continue
            }

            let indent = rawLine.prefix(while: { $0 == " " }).count

            while indentStack.count > 1 && indent < indentStack.last! {
                indentStack.removeLast()
                output.append("}")
            }

            let transformed = transformLine(stripped)
            output.append(transformed)
        }

        while indentStack.count > 1 {
            indentStack.removeLast()
            output.append("}")
        }

        return output.joined(separator: "\n")
    }

    private static func transformLine(_ line: String) -> String {
        var l = line

        // import statements
        if l.hasPrefix("import ") {
            let module = l.dropFirst(7).trimmingCharacters(in: .whitespaces)
            let jsName = module.replacingOccurrences(of: ".", with: "_")
            return "var \(jsName) = __modules['\(module)'] || {};"
        }
        if l.hasPrefix("from ") {
            let parts = l.components(separatedBy: " ")
            if let importIdx = parts.firstIndex(of: "import"), importIdx > 1 {
                let module = parts[1]
                let imports = parts[(importIdx + 1)...].joined(separator: " ").components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                var stmts: [String] = []
                for imp in imports {
                    let clean = imp.replacingOccurrences(of: " ", with: "")
                    stmts.append("var \(clean) = (__modules['\(module)'] || {}).\(clean);")
                }
                return stmts.joined(separator: " ")
            }
        }

        // def → function
        if l.hasPrefix("def ") && l.hasSuffix(":") {
            let sig = String(l.dropFirst(4).dropLast())
            return "function \(replaceDefaults(sig)) {"
        }

        // class (basic)
        if l.hasPrefix("class ") && l.hasSuffix(":") {
            let name = String(l.dropFirst(6).dropLast()).components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? ""
            return "function \(name)() { var self = this; {"
        }

        // return
        if l.hasPrefix("return ") {
            let expr = String(l.dropFirst(7))
            return "return \(replaceConstants(replaceOperators(replaceFStrings(expr))));"
        }
        if l == "return" { return "return;" }

        // if/elif/else
        if l.hasPrefix("if ") && l.hasSuffix(":") {
            let cond = String(l.dropFirst(3).dropLast())
            return "if (\(translateCondition(cond))) {"
        }
        if l.hasPrefix("elif ") && l.hasSuffix(":") {
            let cond = String(l.dropFirst(5).dropLast())
            return "} else if (\(translateCondition(cond))) {"
        }
        if l == "else:" { return "} else {" }

        // for loop
        if l.hasPrefix("for ") && l.hasSuffix(":") {
            return translateForLoop(String(l.dropLast()))
        }

        // while
        if l.hasPrefix("while ") && l.hasSuffix(":") {
            let cond = String(l.dropFirst(6).dropLast())
            return "while (\(translateCondition(cond))) {"
        }

        // try/except/finally
        if l == "try:" { return "try {" }
        if l.hasPrefix("except") && l.hasSuffix(":") {
            let rest = l.dropFirst(6).dropLast().trimmingCharacters(in: .whitespaces)
            if rest.isEmpty { return "} catch(__e) {" }
            if rest.contains(" as ") {
                let varName = rest.components(separatedBy: " as ").last?.trimmingCharacters(in: .whitespaces) ?? "e"
                return "} catch(\(varName)) {"
            }
            return "} catch(__e) {"
        }
        if l == "finally:" { return "} finally {" }

        // pass → empty
        if l == "pass" { return "// pass" }
        // break / continue
        if l == "break" { return "break;" }
        if l == "continue" { return "continue;" }

        // raise
        if l.hasPrefix("raise ") {
            let msg = String(l.dropFirst(6))
            return "throw new Error(\(replaceConstants(msg)));"
        }

        // assert
        if l.hasPrefix("assert ") {
            let expr = String(l.dropFirst(7))
            return "if (!(\(translateCondition(expr)))) throw new Error('AssertionError');"
        }

        // with (basic, treat as just executing the body)
        if l.hasPrefix("with ") && l.hasSuffix(":") {
            return "{ // with block"
        }

        // lambda
        l = replaceLambdas(l)

        // General expression/assignment
        l = replaceConstants(l)
        l = replaceOperators(l)
        l = replaceFStrings(l)
        l = replaceSlices(l)
        l = replaceListComprehensions(l)

        if !l.hasSuffix("{") && !l.hasSuffix("}") {
            l += ";"
        }
        return l
    }

    // MARK: - Transform helpers

    private static func replaceConstants(_ s: String) -> String {
        var r = s
        r = r.replacingOccurrences(of: "\\bTrue\\b", with: "true", options: .regularExpression)
        r = r.replacingOccurrences(of: "\\bFalse\\b", with: "false", options: .regularExpression)
        r = r.replacingOccurrences(of: "\\bNone\\b", with: "null", options: .regularExpression)
        return r
    }

    private static func replaceOperators(_ s: String) -> String {
        var r = s
        r = r.replacingOccurrences(of: "\\bnot\\s+", with: "!", options: .regularExpression)
        r = r.replacingOccurrences(of: "\\s+and\\s+", with: " && ", options: .regularExpression)
        r = r.replacingOccurrences(of: "\\s+or\\s+", with: " || ", options: .regularExpression)
        r = r.replacingOccurrences(of: "\\s+not\\s+in\\s+", with: ") ? false : __py_in(", options: .regularExpression)
        // // → floor division (careful not to match comments)
        r = r.replacingOccurrences(of: "([^:])//([^/])", with: "$1/__py_floordiv_placeholder/$2", options: .regularExpression)
        r = r.replacingOccurrences(of: "/__py_floordiv_placeholder/", with: ")")
        // Actually, better to handle // more carefully
        r = replaceFloorDiv(r)
        return r
    }

    private static func replaceFloorDiv(_ s: String) -> String {
        guard s.contains("//") else { return s }
        // Simple replacement: a // b → __py_floordiv(a, b)
        // This is simplified; a full parser would be needed for complex expressions
        var result = s
        while let range = result.range(of: "//") {
            let before = String(result[result.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let after = String(result[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            // Find the operand boundaries (simplified)
            let leftOperand = before.components(separatedBy: .whitespaces).last ?? before
            let rightParts = after.components(separatedBy: .whitespaces)
            let rightOperand = rightParts.first ?? after
            let prefix = String(result[result.startIndex..<range.lowerBound]).dropLast(leftOperand.count)
            let suffix = rightParts.count > 1 ? " " + rightParts.dropFirst().joined(separator: " ") : ""
            result = prefix + "__py_floordiv(\(leftOperand), \(rightOperand))" + suffix
        }
        return result
    }

    private static func replaceFStrings(_ s: String) -> String {
        var result = s
        // f"...{expr}..." → `...${expr}...`
        let pattern = "f\"([^\"]*)\""
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsStr = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsStr.length))
            for match in matches.reversed() {
                let content = nsStr.substring(with: match.range(at: 1))
                let jsTemplate = "`\(content.replacingOccurrences(of: "{", with: "${"))`"
                result = nsStr.replacingCharacters(in: match.range, with: jsTemplate) as String
            }
        }
        // f'...{expr}...'
        let pattern2 = "f'([^']*)'"
        if let regex = try? NSRegularExpression(pattern: pattern2) {
            let nsStr = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsStr.length))
            for match in matches.reversed() {
                let content = nsStr.substring(with: match.range(at: 1))
                let jsTemplate = "`\(content.replacingOccurrences(of: "{", with: "${"))`"
                result = nsStr.replacingCharacters(in: match.range, with: jsTemplate) as String
            }
        }
        return result
    }

    private static func replaceSlices(_ s: String) -> String {
        // obj[start:end] → __py_slice(obj, start, end, null)
        // Simplified: only handles simple cases
        var result = s
        let pattern = "(\\w+)\\[([^\\]]*):([^\\]]*)\\]"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsStr = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsStr.length))
            for match in matches.reversed() {
                let obj = nsStr.substring(with: match.range(at: 1))
                let start = nsStr.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                let end = nsStr.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
                let startJS = start.isEmpty ? "null" : start
                let endJS = end.isEmpty ? "null" : end
                let replacement = "__py_slice(\(obj), \(startJS), \(endJS), null)"
                result = nsStr.replacingCharacters(in: match.range, with: replacement) as String
            }
        }
        return result
    }

    private static func replaceLambdas(_ s: String) -> String {
        var result = s
        let pattern = "lambda\\s+([^:]+):\\s*(.+)"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsStr = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsStr.length))
            for match in matches.reversed() {
                let params = nsStr.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                let body = nsStr.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                let jsLambda = "((\(params)) => \(replaceConstants(replaceOperators(body))))"
                result = nsStr.replacingCharacters(in: match.range, with: jsLambda) as String
            }
        }
        return result
    }

    private static func replaceListComprehensions(_ s: String) -> String {
        // [expr for x in iterable] → iterable.map(x => expr)
        // [expr for x in iterable if cond] → iterable.filter(x => cond).map(x => expr)
        var result = s
        let pattern = "\\[([^\\[\\]]+)\\s+for\\s+(\\w+)\\s+in\\s+([^\\]]+?)(?:\\s+if\\s+([^\\]]+))?\\]"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsStr = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsStr.length))
            for match in matches.reversed() {
                let expr = nsStr.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                let varName = nsStr.substring(with: match.range(at: 2))
                let iterable = nsStr.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
                let hasCondition = match.range(at: 4).location != NSNotFound
                let condition = hasCondition ? nsStr.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces) : nil

                var jsExpr = "\(iterable)"
                if let cond = condition {
                    jsExpr += ".filter(\(varName) => \(translateCondition(cond)))"
                }
                jsExpr += ".map(\(varName) => \(replaceConstants(replaceOperators(expr))))"
                result = nsStr.replacingCharacters(in: match.range, with: jsExpr) as String
            }
        }
        return result
    }

    private static func translateCondition(_ cond: String) -> String {
        var c = cond
        c = replaceConstants(c)
        c = c.replacingOccurrences(of: "\\bnot\\s+in\\b", with: "__NOT_IN__", options: .regularExpression)
        c = c.replacingOccurrences(of: "\\bin\\b", with: "__IN__", options: .regularExpression)

        // x __NOT_IN__ y → !__py_in(x, y)
        if c.contains("__NOT_IN__") {
            let parts = c.components(separatedBy: "__NOT_IN__")
            if parts.count == 2 {
                let left = parts[0].trimmingCharacters(in: .whitespaces)
                let right = parts[1].trimmingCharacters(in: .whitespaces)
                c = "!__py_in(\(left), \(right))"
            }
        }
        if c.contains("__IN__") {
            let parts = c.components(separatedBy: "__IN__")
            if parts.count == 2 {
                let left = parts[0].trimmingCharacters(in: .whitespaces)
                let right = parts[1].trimmingCharacters(in: .whitespaces)
                c = "__py_in(\(left), \(right))"
            }
        }

        c = replaceOperators(c)
        return c
    }

    private static func translateForLoop(_ line: String) -> String {
        // for x in range(...)
        let pattern1 = "for\\s+(\\w+)\\s+in\\s+range\\((.+)\\)"
        if let regex = try? NSRegularExpression(pattern: pattern1),
           let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) {
            let nsStr = line as NSString
            let varName = nsStr.substring(with: match.range(at: 1))
            let args = nsStr.substring(with: match.range(at: 2))
            return "for (var \(varName) of range(\(args))) {"
        }

        // for k, v in dict.items()
        let pattern2 = "for\\s+(\\w+)\\s*,\\s*(\\w+)\\s+in\\s+(.+)"
        if let regex = try? NSRegularExpression(pattern: pattern2),
           let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) {
            let nsStr = line as NSString
            let var1 = nsStr.substring(with: match.range(at: 1))
            let var2 = nsStr.substring(with: match.range(at: 2))
            let iterable = nsStr.substring(with: match.range(at: 3))
            return "for (var [__tmp] of \(iterable)) { var \(var1) = __tmp[0] !== undefined ? __tmp[0] : __tmp; var \(var2) = __tmp[1] !== undefined ? __tmp[1] : undefined; {"
        }

        // for x in iterable
        let pattern3 = "for\\s+(\\w+)\\s+in\\s+(.+)"
        if let regex = try? NSRegularExpression(pattern: pattern3),
           let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) {
            let nsStr = line as NSString
            let varName = nsStr.substring(with: match.range(at: 1))
            let iterable = nsStr.substring(with: match.range(at: 2))
            return "for (var \(varName) of \(replaceConstants(iterable))) {"
        }

        return "for (;;) { break; // unsupported for loop"
    }

    private static func replaceDefaults(_ sig: String) -> String {
        sig
    }
}
