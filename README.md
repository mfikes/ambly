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

Open the `Ambly Demo.xcworkspace` in Xcode run the app it in the simulator or on a device.

### REPL

#### WebDAV Setup
If you are running the app on a device, you will first need to have your Mac mount the WebDAV folder being exposed by the app. (If you are running it in the simulator, you can skip this step.)

Look in the Xcode logs for lines like the following:
```
[INFO] GCDWebDAVServer started on port 80 and reachable at http://10.0.1.6/
[VERBOSE] Bonjour registration complete for GCDWebDAVServer
[INFO] GCDWebDAVServer now reachable at http://My-iPhone.local/
```

Take either of the URLs (IP-based, or Bonjour-based), and in Finder do `Go` > `Connect to Server …` 

Then put the WebDav endpoint into the Server Address field and Connect as Guest.

#### Starting the REPL


In `ambly/Clojure` run either
- `script/jscrepljs` 
if running the app in the simulator
- `script/jscrepljs <IP or Bonjour HostName>` 
if on-device

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
  {:output-dir "out"
   :optimizations :none
   :cache-analysis true
   :source-map true})
```

If you are instead running the app on a device:

```clojure
(repl/repl* (jsc/repl-env :host <IP or Bonjour HostName>)
    {:output-dir "/Volumes/<IP or Bonjour HostName>"
   :optimizations :none
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
