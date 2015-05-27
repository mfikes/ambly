@ECHO OFF
lein trampoline run -m clojure.main -e "(require '[cljs.repl :as repl]) (require '[ambly.core :as ambly]) (repl/repl (ambly/repl-env))"
