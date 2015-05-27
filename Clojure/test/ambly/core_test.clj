(ns ambly.core-test
  (:require [clojure.test :refer :all]
            [ambly.core :refer :all]
            [clojure.java.io :as io])
  (:import (java.net URL)
           (java.io File)))

(deftest sh-test
  (testing "Zero return value"
    (is (= 0 (sh 1000 -1 "/bin/test" "a" "=" "a"))))
  (testing "One return value"
    (is (= 1 (sh 1000 -1 "/bin/test" "a" "=" "b"))))
  (testing "Timeout"
    (is (= :timeout (sh 10 :timeout "/bin/sleep" "1")))))

(defn- form-ambly-bonjour-name
  [suffix]
  (str ambly-bonjour-name-prefix suffix))

(deftest test-is-ambly-bonjour-name?
  (testing "empty string"
    (is (not (is-ambly-bonjour-name? ""))))
  (testing "matching name"
    (is (is-ambly-bonjour-name? (form-ambly-bonjour-name "foo")))))

(deftest test-bonjour-name->display-name
  (testing "normal"
    (is (= "foo" (bonjour-name->display-name (form-ambly-bonjour-name "foo"))))))

(deftest test-name-endpoint-map->choice-list
  (testing "empty"
    (is (= ()
          (name-endpoint-map->choice-list {}))))
  (testing "single"
    (is (= '([1 ["Ambly foo" {:port 49153}]])
          (name-endpoint-map->choice-list {"Ambly foo" {:port 49153}}))))
  (testing "double"
    (is (= '([1 ["Ambly bar" {:port 50000}]]
              [2 ["Ambly foo" {:port 40000}]])
          (name-endpoint-map->choice-list
            (hash-map "Ambly foo" {:port 40000} "Ambly bar" {:port 50000})))))
  (testing "double with local"
    (is (= '([1 ["Ambly foo" {:port 40000 :address "127.0.0.1"}]]
              [2 ["Ambly bar" {:port 50000}]])
          (name-endpoint-map->choice-list
            (hash-map "Ambly foo" {:port 40000 :address "127.0.0.1"} "Ambly bar" {:port 50000}))))))

(deftest test-print-discovered-devices
  (testing "empty"
    (is (= "(No devices)\n"
          (with-out-str
            (print-discovered-devices {} {})))))
  (testing "single"
    (is (= "[1] foo\n"
          (with-out-str
            (print-discovered-devices {"Ambly foo" {:port 49153}} {})))))
  (testing "double"
    (is (= "[1] bar\n[2] foo\n"
          (with-out-str
            (print-discovered-devices
              (hash-map "Ambly foo" {:port 40000} "Ambly bar" {:port 50000}) {}))))))

(deftest test->source-uri->file
  (testing "normal"
    (is (= "cljs/core.js"
          (source-uri->relative-path "file:///cljs/core.js"))))
  (testing "remote"
    (is (= "<http://foo.com/remote.js>"
          (source-uri->relative-path "http://foo.com/remote.js")))))

(deftest test-stack-line->canonical-frame
  (testing "normal"
    (is (= {:file "cljs/core.js"
            :function "cljs$core$first"
            :line 4722
            :column 22}
          (stack-line->canonical-frame "cljs$core$first@file:///cljs/core.js:4722:22"))))
  (testing "no @"
    (is (= {:file "<http://foo.com/remote.js>"
            :function nil
            :line 4722
            :column 22}
          (stack-line->canonical-frame "http://foo.com/remote.js:4722:22"))))
  (testing "global code"
    (is (= {:file nil
            :function "global code"
            :line nil
            :column nil}
          (stack-line->canonical-frame "global code"))))
  (testing "blank"
    (is (nil? (stack-line->canonical-frame "")))))

(deftest test-raw-stacktrace->canonical-stacktrace
  (testing "normal"
    (is (= [{:file "cljs/core.js" :function "cljs$core$seq" :line 4692 :column 17}
            {:file "cljs/core.js" :function "cljs$core$first" :line 4722 :column 22}
            {:file "cljs/core.js" :function "cljs$core$ffirst" :line 5799 :column 39}
            {:file nil :function "global code" :line nil :column nil}]
          (raw-stacktrace->canonical-stacktrace
            "cljs$core$seq@file:///cljs/core.js:4692:17\ncljs$core$first@file:///cljs/core.js:4722:22\ncljs$core$ffirst@file:///cljs/core.js:5799:39\n\n\nglobal code"
            {:output-dir "/Volumes/Ambly-123"})))))

(deftest test-stacktrace->display-string
  (testing "normal"
    (is (= "\tcljs.core/seq (cljs/core.cljs:951:20)
\tcljs.core/first (cljs/core.cljs:960:16)
\tcljs$core$ffirst (cljs/core.cljs:1393:11)
\tglobal code (NO_SOURCE_FILE)\n"
          (let [url (URL. "jar:file:/Users/mfikes/.m2/repository/org/clojure/clojurescript/0.0-3196/clojurescript-0.0-3196.jar!/cljs/core.cljs")
                file (File. "/Volumes/Ambly-2EDFA1AF/cljs/core.cljs")]
            (stacktrace->display-string
              [{:file "/Volumes/Ambly-2EDFA1AF/cljs/core.js" :function "cljs$core$seq" :line 4692 :column 17}
               {:file "/Volumes/Ambly-2EDFA1AF/cljs/core.js" :function "cljs$core$first" :line 4722 :column 22}
               {:file "/Volumes/Ambly-2EDFA1AF/cljs/core.js" :function "cljs$core$ffirst" :line 5799, :column 39}
               {:file nil, :function "global code", :line nil, :column nil}]
              [{:url url :function "cljs.core/seq" :file file :line 951 :column 20}
               {:url url :function "cljs.core/first" :file file :line 960 :column 16}
               {:url url :function "cljs$core$ffirst", :file file :line 1393 :column 11}
               {:function nil, :file "NO_SOURCE_FILE", :line nil :column nil}]
              "/Volumes/Ambly-2EDFA1AF"))))))

(deftest form-amply-import-script-expr-js-test
  (testing "Dynamic Path in /tmp"
    (is (= "AMBLY_IMPORT_SCRIPT('/tmp/' + x);" (form-ambly-import-script-expr-js "'/tmp/' + x")))))

(deftest form-ambly-import-script-path-js-test
  (testing "Path in /tmp"
    (is (= "AMBLY_IMPORT_SCRIPT('/tmp/foo.js');" (form-ambly-import-script-path-js "/tmp/foo.js")))))

(deftest local?-test
  (testing "127.0.0.1"
    (is (local? "127.0.0.1")))
  (testing "192.0.2.1"
    (is (not (local? "192.0.2.1")))))

(deftest address-type-test
  (testing "127.0.0.1"
    (is (= :ipv4 (address-type "127.0.0.1"))))
  (testing "::1"
    (is (= :ipv6 (address-type "::1")))))

(deftest create-http-url-test
  (testing "ipv4"
    (is (= "http://127.0.0.1:8080" (create-http-url "127.0.0.1" 8080))))
  (testing "ipv6"
    (is (= "http://[::1]:8080" (create-http-url "::1" 8080)))))
