Ambly
=======
ClojureScript REPL into embedded JavaScriptCore.

Running
=======

Currently, the embedded JavaScriptCore instance is hosted inside an iOS simulator instance. Ideally this will be revised to be hosted in a command-line OS X executable instead.

1. There is currently a hardcoded path in [line 62](https://github.com/mfikes/ambly/blob/master/ObjectiveC/Ambly%20Demo/Ambly%20Demo/JSContextManager.m#L62) of `JSContextManager.m` that will need to be revised to reflect where you have things checked out. Edit that first.
2. Open the Xcode project in the Ambly Demo directory and run it in the simulator.
3. In `ambly/Clojure` run `lein repl`
4. Then issue the following two forms

```clojure
(require
  '[cljs.repl :as repl]
  '[ambly.repl.jsc :as jsc])
```

```
(repl/repl* (jsc/repl-env)
  {:output-dir "out"
   :optimizations :none
   :cache-analysis true})
```

Then the REPL will be live:
```
To quit, type: :cljs/quit
ClojureScript:cljs.user> (+ 1 1)
2
```

For diagnostics, the log in Xcode is currently showing what the is being sent to JSC. For the above:
```
2015-02-03 14:05:48.752 Ambly Demo[5165:475166] cljs.core.pr_str.call(null,(function (){var ret__4579__auto__ = ((1) + (1));
cljs.core._STAR_3 = cljs.core._STAR_2;

cljs.core._STAR_2 = cljs.core._STAR_1;

cljs.core._STAR_1 = ret__4579__auto__;

return ret__4579__auto__;
})())
```
  

License
=======

Distributed under the Eclipse Public License, which is also used by ClojureScript.
