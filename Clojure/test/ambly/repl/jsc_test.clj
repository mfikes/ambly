(ns ambly.repl.jsc-test
  (:require [clojure.test :refer :all]
            [ambly.repl.jsc :refer :all]
            [clojure.java.io :as io]))

(deftest form-amply-import-script-expr-js-test
  (testing "Dynamic Path in /tmp"
    (is (= "AMBLY_IMPORT_SCRIPT('/tmp/' + x);" (form-ambly-import-script-expr-js "'/tmp/' + x")))))

(deftest form-ambly-import-script-path-js-test
  (testing "Path in /tmp"
    (is (= "AMBLY_IMPORT_SCRIPT('/tmp/foo.js');" (form-ambly-import-script-path-js (io/file "/tmp" "foo.js"))))))