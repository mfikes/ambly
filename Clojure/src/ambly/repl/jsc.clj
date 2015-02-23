(ns ambly.repl.jsc
  (:require [clojure.string :as string]
            [clojure.java.io :as io]
            [cljs.analyzer :as ana]
            [cljs.util :as util]
            [cljs.compiler :as comp]
            [cljs.repl :as repl]
            [cljs.closure :as closure]
            [clojure.data.json :as json]
            [clojure.java.shell :as shell])
  (:import java.net.Socket
           java.lang.StringBuilder
           [java.io File BufferedReader BufferedWriter IOException]
           (javax.jmdns JmDNS ServiceListener)))

(defn set-logging-level [logger-name level]
  (.setLevel (java.util.logging.Logger/getLogger logger-name) level))

(def ambly-bonjour-name-prefix "Ambly ")

(defn is-ambly-bonjour-name? [bonjour-name]
  (.startsWith bonjour-name ambly-bonjour-name-prefix))

(defn bonjour-name->display-name
  [bonjour-name]
  (subs bonjour-name (count ambly-bonjour-name-prefix)))

(defn name-endpoint-map->choice-list [name-endpoint-map]
  (map vector (iterate inc 1) name-endpoint-map))

(defn print-discovered-devices [name-endpoint-map opts]
  (if (empty? name-endpoint-map)
    ((:print opts) "(No devices)")
    (doseq [[choice-number [bonjour-name _]] (name-endpoint-map->choice-list name-endpoint-map)]
      ((:print opts) (str "[" choice-number "] " (bonjour-name->display-name bonjour-name))))))

(defn discover-and-choose-device
  "Looks for Ambly WebDAV devices advertised via Bonjour and presents
  a simple command-line UI letting user pick one, unless
  choose-first-discovered? is set to true in which case the UI is bypassed"
  [choose-first-discovered? opts]
  (let [reg-type "_http._tcp.local."
        name-endpoint-map (atom (sorted-map))
        mdns-service (JmDNS/create)
        service-listener
        (reify ServiceListener
          (serviceAdded [_ service-event]
            (let [name (.getName service-event)]
              (when (is-ambly-bonjour-name? name)
                (.requestServiceInfo mdns-service (.getType service-event) (.getName service-event) 1))))
          (serviceRemoved [_ service-event]
            (swap! name-endpoint-map dissoc (.getName service-event)))
          (serviceResolved [_ service-event]
            (let [name (.getName service-event)]
              (when (is-ambly-bonjour-name? name)
                (let [entry {name (let [info (.getInfo service-event)]
                                    {:address (.getAddress info)
                                     :port    (.getPort info)})}]
                  (swap! name-endpoint-map merge entry))))))]
    (try
      (.addServiceListener mdns-service reg-type service-listener)
      (loop [count 0]
        (when (empty? @name-endpoint-map)
          (Thread/sleep 100)
          (when (= 20 count)
            ((:print opts) "\nSearching for devices ..."))
          (recur (inc count))))
      (Thread/sleep 500)                                    ;; Sleep a little more to catch stragglers
      (loop [current-name-endpoint-map @name-endpoint-map]
        ((:print opts))
        (print-discovered-devices current-name-endpoint-map opts)
        (when-not choose-first-discovered?
          ((:print opts) "\n[R] Refresh\n")
          ((:print-no-newline opts) "Choice: ")
          ((:flush opts)))
        (let [choice (if choose-first-discovered? "1" (read-line))]
          (if (= "r" (.toLowerCase choice))
            (recur @name-endpoint-map)
            (let [choices (name-endpoint-map->choice-list current-name-endpoint-map)
                  choice-ndx (try (dec (Long/parseLong choice)) (catch NumberFormatException _ -1))]
              (if (< -1 choice-ndx (count choices))
                (second (nth choices choice-ndx))
                (recur current-name-endpoint-map))))))
      (finally
        (future
          (.removeServiceListener mdns-service reg-type service-listener)
          (.close mdns-service))))))

(defn socket [host port]
  (let [socket (Socket. host port)
        in     (io/reader socket)
        out    (io/writer socket)]
    {:socket socket :in in :out out}))

(defn close-socket [s]
  (.close (:socket s)))

(defn write [^BufferedWriter out ^String js]
  (.write out js)
  (.write out (int 0)) ;; terminator
  (.flush out))

(defn read-messages [^BufferedReader in response-promise opts]
  (loop [sb (StringBuilder.) c (.read in)]
    (cond
      (= c -1) (do
                 (if-let [resp-promise @response-promise]
                   (deliver resp-promise :eof))
                 :eof)
      (= c 1) (do
                ((:print-no-newline opts) (str sb))
                ((:flush opts))
                (recur (StringBuilder.) (.read in)))
      (= c 0) (do
                (deliver @response-promise (str sb))
                (recur (StringBuilder.) (.read in)))
      :else (do
              (.append sb (char c))
              (recur sb (.read in))))))

(defn start-reading-messages
  "Starts a thread reading inbound messages."
  [repl-env opts]
  (.start
        (Thread.
          #(try
            (let [rv (read-messages (:in @(:socket repl-env)) (:response-promise repl-env) opts)]
              (when (= :eof rv)
                (close-socket @(:socket repl-env))))
            (catch IOException e
              (when-not (.isClosed (:socket @(:socket repl-env)))
                (.printStackTrace e)))))))

(defn stack-line->canonical-frame
  "Parses a stack line into a frame representation, returning nil
  if parse failed."
  [stack-line opts]
  (let [[function file line column]
        (rest (re-matches #"(.*)@file:///(.*):([0-9]+):([0-9]+)"
                stack-line))]
    (if (and file function line column)
      {:file     (str (io/file (util/output-directory opts) file))
       :function function
       :line     (Long/parseLong line)
       :column   (Long/parseLong column)})))

(defn raw-stacktrace->canonical-stacktrace
  "Parse a raw JSC stack representation, parsing it into stack frames.
  The canonical stacktrace must be a vector of maps of the form
  {:file <string> :function <string> :line <integer> :column <integer>}."
  [raw-stacktrace opts]
  (->> raw-stacktrace
    string/split-lines
    (map #(stack-line->canonical-frame % opts))
    (remove nil?)
    vec))

(defn jsc-eval
  "Evaluate a JavaScript string in the JSC REPL process."
  [repl-env js]
  (let [{:keys [out]} @(:socket repl-env)
        response-promise (promise)]
    (reset! (:response-promise repl-env) response-promise)
    (write out js)
    (let [response @response-promise]
      (if (= :eof response)
        {:status :error
         :value  "Connection to JavaScriptCore closed."}
        (let [result (json/read-str response
                       :key-fn keyword)]
          (merge
            {:status (keyword (:status result))
             :value  (:value result)}
            (when-let [raw-stacktrace (:stacktrace result)]
              {:stacktrace raw-stacktrace})))))))

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

(defn tear-down
  [repl-env]
  (when-let [webdav-mount-point @(:webdav-mount-point repl-env)]
    (shell/sh "umount" webdav-mount-point))
  (when-let [socket @(:socket repl-env)]
    (close-socket socket))
  (when (:shutdown-agents-on-quit (:options repl-env))
    (shutdown-agents)))

(defn setup
  [repl-env opts]
  (try
    (let [_ (set-logging-level "javax.jmdns" java.util.logging.Level/OFF)
          [bonjour-name endpoint] (discover-and-choose-device (:choose-first-discovered (:options repl-env)) opts)
          endpoint-address (.getHostAddress (:address endpoint))
          endpoint-port (:port endpoint)
          webdav-mount-point (str "/Volumes/Ambly-" endpoint-address)
          output-dir (io/file webdav-mount-point)
          env (ana/empty-env)
          core (io/resource "cljs/core.cljs")]
      ((:print opts) "\nConnecting to" (bonjour-name->display-name bonjour-name) "...\n")
      (reset! (:webdav-mount-point repl-env) webdav-mount-point)
      (when (.exists output-dir)
        (shell/sh "umount" webdav-mount-point))
      (.mkdirs output-dir)
      (shell/sh "mount_webdav" (str "http://" endpoint-address ":" endpoint-port) webdav-mount-point)
      (reset! (:socket repl-env)
        (socket endpoint-address (:port repl-env)))
      ;; Start dedicated thread to read messages from socket
      (start-reading-messages repl-env opts)
      ;; compile cljs.core & its dependencies, goog/base.js must be available
      ;; for bootstrap to load, use new closure/compile as it can handle
      ;; resources in JARs
      (let [core-js (closure/compile core
                      (assoc opts
                        :output-dir webdav-mount-point
                        :output-file
                        (closure/src-file->target-file core)))
            deps (closure/add-dependencies opts core-js)]
        ;; output unoptimized code and the deps file
        ;; for all compiled namespaces
        (apply closure/output-unoptimized
          (assoc opts
            :output-dir webdav-mount-point
            :output-to (.getPath (io/file output-dir "ambly_repl_deps.js")))
          deps))
      ;; Set up CLOSURE_IMPORT_SCRIPT function, injecting path
      (jsc-eval repl-env
        (str "CLOSURE_IMPORT_SCRIPT = function(src) {"
          (form-require-expr-js
            (str "'goog" File/separator "' + src"))
          "return true; };"))
      ;; bootstrap
      (jsc-eval repl-env
        (form-require-path-js (io/file "goog" "base.js")))
      ;; load the deps file so we can goog.require cljs.core etc.
      (jsc-eval repl-env
        (form-require-path-js (io/file "ambly_repl_deps.js")))
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
           (set-print-fn! js/out.write)))
      ;; redef goog.require to track loaded libs
      (repl/evaluate-form repl-env env "<cljs repl>"
        '(do
           (set! *loaded-libs* #{"cljs.core"})
           (set! (.-require js/goog)
             (fn [name reload]
               (when (or (not (contains? *loaded-libs* name)) reload)
                 (set! *loaded-libs* (conj (or *loaded-libs* #{}) name))
                 (js/CLOSURE_IMPORT_SCRIPT
                   (aget (.. js/goog -dependencies_ -nameToPath) name)))))))
      {:merge-opts {:output-dir webdav-mount-point}})
    (catch Throwable t
      (tear-down repl-env)
      (throw t))))

(defrecord JscEnv [host port socket response-promise webdav-mount-point options]
  repl/IReplEnvOptions
  (-repl-options [this]
    {:require-foreign true})
  repl/IParseStacktrace
  (-parse-stacktrace [_ stacktrace _ build-options]
    (raw-stacktrace->canonical-stacktrace stacktrace build-options))
  repl/IPrintStacktrace
  (-print-stacktrace [_ stacktrace _ build-options]
    (doseq [{:keys [function file url line column]}
            (repl/mapped-stacktrace stacktrace build-options)]
      ((:print repl/*repl-opts*) "\t" (str function " (" (str (or url file)) ":" line ":" column ")"))))
  repl/IJavaScriptEnv
  (-setup [repl-env opts]
    (setup repl-env opts))
  (-evaluate [repl-env _ _ js]
    (jsc-eval repl-env js))
  (-load [repl-env provides url]
    (load-javascript repl-env provides url))
  (-tear-down [repl-env]
    (tear-down repl-env)))

(defn repl-env* [options]
  (let [{:keys [host port] :as opts}
        (merge
          {:host "localhost"
           :port 50505}
          options)]
    (JscEnv. host port (atom nil) (atom nil) (atom nil) opts)))

(defn repl-env
  [& {:as options}]
  (repl-env* options))

(comment

  (require
    '[cljs.repl :as repl]
    '[ambly.repl.jsc :as jsc])

  (repl/repl* (jsc/repl-env)
    {:output-dir "out"
     :cache-analysis true
     :source-map true})

  )
