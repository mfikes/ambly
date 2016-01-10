# Ambly

A [ClojureScript](https://github.com/clojure/clojurescript) REPL into embedded JavaScriptCore on iOS, OS X, and tvOS.

Ambly is a REPL designed for use when developing hybrid ClojureScript / native apps.

Ambly comprises a ClojureScript REPL implementation, along with Objective-C code interfacing JavaScriptCore.

An iOS and tvOS demo app is included, making it easy to give the REPL a spin.

```
pod "Ambly", "~> 0.7.0"
```

[![Clojars Project](http://clojars.org/org.omcljs/ambly/latest-version.svg)](http://clojars.org/org.omcljs/ambly)

## Running

### Prerequisites

You must have Xcode installed as well as support for [CocoaPods](http://cocoapods.org). 
You must have Java 7 or later installed along with [Leiningen](http://leiningen.org) or [Boot](http://boot-clj.com/).

### Demo App

In `ambly/ObjectiveC/Ambly Demo` run `pod install`.

Open `Ambly Demo.xcworkspace` in Xcode and run the app in the simulator or on a device.

### REPL

In `ambly/Clojure` run `script/repl` to start the REPL if you're using Leiningen. If you're using Boot, run `$ boot ambly`. 

Here is a sample REPL startup sequence, illustrating device auto-discovery:

```
$ lein run 

[1] Ambly Demo on iPod touch
[2] Ambly Demo on iPad
[3] Ambly Demo on iPhone Simulator (My-Mac-Pro)
[4] Ambly Demo TV on Apple TV

[R] Refresh

Choice: 1

Connecting to Ambly Demo on iPod touch ...

To quit, type: :cljs/quit
cljs.user=> (+ 3 4)
7
```

> Note: See [Connectivity](https://github.com/omcljs/ambly/wiki/Connectivity) for details, should any networking difficulty arise.

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

## Contributing

Please contact David Nolen via email to request an electronic Contributor
Agreement. Pull requests will be accepted once your electronic CA has been signed and returned.

## Copyright and license

Copyright © 2015–2016 David Nolen

Licensed under the EPL (see the file LICENSE).
