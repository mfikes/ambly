(ns ambly.core
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
           (javax.jmdns JmDNS ServiceListener)
           (java.net URI InetAddress NetworkInterface Inet4Address)))

(defn- substring-exists?
  "Gets whether a substring exists in a string."
  [s sub]
  (not (neg? (.indexOf s sub))))

(defn getOs
  "Returns a keyword that represents the OS."
  []
  (let [os-name (.toLowerCase (System/getProperty "os.name"))]
    (cond
      (substring-exists? os-name "mac") :mac
      (substring-exists? os-name "win") :win
      :else :unknown)))

(defn sh
  "Executes a shell process. Allows up to timeout to complete, returning process
  exit code. Otherwise forcibly terminates process and returns timeout-exit-value."
  [timeout timeout-exit-value & args]
  {:pre [(number? timeout) (every? string? args)]}
  (let [process (.exec (Runtime/getRuntime) (string/join " " args))]
    (loop [time-remaining timeout]
      (Thread/sleep 100)
      (or
        (try
          (.exitValue process)
          (catch IllegalThreadStateException _
            nil))
        (if (pos? time-remaining)
          (recur (- time-remaining 100))
          (do
            (.destroy process)
            timeout-exit-value))))))

(defn- ip-address->inet-addr
  "Take a string representation of an IP address and returns a Java InetAddress
  instance, or nil if the conversion couldn't be completed."
  [ip-address]
  {:pre  [(string? ip-address)]
   :post [(or (nil? %) (instance? InetAddress %))]}
  (try
    (InetAddress/getByName ip-address)
    (catch Throwable _
      nil)))

(defn local?
  "Takes an IP address and returns a truthy value iff the address is local
  to the machine running this code."
  [ip-address]
  {:pre [(or (nil? ip-address) (string? ip-address))]}
  (some-> ip-address
    ip-address->inet-addr
    NetworkInterface/getByInetAddress))

(defn address-type
  "Takes an IP address and returns a keyword in #{:ipv4 :ipv6}
  indicating the type of the address, or nil if the type could not
  be determined"
  [ip-address]
  {:pre  [(string? ip-address)]
   :post [(or (nil? %) (#{:ipv4 :ipv6} %))]}
  (if-let [inet-address (ip-address->inet-addr ip-address)]
    (if (instance? Inet4Address inet-address)
      :ipv4
      :ipv6)))

(defn address-type->localhost-address
  "Given an address type, returns the localhost address."
  [address-type]
  {:pre [(#{:ipv4 :ipv6} address-type)]
   :post [(string? %)]}
  (address-type {:ipv4 "127.0.0.1" :ipv6 "::1"}))

(defn- local-address-if
  "Takes an IP address and returns the localhost address if the
  address happens to be local to this machine."
  [ip-address]
  {:pre  [(string? ip-address)]
   :post [(string? %)]}
  (if (local? ip-address)
    (-> ip-address
      address-type
      address-type->localhost-address)
    ip-address))

(defn set-logging-level [logger-name level]
  "Sets the logging level for a logger to a level."
  {:pre [(string? logger-name) (instance? java.util.logging.Level level)]}
  (.setLevel (java.util.logging.Logger/getLogger logger-name) level))

(def ambly-bonjour-name-prefix
  "The prefix used in Ambly Bonjour service names."
  "Ambly ")

(defn is-ambly-bonjour-name? [bonjour-name]
  "Returns true iff a given name is an Ambly Bonjour service name."
  {:pre [(string? bonjour-name)]}
  (.startsWith bonjour-name ambly-bonjour-name-prefix))

(defn bonjour-name->display-name
  "Converts an Ambly Bonjour service name to a display name
  (stripping off ambly-bonjour-name-prefix)."
  [bonjour-name]
  {:pre [(is-ambly-bonjour-name? bonjour-name)]
   :post [(string? %)]}
  (subs bonjour-name (count ambly-bonjour-name-prefix)))

(defn name-endpoint-map->choice-list [name-endpoint-map]
  "Takes a name to endpoint map, and converts into an indexed list."
  {:pre [(map? name-endpoint-map)]}
  (map vector
    (iterate inc 1)
    (sort-by (juxt (comp (complement local?) :address second) first)
      name-endpoint-map)))

(defn print-discovered-devices [name-endpoint-map opts]
  "Prints the set of discovered devices given a name endpoint map."
  {:pre [(map? name-endpoint-map) (map? opts)]}
  (if (empty? name-endpoint-map)
    (println "(No devices)")
    (doseq [[choice-number [bonjour-name _]] (name-endpoint-map->choice-list name-endpoint-map)]
      (println (str "[" choice-number "] " (bonjour-name->display-name bonjour-name))))))

(defn setup-mdns
  "Sets up mDNS to populate atom supplied in name-endpoint-map with discoveries.
  Returns a function that will tear down mDNS."
  [reg-type name-endpoint-map]
  {:pre [(string? reg-type)]
   :post [(fn? %)]}
  (let [mdns-service (JmDNS/create)
        service-listener
        (reify ServiceListener
          (serviceAdded [_ service-event]
            (let [type (.getType service-event)
                  name (.getName service-event)]
              (when (and (= reg-type type) (is-ambly-bonjour-name? name))
                (.requestServiceInfo mdns-service type name 1))))
          (serviceRemoved [_ service-event]
            (swap! name-endpoint-map dissoc (.getName service-event)))
          (serviceResolved [_ service-event]
            (let [type (.getType service-event)
                  name (.getName service-event)]
              (when (and (= reg-type type) (is-ambly-bonjour-name? name))
                (let [entry {name (let [info (.getInfo service-event)]
                                    {:address (.getHostAddress (.getAddress info))
                                     :port    (.getPort info)})}]
                  (swap! name-endpoint-map merge entry))))))]
    (.addServiceListener mdns-service reg-type service-listener)
    (fn []
      (.removeServiceListener mdns-service reg-type service-listener)
      (.close mdns-service))))

(defn discover-and-choose-device
  "Looks for Ambly WebDAV devices advertised via Bonjour and presents
  a simple command-line UI letting user pick one, unless
  choose-first-discovered? is set to true in which case the UI is bypassed"
  [choose-first-discovered? opts]
  {:pre [(map? opts)]}
  (let [reg-type "_http._tcp.local."
        name-endpoint-map (atom {})
        tear-down-mdns
        (loop [count 0
               tear-down-mdns (setup-mdns reg-type name-endpoint-map)]
          (if (empty? @name-endpoint-map)
            (do
              (Thread/sleep 100)
              (when (= 20 count)
                (println "\nSearching for devices ..."))
              (if (zero? (rem (inc count) 100))
                (do
                  (tear-down-mdns)
                  (recur (inc count) (setup-mdns reg-type name-endpoint-map)))
                (recur (inc count) tear-down-mdns)))
            tear-down-mdns))]
    (try
      (Thread/sleep 500)                                    ;; Sleep a little more to catch stragglers
      (loop [current-name-endpoint-map @name-endpoint-map]
        (println)
        (print-discovered-devices current-name-endpoint-map opts)
        (when-not choose-first-discovered?
          (println "\n[R] Refresh\n")
          (print "Choice: ")
          (flush))
        (let [choice (if choose-first-discovered? "1" (read-line))]
          (if (= "r" (.toLowerCase choice))
            (recur @name-endpoint-map)
            (let [choices (name-endpoint-map->choice-list current-name-endpoint-map)
                  choice-ndx (try (dec (Long/parseLong choice)) (catch NumberFormatException _ -1))]
              (if (< -1 choice-ndx (count choices))
                (second (nth choices choice-ndx))
                (recur current-name-endpoint-map))))))
      (finally
        (.start (Thread. tear-down-mdns))))))

(defn socket
  [host port]
  {:pre [(string? host) (number? port)]}
  (let [socket (doto (Socket. host port) (.setKeepAlive true))
        in     (io/reader socket)
        out    (io/writer socket)]
    {:socket socket :in in :out out}))

(defn close-socket
  [s]
  {:pre [(map? s)]}
  (.close (:socket s)))

(defn write
  [out js]
  (:pre [(instance? BufferedWriter out) (string? js)])
  (.write out js)
  (.write out (int 0)) ;; terminator
  (.flush out))

(defn read-messages
  [in response-promise opts]
  {:pre [(instance? BufferedReader in) (map? opts)]}
  (loop [sb (StringBuilder.) c (.read in)]
    (cond
      (= c -1) (do
                 (if-let [resp-promise @response-promise]
                   (deliver resp-promise :eof))
                 :eof)
      (= c 1) (do
                (print (str sb))
                (flush)
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
  {:pre [(map? repl-env) (map? opts)]}
  (.start
    (Thread.
      #(try
        (let [rv (read-messages (:in @(:socket repl-env)) (:response-promise repl-env) opts)]
          (when (= :eof rv)
            (close-socket @(:socket repl-env))))
        (catch IOException e
          (when-not (.isClosed (:socket @(:socket repl-env)))
            (.printStackTrace e)))))))

(defn source-uri->relative-path
  "Takes a source URI and returns a relative path value suitable for inclusion
  in a canonical stack frame."
  [source-uri]
  {:pre [(string? source-uri)]}
  (let [uri (URI. source-uri)
        uri-scheme (.getScheme uri)]
    (case uri-scheme
      "file" (let [uri-path (.getPath uri)]
               (if (.startsWith uri-path "/")
                 (subs uri-path 1)
                 uri-path))
      (str "<" source-uri ">"))))

(defn stack-line->canonical-frame
  "Parses a stack line into a frame representation, returning nil
  if parse failed."
  [stack-line]
  {:pre  [(string? stack-line)]}
  (let [[function source-uri line column]
        (rest (re-matches #"(.*)@(.*):([0-9]+):([0-9]+)"
                stack-line))]
    (if (and source-uri function line column)
      {:file     (source-uri->relative-path source-uri)
       :function function
       :line     (Long/parseLong line)
       :column   (Long/parseLong column)}
      (let [[source-uri line column]
            (rest (re-matches #"(.*):([0-9]+):([0-9]+)"
                              stack-line))]
        (if (and source-uri line column)
          {:file     (source-uri->relative-path source-uri)
           :function nil
           :line     (Long/parseLong line)
           :column   (Long/parseLong column)}
          (when-not (string/blank? stack-line)
            {:file     nil
             :function (string/trim stack-line)
             :line     nil
             :column   nil}))))))

(defn raw-stacktrace->canonical-stacktrace
  "Parse a raw JSC stack representation, parsing it into stack frames.
  The canonical stacktrace must be a vector of maps of the form
  {:file <string> :function <string> :line <integer> :column <integer>}."
  [raw-stacktrace opts]
  {:pre  [(string? raw-stacktrace) (map? opts)]
   :post [(vector? %)]}
  (let [stack-line->canonical-frame (memoize stack-line->canonical-frame)]
    (->> raw-stacktrace
         string/split-lines
         (map stack-line->canonical-frame)
         (remove nil?)
         vec)))

(def not-conected-result
  {:status :error
   :value "Not connected."})

(defn jsc-eval
  "Evaluate a JavaScript string in the JSC REPL process."
  [repl-env js]
  {:pre [(map? repl-env) (string? js)]}
  (let [{:keys [out]} @(:socket repl-env)
        response-promise (promise)]
    (if out
      (do
        (reset! (:response-promise repl-env) response-promise)
        (write out js)
        (let [response @response-promise]
          (if (= :eof response)
            not-conected-result
            (let [result (json/read-str response
                           :key-fn keyword)]
              (merge
                {:status (keyword (:status result))
                 :value  (:value result)}
                (when-let [raw-stacktrace (:stacktrace result)]
                  {:stacktrace raw-stacktrace}))))))
      not-conected-result)))

(defn load-javascript
  "Load a Closure JavaScript file into the JSC REPL process."
  [repl-env provides url]
  (jsc-eval repl-env
    (str "goog.require('" (comp/munge (first provides)) "')")))

(defn form-ambly-import-script-expr-js
  "Takes a JavaScript path expression and forms an `AMBLY_IMPORT_SCRIPT` command."
  [path-expr]
  {:pre [(string? path-expr)]}
  (str "AMBLY_IMPORT_SCRIPT(" path-expr ");"))

(defn form-ambly-import-script-path-js
  "Takes a path and forms a JavaScript `AMBLY_IMPORT_SCRIPT` command."
  [path]
  {:pre [(string? path)]}
  (form-ambly-import-script-expr-js (str "'" path "'")))

(defn- mount-exists?
  "Checks to see if a WebDAV mount point already exists."
  [webdav-mount-point]
  {:pre [(string? webdav-mount-point)]}
  ;; We fall back to `.canRead` to cope with mount points where `.exists` returns false and
  ;; for command-line tools indicate `Operation timed out`.
  (let [file (io/file webdav-mount-point)]
    (or (.exists file) (.canRead file))))

(defmulti umount-webdav
  "Unmounts WebDAV, returning true upon success."
  (fn [os webdav-mount-point] os))

(defmethod umount-webdav :mac
  [os webdav-mount-point]
  {:pre [(keyword? os) (string? webdav-mount-point)]}
  (or
    (not (mount-exists? webdav-mount-point))
    (or
      (zero? (sh 5000 -1 "umount" webdav-mount-point))
      (zero? (sh 5000 -1 "umount" "-f" webdav-mount-point))
      (zero? (sh 1000 -1 "rmdir" webdav-mount-point)))))

(defmethod umount-webdav :win
  [os webdav-mount-point]
  {:pre [(keyword? os) (string? webdav-mount-point)]}
  (zero? (sh 5000 -1 "net" "use" webdav-mount-point "/delete")))

(defmethod umount-webdav :unknown
  [os webdav-mount-point]
  {:pre [(string? webdav-mount-point)]}
  (println "\nPlease manually unmount" webdav-mount-point)
  true)

(defn create-http-url
  "Takes an address and port and forms a URL."
  [address port]
  (let [wrapped-address (if (= :ipv6 (address-type address))
                          (str "[" address "]")
                          address)]
    (str "http://" wrapped-address ":" port)))

(defmulti mount-webdav
  "Mounts WebDAV, returning the filesystem mount point,
  otherwise throwing upon failure."
  (fn [os bonjour-name endpoint-address endpoint-port] os))

(defmethod mount-webdav :mac
  [os bonjour-name endpoint-address endpoint-port]
  {:pre [(keyword? os) (is-ambly-bonjour-name? bonjour-name)
         (string? endpoint-address) (number? endpoint-port)]}
  (let [webdav-endpoint (create-http-url endpoint-address endpoint-port)
        webdav-mount-point (str "/Volumes/Ambly-" (format "%08X" (hash webdav-endpoint)))
        output-dir (io/file webdav-mount-point)]
    (when-not (umount-webdav os webdav-mount-point)
      (throw (IOException. (str "Unable to unmount previous WebDAV mount at " webdav-mount-point))))
    (loop [tries 1]
      (if-not (or (mount-exists? webdav-mount-point) (.mkdirs output-dir))
        (throw (IOException. (str "Unable to create WebDAV mount point " webdav-mount-point))))
      (if (zero? (sh 1000 -1 "mount_webdav" webdav-endpoint webdav-mount-point))
        webdav-mount-point
        (if (= 4 tries)
          (throw (IOException. (str "Unable to mount WebDAV at " webdav-endpoint)))
          (do
            (umount-webdav os webdav-mount-point)
            (Thread/sleep (* tries 500))
            (recur (inc tries))))))))

(defn extract-drive-letter
  "Takes the output from `net use ...` command and extracts
  the assigned drive letter."
  [output]
  (str (second (re-matches #"Drive ([A-Z]?): is now connected to" output)) ":"))

(defmethod mount-webdav :win
  [os bonjour-name endpoint-address endpoint-port]
  {:pre [(keyword? os) (is-ambly-bonjour-name? bonjour-name)
         (string? endpoint-address) (number? endpoint-port)]}
  (let [webdav-endpoint (create-http-url endpoint-address endpoint-port)
        shell-result (shell/sh "net" "use" "*" webdav-endpoint)]
   (or
     (extract-drive-letter (subs (:out shell-result) 0 28))
     (throw (IOException. (:err shell-result))))))

(defmethod mount-webdav :unknown
  [os bonjour-name endpoint-address endpoint-port]
  {:pre [(keyword? os) (is-ambly-bonjour-name? bonjour-name)
         (string? endpoint-address) (number? endpoint-port)]}
  (let [webdav-endpoint (create-http-url endpoint-address endpoint-port)]
    (println "Please manually mount" webdav-endpoint "and when done, enter")
    (print "filesystem mount directory: ")
    (flush)
    (read-line)))

(defn- set-up-socket
  [repl-env opts address port]
  {:pre [(map? repl-env) (map? opts) (string? address) (number? port)]}
  (when-let [socket @(:socket repl-env)]
    (close-socket socket))
  (reset! (:socket repl-env)
    (socket address port))
  ;; Start dedicated thread to read messages from socket
  (start-reading-messages repl-env opts))

(defn tear-down
  [repl-env]
  (when-let [webdav-mount-point @(:webdav-mount-point repl-env)]
    (umount-webdav (getOs) webdav-mount-point))
  (when-let [socket @(:socket repl-env)]
    (close-socket socket)))

(defn setup
  [repl-env opts]
  {:pre [(map? repl-env) (map? opts)]}
  (try
    (let [_ (set-logging-level "javax.jmdns" java.util.logging.Level/OFF)
          [bonjour-name endpoint] (discover-and-choose-device (:choose-first-discovered (:options repl-env)) opts)
          endpoint-address (local-address-if (:address endpoint))
          endpoint-port (:port endpoint)
          _ (reset! (:bonjour-name repl-env) bonjour-name)
          webdav-mount-point (mount-webdav (getOs) bonjour-name endpoint-address endpoint-port)
          _ (reset! (:webdav-mount-point repl-env) webdav-mount-point)
          output-dir (io/file webdav-mount-point)
          env (ana/empty-env)
          core (io/resource "cljs/core.cljs")]
      (println (str "\nConnecting to " (bonjour-name->display-name bonjour-name) " ...\n"))
      (set-up-socket repl-env opts endpoint-address (dec endpoint-port))
      (if (= "true" (:value (jsc-eval repl-env "typeof cljs === 'undefined'")))
        (do
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
              (form-ambly-import-script-expr-js
                "'goog/' + src")
              "return true; };"))
          ;; bootstrap
          (jsc-eval repl-env
            (form-ambly-import-script-path-js "goog/base.js"))
          ;; load the deps file so we can goog.require cljs.core etc.
          (jsc-eval repl-env
            (form-ambly-import-script-path-js "ambly_repl_deps.js"))
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
               (set-print-fn! js/AMBLY_PRINT_FN)))
          ;; redef goog.require to track loaded libs
          (repl/evaluate-form repl-env env "<cljs repl>"
            '(do
               (set! *loaded-libs* #{"cljs.core"})
               (set! (.-require js/goog)
                 (fn [name reload]
                   (when (or (not (contains? *loaded-libs* name)) reload)
                     (set! *loaded-libs* (conj (or *loaded-libs* #{}) name))
                     (js/CLOSURE_IMPORT_SCRIPT
                       (aget (.. js/goog -dependencies_ -nameToPath) name))))))))
        (let [expected-clojurescript-version (cljs.util/clojurescript-version)
              actual-clojurescript-version (:value (jsc-eval repl-env "cljs.core._STAR_clojurescript_version_STAR_"))]
          (when-not (= expected-clojurescript-version actual-clojurescript-version)
            (println
              (str "WARNING: " (bonjour-name->display-name bonjour-name)
                "\n         is running ClojureScript " actual-clojurescript-version
                ", while the Ambly REPL is\n         set up to use ClojureScript "
                expected-clojurescript-version ".\n")))))
      {:merge-opts {:output-dir webdav-mount-point}})
    (catch Throwable t
      (tear-down repl-env)
      (throw t))))

(defn stacktrace->display-string
  "Takes a stacktrace and forms a display string, consulting a mapped stacktrace
  and the output directory"
  [stacktrace mapped-stacktrace output-dir]
  {:pre [(vector? stacktrace) (vector? mapped-stacktrace) (string? output-dir)]
   :post [(string? %)]}
  (let [source (fn [url file]
                 (if file
                   (let [file-path (str file)]
                     (if (.startsWith file-path output-dir)
                       (subs file-path (inc (count output-dir)))
                       file-path))
                   (str url)))]
    (apply str
      (for [{:keys [function file url line column]}
            (map #(merge-with (fn [a b] (or a b)) %1 %2)
              mapped-stacktrace
              stacktrace)]
        (let [url (when url (string/trim (.toString url)))
              file (when file (string/trim (.toString file)))]
          (str "\t" (when function (str function " "))
            "(" (source url file) (when line (str ":" line)) (when column (str ":" column)) ")\n"))))))

(defrecord JscEnv [response-promise bonjour-name webdav-mount-point socket options]
  repl/IReplEnvOptions
  (-repl-options [this]
    {:require-foreign true})
  repl/IParseStacktrace
  (-parse-stacktrace [_ stacktrace _ build-options]
    (raw-stacktrace->canonical-stacktrace stacktrace build-options))
  repl/IPrintStacktrace
  (-print-stacktrace [_ stacktrace _ build-options]
    (print
      (stacktrace->display-string
        stacktrace
        (repl/mapped-stacktrace stacktrace build-options)
        @webdav-mount-point)))
  repl/IJavaScriptEnv
  (-setup [repl-env opts]
    (setup repl-env opts))
  (-evaluate [repl-env _ _ js]
    (jsc-eval repl-env js))
  (-load [repl-env provides url]
    (load-javascript repl-env provides url))
  (-tear-down [repl-env]
    (tear-down repl-env)))

(defn repl-env*
  [options]
  {:pre [(or (nil? options) (map? options))]}
  (JscEnv. (atom nil) (atom nil) (atom nil) (atom nil) (or options {})))

(defn repl-env
  "Ambly REPL environment."
  [& {:as options}]
  (repl-env* options))

(defn -main
  "Launches the Ambly REPL."
  []
  (repl/repl (repl-env)))

(comment

  (require
    '[cljs.repl :as repl]
    '[ambly.core :as ambly])

  (repl/repl (ambly/repl-env))

  )
