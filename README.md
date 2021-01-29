# `pecan`

`pecan` is a library for [Haxe](https://github.com/HaxeFoundation/haxe) that provides coroutines -- suspendable functions.

---

 - [Coroutines](#coroutines)
   - [Suspending](#suspending)
   - [Defining custom suspending functions](#defining-custom-suspending-functions)
   - [Arguments](#arguments)
   - [I/O](#io)
   - [Defining custom input functions](#defining-custom-input-functions)
   - [API](#api)

## Coroutines

Coroutine factories can be obtained with the `pecan.Co.co` expression macro. The first argument is a block of code, which will form the body of the coroutine. The second and third arguments are optional and can be used to specify I/O types, see [I/O](#io).

```haxe
import pecan.Co.co;

class Main {
  public static function main():Void {
    var foo = co({
      trace("World!");
    }).run();
    trace("Hello!");
    foo.tick();
  }
}
```

A coroutine differs from a regular function in that a "call" is not a single event, but rather a single instance of a coroutine can exist for a long time. Hence the `co` macro returns a factory, which is analogous to a function declaration. The `run` method of a factory can be used to obtain a new instance of the coroutine (with the interface `pecan.ICo<...>`), analogous to a function call.

Within the code block, there are some special variables and constructs available:

 - `self` - refers to the current instance of `pecan.Co`.
 - `suspend()`, and `terminate()` - see [suspending](#suspending).
 - `accept()` and `yield(<expr>)` - see [I/O](#io).
 - `label(<string>)` - see [labels](#labels).

### Suspending

One of the main features of coroutines is that they can be suspended at any point and then be woken up again at some point later, such that they continue from the same point in the code.

Within a coroutine, a `suspend()` call can be used to suspend execution. A suspended coroutine can be woken up later with the `wakeup` method:

```haxe
var c = co({
  trace("hello");
  suspend();
  trace("world");
}).run();
c.tick();
trace("Haxe");
c.wakeup();
// outputs hello Haxe world
```

A wakeup of the coroutine can be scheduled just before a `suspend` call, for example:

```haxe
co({
  trace("hello");
  haxe.Timer.delay(self.wakeup, 1000);
  suspend();
  trace("world");
}).run().tick();
```

Coroutines can also be terminated completely, which means they cannot be woken up again. This is achieved with the `terminate()` call.

### Defining custom suspending functions

It is possible to declare methods as suspending. These methods must:

 - have the `:pecan.action` metadata
 - take the coroutine `pecan.ICo<...>` as their last argument, ideally optional

Functions declared this way can then be called from within coroutines, with the last argument being replaced by the coroutine instance automatically.

An example defining `haxe.Timer.delay` as a suspending function:

```haxe
class Foobar {
  @:pecan.action public static function delay<T, U>(ms:Int, ?co:pecan.ICo<T, U>):Void {
    haxe.Timer.delay(co.wakeup, ms);
    co.suspend();
  }
}
```

Then simply:

```haxe
co({
  trace("Hello,");
  Foobar.delay(1000); // one second of suspense
  trace("Haxe!");
}).run().tick();
```

### Arguments

Coroutines can be declared to accept arguments. These are values passed to the coroutine once, when it is created with the `run` method of its factory. To declare a coroutine that takes arguments, pass a function declaration into the `co` call:

```haxe
var greeter = co((name:String) -> {
  trace('Hello, $name!');
});
greeter.run("Haxe").tick(); // outputs Hello, Haxe!
greeter.run("world").tick(); // outputs Hello, world!
```

As for regular functions, arguments can be optional.

### I/O

Coroutines can `accept` inputs and `yield` outputs. To ensure type safety, the types for inputs and outputs must be declared as part of the `co` macro call. The optional second argument declares the input type, the optional third argument declares the output type. The types must be specified as type-checks:

```haxe
var takesInts = co({/* ... */}, (_ : Int));
var outputsStrings = co({/* ... */}, null, (_ : String));
var takesBoolsAndOutputsDates = co({/* ... */}, (_ : Bool), (_ : Date));
```

Within the coroutine code, `accept()` can be used to accept input of the declared type:

```haxe
var greeter = co({
  trace('Hello, ${accept()}, from ${accept()}!');
}, (_ : String)).run();
greeter.give("Haxe");
greeter.give("pecan"); // outputs Hello, Haxe, from pecan!
```

All `accept()` calls within an expression are evaluated before the expression itself. The evaluation order of complex expressions involving calls to `accept()` and other functions may therefore be different than expected. Boolean operators with `accept()` will not short-circuit.

Similarly, `yield(...)` can be used to provide output from the coroutine:

```haxe
var languages = co({
  yield("Haxe");
  yield("Haxe 4");
}, null, (_ : String)).run();
trace('${languages.take()} is awesome!'); // outputs Haxe is awesome!
trace('${languages.take()} is awesome!'); // outputs Haxe 4 is awesome!
```

A coroutine can both accept inputs and yield outputs, and the types of the two do not have to be the same. `accept` and `yield` are blocking calls – the coroutine will be suspended until data is given to it or taken from it respectively. Additionally, some part of the expression inside `yield` may not be executed at all until `take()` is called (except for sub-expressions which are also suspending, so `yield(accept())` will accept, *then* yield).

### Defining custom input functions

It is possible to declare methods similar to `accept`. These methods must:

 - have the `:pecan.accept` metadata
 - take the coroutine `pecan.ICo<...>` as their last argument, ideally optional
 - take a function `T->Void` as their second-to-last argument, ideally optional
 - return the same type `T` (but the return value is not used!)

Functions declared this way can then be called from within coroutines, with the last two arguments filled in automatically.

An example defining a delay that eventually returns a `String`:

```haxe
class Foobar {
  @:pecan.accept public static function acceptDelay<T, U>(ms:Int, ?ret:String->Void, ?co:pecan.ICo<T, U>):String {
    haxe.Timer.delay(() -> {
      ret("foo");
      co.wakeup();
    }, ms);
    co.suspend();
    return null;
  }
}
```

Then:

```haxe
co({
  trace("Hello,");
  var x = Foobar.acceptDelay(1000);
  trace(x); // foo
}).run().tick();
```

Note that the return type of the method exists solely for type checking purposes. The function should always return `null` (or an appropriate default value for basic types on static targets), and return the real value by calling the function passed as an argument.

### Labels

Labels can be declared inside coroutine bodies with the `label(<string>)` syntax. Labels identify positions in the coroutine code that can be jumped to with a `goto` call.
  
```haxe
var weather = co({
  label("sunny");
  while (true) yield("It's sunny!");
  label("rainy");
  while (true) yield("It's rainy!");
}, null, (_:String)).run();
trace(weather.take()); // It's sunny!
trace(weather.take()); // It's sunny!
weather.goto("rainy");
trace(weather.take()); // It's rainy!
weather.goto("sunny");
trace(weather.take()); // It's sunny!
```

Label names must be a constant string expression.

### API

`pecan.ICo<TIn, TOut>` is the interface of a coroutine, as created by the `pecan.Co.co` expression macro. `TIn` is the input type, `TOut` is the output type - `Void` is used for no input or no output. A coroutine exists in one of these states (`pecan.Co.CoState`):

 - `Ready` - ready to execute actions, can be invoked to run with `tick`.
 - `Suspended` - (temporarily) suspended, may wake up later to become `Ready`.
 - `Terminated` - no more actions will be executed.
 - `Accepting` - waiting for a value of type `TIn`, can be provided with `give`.
 - `Yielding` - ready to give a value of type `TOut`, can be accepted with `take`.

#### `public static function tick():Void`

If the coroutine is `Ready`, execute actions starting from the current position until done or switched to a different state.

Otherwise this function has no effect.

#### `public static function wakeup():Void`

Wake up a `Suspended` or `Ready` coroutine, then follow with a `tick`.

#### `public static function terminate():Void`

Stop executing actions immediately (when called from within the coroutine), set coroutine to `Terminated`.

#### `public static function give(value:TIn):Void`

`tick`, then if the coroutine is in an `Accepting` state, give it `value`.

#### `public static function take():TOut`

`tick`, then if the coroutine is in a `Yielding` state, return the emitted value.

#### `public static function goto(label:String):Void`

Move the coroutine to the given label, then `tick`.
