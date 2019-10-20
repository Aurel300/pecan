# `pecan`

`pecan` is a library for [Haxe](https://github.com/HaxeFoundation/haxe) that provides two features:

 - **coroutines** - suspendable functions with serialisable state
 - **event-condition-action** - a system to specify "triggers" for various events (TODO)

---

 - [Coroutines](#coroutines)
   - [Suspending](#suspending)
   - [Defining suspending functions](#defining-suspending-functions)
   - [Arguments](#arguments)
   - [I/O](#io)
   - [API](#api)
   - [Limitations](#limitations)
   - [Internals](#internals)

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

A coroutine differs from a regular function in that a "call" is not a single event, but rather a single instance of a coroutine can exist for a long time. Hence the `co` macro returns a factory `pecan.CoFactory<...>`, which is analogous to a function declaration. The `run` method of a factory can be used to obtain a new instance of the coroutine `pecan.Co<...>`, analogous to a function call.

Within the code block, there are some special variables and constructs available:

 - `self` - refers to the current instance of `pecan.Co`.
 - `suspend()`, `suspend(f)`, and `terminate()` - see [suspending](#suspending).
 - `accept()` and `yield(<expr>)` - see [I/O](#io).

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

The `suspend` call can optionally take a single argument, which should be a function with the signature `(self:pecan.Co<...>, wakeup:() -> Void) -> Void`.

(TODO: this seems a bit useless now, since the `wakeup` call can simply be scheduled immediately before the `suspend` call.)

Coroutines can also be terminated completely, which means they cannot be woken up again. This is achieved with the `terminate()` call.

### Defining suspending functions

It is possible to declare methods as suspending. These methods must be marked with the `:pecan.suspend` metadata, they must take the coroutine `pecan.Co<...>` and its wakeup function `()->Void` as their last two arguments, and they must return `Bool`, indicating whether or not the coroutine should be suspended following the call.

Functions declared this way can then be called from within coroutines, and they will suspend the coroutine as needed.

An example to use `haxe.Timer.delay` as a suspending function:

```haxe
class Foobar {
  @:pecan.suspend public static function delay<T, U>(ms:Int, co:pecan.Co<T, U>, wakeup:()->Void):Bool {
    haxe.Timer.delay(wakeup, ms);
    return true;
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

Arguments can be optional, in which case they should be prefixed with `?` and have a default value. Any non-optional argument must have a type hint.

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

All `accept()` calls within an expression are evaluated first. `true ? accept() : accept()` requires two values, even though only the first one will be used.

Similarly, `yield(...)` can be used to provide output from the coroutine:

```haxe
var languages = co({
  yield("Haxe");
  yield("Haxe 4");
}, null, (_ : String)).run();
trace('${languages.take()} is awesome!'); // outputs Haxe is awesome!
trace('${languages.take()} is awesome!'); // outputs Haxe 4 is awesome!
```

A coroutine can both accept inputs and yield outputs, and the types of the two do not have to be the same. Keep in mind that `accept` and `yield` are blocking calls – the coroutine will be suspended until data is given to it or taken from it respectively. Additionally, the expression inside `yield` will not be executed at all until `take()` is called (except for sub-expressions which are also suspending, so `yield(accept())` will accept, *then* yield).

### API

`pecan.Co<TIn, TOut>` is the type of a coroutine, as created by the `pecan.Co.co` expression macro. `TIn` is the input type, `TOut` is the output type - `Void` is used for no input or no output. A coroutine exists in one of these states (`pecan.Co.CoState`):

 - `Ready` - ready to execute actions, can be invoked to run with `tick`.
 - `Suspended` - (temporarily) suspended, may wake up later to become `Ready`.
 - `Terminated` - no more actions will be executed.
 - `Accepting(...)` - waiting for a value of type `TIn`, can be provided with `give`.
 - `Yielding(...)` - ready to give a value of type `TOut`, can be accepted with `take`.

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

### Limitations

 - all variable declarations must either have a type hint or an expression
 - `self`, `accept`, `yield`, `suspend`, and `terminate` are "magical" constructs that work as documented, but cannot e.g. be bound with `bind` or treated like proper functions

### Internals

The implementations for `pecan` coroutines consists of two separate parts: [the macro `pecan.Co.co`](src/pecan/Co.macro.hx), which transforms a regular Haxe code block to an array of actions; and [the runtime `pecan.Co`](src/pecan/Co.hx), which executes the actions.

At runtime, coroutines are represented as arrays of `pecan.CoAction`. The various different kinds of actions are expressed with the `enum` `pecan.CoAction.CoActionKind`:

 - `Sync(f, next)` - a synchronous call; `f` is called and the instruction pointer moves to `next`.
 - `Suspend(?f, next)` - a potentially suspending call. If the call to `f` returns `true`, the coroutine is suspended and can be waken up by calling the wakeup callback (given as an argument to `f`) later. If `f` is `null`, the coroutine is always suspended. Once the coroutine is woken up, the instruction pointer moves to `next`.
 - `If(cond, nextIf, nextElse)` - a conditional; `f` is called and the instruction pointer moves to `nextIf` or `nextElse`, depending on the result of the call.
 - `Accept(f, next)` - switch to `Accepting` state and call `f` once a value is accepted (given to the coroutine with a `give` call). Once the coroutine is given a value, the instruction pointer moves to `next`.
 - `Yield(f, next)` - switch to `Yielding` state and call `f` when a value is taken from the coroutine (with a `take` call). Once a value is taken from the coroutine, the instruction pointer moves to `next`.

Every coroutine definition results in the definition of a subclass of `pecan.CoVariables`, which contains as fields all the local variables declared in the coroutine. The names of the fields are `_coLocal<number>`; shadowed variables result in separate `_coLocal` fields and are referenced according to proper Haxe scoping rules.
