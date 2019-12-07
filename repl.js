cljs = {
  core: {
    pr_str: function(x) {
      if (typeof x === "number") {
        return "" + x;
      } else if (typeof x === "string") {
        return '"' + x + '"';
      } else {
        return "#'" + x.sym;
      }
    }
  },
  user: {}
};

cljs.core.Var = function(val, sym, _meta) {
  this.val = val;
  this.sym = sym;
  this._meta = _meta;
};

cljs.core.Symbol = function(ns, name, str, _hash, _meta) {
  this.ns = ns;
  this.name = name;
  this.str = str;
  this._hash = _hash;
  this._meta = _meta;
};

cljs.core.Symbol.prototype.toString = function() {
  return this.str;
};

cljs.core.Keyword = function(ns, name, fqn, _hash) {
  this.ns = ns;
  this.name = name;
  this.fqn = fqn;
  this._hash = _hash;
};

cljs.core.list = function cljs$core$list(var_args) {};
cljs.core.List = {};
cljs.core.List.EMPTY = null;

cljs.core.PersistentVector = function() {};

cljs.core.PersistentVector.EMPTY_NODE = {};

cljs.core.PersistentArrayMap = function() {};

cljs.core.PersistentHashMap = function() {};
cljs.core.PersistentHashMap.fromArrays = function(ks, vs) {};

cljs.core.truth_ = function cljs$core$truth_(x) {
  return x != null && x !== false;
};

var current_c;

cljs.core._STAR_print_fn_STAR_ = function(x) {
  current_c.write(x + "\1");
};

goog = {};
goog.isFunction = function (a){return"function"==goog.typeOf(a)};
goog.typeOf = function (a){var b=typeof a;if("object"==b)if(a){if(a instanceof Array)return"array";if(a instanceof Object)return b;var c=Object.prototype.toString.call(a);if("[object Window]"==c)return"object";if("[object Array]"==c||"number"==typeof a.length&&"undefined"!=typeof a.splice&&"undefined"!=typeof a.propertyIsEnumerable&&!a.propertyIsEnumerable("splice"))return"array";if("[object Function]"==c||"undefined"!=typeof a.call&&"undefined"!=typeof a.propertyIsEnumerable&&!a.propertyIsEnumerable("call"))return"function"}else return"null";else if("function"==b&&"undefined"==typeof a.call)return"object";return b};

var accum = "";
var evalme = false;

var server = require("net").createServer(function(c) {
  console.log("New REPL Connection");
  current_c = c;
  c.on("data", function(data) {
    //console.log(">" + data);
    if (data.startsWith("(function (){try{return cljs.core.pr_str")) {
      evalme = true;
    }
    if (data.endsWith("\0")) {
      if (evalme) {
        //console.log("evaluating: " + accum + data);
        try {
          c.write(
            JSON.stringify({ status: "success", value: eval(accum + data) })
          );
        } catch (e) {
          c.write(JSON.stringify({ status: "exception",
                                  value: ""+e,
                                 stacktrace: e.stack}));
        }
        accum = "";
        evalme = false;
        c.write("\0");
      } else if (data === ":cljs/quit") {
        c.end();
      } else {
        c.write(JSON.stringify({ status: "success", value: "true" }));
        accum = "";
        evalme = false;
        c.write("\0");
      }
    } else {
      accum = accum + data;
    }
  });
});

server.listen(53000);
print("Ready for REPL connections.")
