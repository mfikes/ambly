(ns ambly.repl.jsc
  (:require [clojure.string :as string]
            [clojure.java.io :as io]
            [cljs.analyzer :as ana]
            [cljs.compiler :as comp]
            [cljs.repl :as repl]
            [cljs.closure :as closure]
            [clojure.data.json :as json])
  (:import java.net.Socket
           java.lang.StringBuilder
           [java.io File BufferedReader BufferedWriter]
           [java.lang ProcessBuilder ProcessBuilder$Redirect]))

(defn socket [host port]
  (let [socket (Socket. host port)
        in     (io/reader socket)
        out    (io/writer socket)]
    {:socket socket :in in :out out}))

(defn close-socket [s]
  (.close (:in s))
  (.close (:out s))
  (.close (:socket s)))

(defn write [^BufferedWriter out ^String js]
  (.write out js)
  (.write out (int 0)) ;; terminator
  (.flush out))

(defn read-response [^BufferedReader in]
  (let [sb (StringBuilder.)]
    (loop [sb sb c (.read in)]
      (cond
       (= c 1) (let [ret (str sb)]
                 (print ret)
                 (recur (StringBuilder.) (.read in)))
       (= c 0) (str sb)
       :else (do
               (.append sb (char c))
               (recur sb (.read in)))))))

(defn jsc-eval
  "Evaluate a JavaScript string in the JSC REPL process."
  [repl-env js]
  (let [{:keys [in out]} @(:socket repl-env)]
    (write out js)
    (let [result (json/read-str
                   (read-response in) :key-fn keyword)]
      (condp = (:status result)
        "success"
        {:status :success
         :value (:value result)}

        "exception"
        {:status :exception
         :value (:value result)}))))

(defn load-javascript
  "Load a Closure JavaScript file into the JSC REPL process."
  [repl-env provides url]
  (jsc-eval repl-env
    (str "goog.require('" (comp/munge (first provides)) "')")))

(defn form-require-expr-js
  "Takes a JavaScript path expression anf forms a `require` command."
  [path-expr]
  {:pre [(string? path-expr)]}
  (str "require(" path-expr ");"))

(defn form-require-path-js
  "Takes a path and forms a JavaScript `require` command."
  [path]
  {:pre [(or (string? path) (instance? File path))]}
  (form-require-expr-js (str "'" path "'")))

(defn setup
  ([repl-env] (setup repl-env nil))
  ([repl-env opts]
    (let [output-dir (io/file (:output-dir opts))
          _    (.mkdirs output-dir)
          env  (ana/empty-env)
          core (io/resource "cljs/core.cljs")
          root-path (.getCanonicalFile output-dir)
          rewrite-path (str (.getPath root-path) File/separator "goog")]
      ;; TODO: temporary hack, should wait till we can read the start string
      ;; from the process - David
      (Thread/sleep 300)
      (reset! (:socket repl-env)
        (socket (:host repl-env) (:port repl-env)))
      ;; compile cljs.core & its dependencies, goog/base.js must be available
      ;; for bootstrap to load, use new closure/compile as it can handle
      ;; resources in JARs
      (let [core-js (closure/compile core
                      (assoc opts
                        :output-file
                        (closure/src-file->target-file core)
                        ;:static-fns true
                        ))
            deps    (closure/add-dependencies opts core-js)]
        ;; output unoptimized code and the deps file
        ;; for all compiled namespaces
        (apply closure/output-unoptimized
          (assoc opts
            :output-to (.getPath (io/file output-dir "ambly_repl_deps.js")))
          deps))
      ;; Set up CLOSURE_IMPORT_SCRIPT function, injecting path
      (jsc-eval repl-env
         (str "CLOSURE_IMPORT_SCRIPT = function(src) {"
              (form-require-expr-js
                (str "'" root-path File/separator "goog" File/separator "' + src"))
              "return true; };"))
      ;; bootstrap
      (jsc-eval repl-env
        (form-require-path-js (io/file root-path "goog" "base.js")))
      ;; load the deps file so we can goog.require cljs.core etc.
      (jsc-eval repl-env
        (form-require-path-js (io/file root-path "ambly_repl_deps.js")))
      ;; monkey-patch isProvided_ to avoid useless warnings - David
      (jsc-eval repl-env
        (str "goog.isProvided_ = function(x) { return false; };"))
      ;; monkey-patch goog.require, skip all the loaded checks
      (repl/evaluate-form repl-env env "<cljs repl>"
        '(set! (.-require js/goog)
           (fn [name]
             (js/CLOSURE_IMPORT_SCRIPT
               (aget (.. js/goog -dependencies_ -nameToPath) name)))))
      ;; load cljs.core, setup printing
      (repl/evaluate-form repl-env env "<cljs repl>"
        '(do
           (.require js/goog "cljs.core")
           #_(set! *print-fn* (.-print (js/require "util")))))
      ;; redef goog.require to track loaded libs
      (repl/evaluate-form repl-env env "<cljs repl>"
        '(set! (.-require js/goog)
           (fn [name reload]
             (when (or (not (contains? *loaded-libs* name)) reload)
               (set! *loaded-libs* (conj (or *loaded-libs* #{}) name))
               (js/CLOSURE_IMPORT_SCRIPT
                 (aget (.. js/goog -dependencies_ -nameToPath) name))))))
      )))

(defrecord JscEnv [host port socket]
  repl/IJavaScriptEnv
  (-setup [this opts]
    (setup this opts))
  (-evaluate [this filename line js]
    (jsc-eval this js))
  (-load [this provides url]
    (load-javascript this provides url))
  (-tear-down [this]
    (close-socket @socket)))

(defn repl-env* [options]
  (let [{:keys [host port]}
        (merge
          {:host "localhost"
           :port 9999}
          options)]
    (JscEnv. host port (atom nil))))

(defn repl-env
  [& {:as options}]
  (repl-env* options))

(comment

  (require
    '[cljs.repl :as repl]
    '[ambly.repl.jsc :as jsc])

  (repl/repl* (jsc/repl-env)
    {:output-dir "out"
     :optimizations :none
     :cache-analysis true
     :source-map true})

  )