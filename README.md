# Ambly

A [ClojureScript](https://github.com/clojure/clojurescript) REPL into iOS JavaScriptCore.

Ambly is a REPL designed for use when developing hybrid ClojureScript iOS apps.

Ambly comprises a ClojureScript REPL implementation, along with Objective-C code interfacing JavaScriptCore.

Ambly is under development. A demo iOS app is included so that you can give the REPL a spin!

## Running

### Prerequisites

You must have Xcode installed as well as support for [CocoaPods](http://cocoapods.org). 
You must have Java 7 or later installed along with [Leiningen](http://leiningen.org).

### Demo App

In `ambly/ObjectiveC/Ambly Demo` run `pod install`.

Open `Ambly Demo.xcworkspace` in Xcode and run the app in the simulator or on a device.

### REPL

In `ambly/Clojure` run `lein run` to start the REPL.

Here is a sample REPL startup sequence, illustrating device auto-discovery:

```
$ lein run 

[1] Ambly Demo on iPod touch
[2] Ambly Demo on iPad
[3] Ambly Demo on iPhone Simulator (My-Mac-Pro)

[R] Refresh

Choice: 1

Connecting to Ambly Demo on iPod touch ...

To quit, type: :cljs/quit
ClojureScript:cljs.user> (+ 3 4)
7
```

### Manual REPL Startup

If you would like to manually start the Ambly REPL from a Clojure REPL, issue the following two forms:

```clojure
(require
  '[cljs.repl :as repl]
  '[ambly.repl.jsc :as jsc])
```

```clojure
(repl/repl (jsc/repl-env))
```

### rlwrap

For a better REPL experience (keyboard input editing and history support), you can install
[rlwrap](http://utopia.knoware.nl/~hlub/uck/rlwrap/) under OS X with
[Homebrew](http://brew.sh/):

```
brew install rlwrap
```

Then you can start the Ambly REPL with `rlwrap lein run`.

## License

Distributed under the Eclipse Public License, which is also used by ClojureScript.
