<!--menu:Introduction-->
<!--label:index-->
# Introduction

`pecan` is a macro-based [Haxe](https://haxe.org/) 4 library that provides [coroutines](https://en.wikipedia.org/wiki/Coroutine).

<!--label:intro-installation-->
## Installation

`pecan` can be installed as a `git` library:

```bash
$ haxelib git pecan git@github.com:Aurel300/pecan.git
# or
$ haxelib git pecan https://github.com/Aurel300/pecan.git
```

Alternatively, the Github repository can be cloned and `pecan` can be installed as a `dev` library:

```bash
$ git clone git@github.com:Aurel300/pecan.git
$ cd pecan
$ haxelib dev pecan .
```

A Haxelib release is coming soon.

Whichever way the library is installed, `-lib pecan` should be added to the compilation flags or the `hxml` file.

<!--label:intro-start-->
## Getting started

Here is an example of `pecan` usage. For a more in-depth look into each of the annotated features, see the following chapters.

```haxe
var factory = pecan.Co.co({   // (1)
  var greeted = 0;
  trace("Greeter online!");
  suspend();                  // (2)
  while (true) {              // (3)
    var name = accept();      // (4)
    if (name == null)
      break;
    trace('Hello, $name!');
    yield(++greeted);         // (5)
  }
  trace("Bye!");
}, (_ : String), (_ : Int));  // (6)

var instance = factory.run(); // (7)
                              // output: Greeter online!
instance.wakeup();            // (8)
instance.give("world");       // (9)
                              // output: Hello, world!
instance.take() == 1;         // (10)
instance.give("Haxe");        // output: Hello, Haxe!
instance.take() == 2;
instance.give(null);          // output: Bye!
instance.state == Terminated; // (11)
```

There are several things to note in the example:

 - `(1)`: `pecan.Co.co` is one way to *declare* a coroutine. This is analogous to a function declaration. See [declaration](features-declaration).
 - `(2)`: coroutines can be *suspended* and later resumed at arbitrary points, unlike regular functions, which have to run to completion. See [suspending calls](features-suspending).
 - `(3)`: coroutines can make use of any Haxe syntax, even if there are suspension points within.
 - `(4)` and `(5)`: `accept()` and `yield(...)` can be used to communicate from within the coroutine in a blocking manner. See [input and output](features-io).
 - `(6)`: input and output types (for `accept()` and `yield(...)`, respectively), must be explicitly declared. See [declaration](features-declaration) and [input and output](features-io).
 - `(7)`: a coroutine is actually started with a `run(...)` call. This is analogous to a function call. See [invoking](features-invoking).
 - `(8)`: coroutines suspended with a `suspend()` call can be resumed with a `wakeup()` call. See [suspending calls](features-suspending).
 - `(9)` and `(10)`: `give(...)` and `take()` complement the coroutine I/O operations. `give(...)` is used to provide values to a coroutine that has called `accept()`, `take()` is used to take values from a coroutine that has called `yield(...)`.
 - `(11)`: see [states](features-states).
