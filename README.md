# Ambly

A [ClojureScript](https://github.com/clojure/clojurescript) REPL into iOS JavaScriptCore.

Ambly is a REPL designed for use when developing hybrid ClojureScript iOS apps.

Ambly comprises a ClojureScript REPL implementation, along with Objective-C code interfacing JavaScriptCore.

An iOS app is included, making it easy to give the REPL a spin. [Watch a demo.](http://youtu.be/TVDkYZJW2MY)

```
platform :ios, '8.0'
pod "Ambly", "~> 0.3.0"
```

[![Clojars Project](http://clojars.org/org.omcljs/ambly/latest-version.svg)](http://clojars.org/org.omcljs/ambly)

## Running

### Prerequisites

You must have Xcode installed as well as support for [CocoaPods](http://cocoapods.org). 
You must have Java 7 or later installed along with [Leiningen](http://leiningen.org).

### Demo App

In `ambly/ObjectiveC/Ambly Demo` run `pod install`.

Open `Ambly Demo.xcworkspace` in Xcode and run the app in the simulator or on a device.

### REPL

In `ambly/Clojure` run `script/repl` to start the REPL.

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
cljs.user=> (+ 3 4)
7
```

### Manual REPL Startup

If you would like to manually start the Ambly REPL from a Clojure REPL, issue the following two forms:

```clojure
(require
  '[cljs.repl :as repl]
  '[ambly.core :as ambly])
```

```clojure
(repl/repl (ambly/repl-env))
```

### rlwrap

For a better REPL experience (keyboard input editing and history support), you can install
[rlwrap](http://utopia.knoware.nl/~hlub/uck/rlwrap/) under OS X with
[Homebrew](http://brew.sh/):

```
brew install rlwrap
```

Then `script/repl` will automatically detect `rlwrap` and use it.

## License

Distributed under the Eclipse Public License, which is also used by ClojureScript.
