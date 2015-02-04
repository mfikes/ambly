Ambly
=======
ClojureScript REPL into embedded JavaScriptCore.

Running
=======

The embedded JavaScriptCore instance is hosted inside an iOS simulator instance.

1. Open the Xcode project in the Ambly Demo directory and run it in the simulator.
2. In `ambly/Clojure` run `lein repl`
3. Then issue the following two forms

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

License
=======

Distributed under the Eclipse Public License, which is also used by ClojureScript.
