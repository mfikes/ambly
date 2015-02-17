# Ambly

ClojureScript REPL into iOS JavaScriptCore.

## Prerequisites

### Xcode/iOS

You must have Xcode installed as well as support for [CocoaPods](http://cocoapods.org).

### Clojure/ClojueScript

You must have Java 7 or later installed along with [Leiningen](http://leiningen.org).

## Running

The embedded JavaScriptCore instance is hosted inside an iOS app (either in the simulator or on-device).

### Xcode Demo Project

In `ambly/ObjectiveC/Ambly Demo` run `pod install`.

Open the `Ambly Demo.xcworkspace` in Xcode and run the app it in the simulator or on a device.

### REPL

**NOTE**: ClojureScript _master_ is currently required. (You will need to get the latest, build it, and update the `project.clj` file in `ambly/Clojure` to refer to your locally-built copy.)

In `ambly/Clojure` run `script/jscrepljs` to start the REPL.

**NOTE**: You may see warnings regarding Bonjour/MDNS being logged. You may also encounter what appears to be a race between files being read in the WebDAV target and them being written out. If this occurs, rerun `script/jscrepljs`. 

Then the REPL will be live:
```
To quit, type: :cljs/quit
ClojureScript:cljs.user> (+ 1 1)
2
```

### Manual REPL Startup

If you would like to manually start the Ambly REPL, first start a Clojure REPL with `lein trampoline run -m clojure.main` and then issue the following two forms:

```clojure
(require
  '[cljs.repl :as repl]
  '[ambly.repl.jsc :as jsc])
```

```clojure
(repl/repl* (jsc/repl-env)
  {:optimizations :none
   :cache-analysis true
   :source-map true})
```

Note that currently starting the Ambly REPL with plain `lein repl` is not supported until upstream ClojureScript REPL issues are resolved.

### rlwrap

For a better REPL experience you can install
[rlwrap](http://utopia.knoware.nl/~hlub/uck/rlwrap/) under OS X with
[Homebrew](http://brew.sh/):

```
brew install rlwrap
```

The `script/jscrepljs` script will detect that `rlwrap` is installed and use it. If manually starting the Ambly REPL, use:

```
rlwrap lein trampoline run -m clojure.main
```

## License

Distributed under the Eclipse Public License, which is also used by ClojureScript.
