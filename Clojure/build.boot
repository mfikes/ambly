(set-env!
  :dependencies '[[org.clojure/clojure "1.6.0"]
                  [org.clojure/clojurescript "0.0-3030"]
                  [adzerk/boot-cljs "0.0-3308-0"]
                  [com.github.rickyclarkson/jmdns "3.4.2-r353-1"]
                  [ambly "1.0.0"]])

(require
 '[adzerk.boot-cljs :refer [cljs]]
 '[ambly.core :as ambly])

(deftask ambly []
  (task-options!
    repl {:eval '(do
                  (require '[cljs.repl :as repl]
                           '[ambly.core :as ambly])
                  (repl/repl (ambly/repl-env)))
         })
  (repl))
