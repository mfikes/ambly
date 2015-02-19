# Ambly

ClojureScript REPL into iOS JavaScriptCore.

Ambly is designed to be a great REPL for use in devloping hybrid iOS apps which target ClojureScript to an embedded instance of JavaScriptCore. The goal is to eliminate friction and make for a seamless experience.

Ambly comprises a ClojureScript REPL implementation, along with Objective-C code which interfaces with JavaScriptCore.

Ambly is currently under development. This repo includes a demo iOS app that you can use to give the REPL a spin.

## Prerequisites

You must have Xcode installed as well as support for [CocoaPods](http://cocoapods.org). 

You must have Java 7 or later installed along with [Leiningen](http://leiningen.org).

## Running

### Demo App

In `ambly/ObjectiveC/Ambly Demo` run `pod install`.

Open the `Ambly Demo.xcworkspace` in Xcode and run it in the simulator or on a device.

### REPL

**NOTE**: ClojureScript _master_ is currently required . You will need clone [its repo](https://github.com/clojure/clojurescript), build it (`script/build`), and update `ambly/Clojure/project.clj`, revising `"0.0-2850"` to match the version number of your locally-built copy.

In `ambly/Clojure` run `script/jscrepljs` to start the REPL.

Here is a sample REPL startup sequence, illustrating device auto-discovery and connection:

```
$ script/jscrepljs 
To quit, type: :cljs/quit

[1] iPod touch
[2] iPad
[3] iPhone Simulator (My-Mac-Pro)

[R] Refresh

Choice: 1

Connecting to iPod touch ...

ClojureScript:cljs.user> (+ 3 4)
7
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

**NOTE**: Starting the Ambly REPL with plain `lein repl` is currently not supported until upstream ClojureScript REPL issues are resolved.

### rlwrap

For a better REPL experience you can install
[rlwrap](http://utopia.knoware.nl/~hlub/uck/rlwrap/) under OS X with
[Homebrew](http://brew.sh/):

```
brew install rlwrap
```

The `script/jscrepljs` script automatically use `rlwrap` if installed. 

If manually starting the Ambly REPL, use:

```
rlwrap lein trampoline run -m clojure.main
```

## License

Distributed under the Eclipse Public License, which is also used by ClojureScript.
