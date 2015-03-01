(ns ambly.repl.jsc-test
  (:require [clojure.test :refer :all]
            [ambly.repl.jsc :refer :all]
            [clojure.java.io :as io]))

(deftest form-require-expr-js-test
  (testing "Dynamic Path in /tmp"
    (is (= "amblyRequire('/tmp/' + x);" (form-ambly-require-expr-js "'/tmp/' + x")))))

(deftest form-require-path-js-test
  (testing "Path in /tmp"
    (is (= "amblyRequire('/tmp/foo.js');" (form-ambly-require-path-js (io/file "/tmp" "foo.js"))))))