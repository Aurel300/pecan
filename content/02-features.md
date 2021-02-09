<!--menu:Features-->
<!--label:features-->
# Features

This chapter describes the various features of `pecan` in more depth.

<!--label:features-declaration-->
## Declaration

Coroutines are declared using the `pecan.Co.co` expression macro. The macro takes between 1 and 3 arguments:

 1. the body of the coroutine,
 2. (optional) the input type, and
 3. (optional) the output type.

The 1st argument can either be a Haxe expression (usually a block expression), or a function. The latter case allows declaring arguments (see [invoking](features-invoking)) and explicitly annotating return types (see [states](features-states#return)).

Within the code block, these variables and functions are implicitly available:

 - `self` - refers to the current instance of [`pecan.ICo<...>`](api-pecan-ico).
 - `suspend()` and `terminate()` - see [suspending](features-suspending).
 - `accept()` and `yield(...)` - see [I/O](features-io).
 - `label(...)` - see [labels](features-labels).

<div class="example">

### Example: coroutine declarations and arguments

```haxe
// takes two arguments whose types are inferred, return type is also inferred
pecan.Co.co((a, b) -> { ... });

// takes two arguments (second is optional), returns `String`
pecan.Co.co(function(a, ?b:Int):String { ... });
```
</div>

Both the 2nd and 3rd arguments may be `null` or `(_ : T)` where `T` is a type.

<div class="example">

### Example: combinations of I/O types

```haxe
// no input or output:
pecan.Co.co({ ... });
// input but no output:
pecan.Co.co({ ... }, (_ : Int));
// output but no input:
pecan.Co.co({ ... }, null, (_ : Int));
// both input and output
pecan.Co.co({ ... }, (_ : Int), (_ : Int));
```
</div>

### Syntax helpers

`pecan` provides some syntax shorthands. To use it within a class, implement the interface `pecan.Syntax`.

<div class="example">

### Example: using the syntax helper

```haxe
class Example implements pecan.Syntax { ... }
```
</div>

The syntax shorthands are:

| Syntax | Equivalent to |
| ------ | ------------- |
| `!{ ... }` | `pecan.Co.co({ ... }).run()` |
| `!function():T { ... }` | `pecan.Co.co(function():T { ... }).run()` |
| `@:pecan.co(io...) function x(args...):T { ... }` | `function x(args...) return pecan.Co.co(function(args...) { ... }, io...).run(args...);` |

<div class="example">

### Example: `!` prefix for immediately invoked coroutines

```haxe
var co = !{
  trace("foo");
  suspend();
  trace("bar");
};
co.wakeup();
```
</div>

<div class="example">

### Example: `!` prefix for immediately invoked coroutines with explicit return type

```haxe
var co = !function():String {
  suspend();
  return "hello";
};
co.wakeup();
```

Note that the return type is inferred, so this example would work without the `function` as well. However, there may be some cases where an explicit type hint is required for correct compilation.
</div>

<div class="example">

### Example: `@:pecan.co` methods

The syntax also allows declaring class methods as coroutines, using the `:pecan.co` metadata. The metadata may optionally take up to two arguments, representing the input and output types (same as the 2nd and 3rd arguments of `pecan.Co.co`):

```haxe
class Example implements pecan.Syntax {
  @:pecan.co function noInputNoOutput() {
    suspend();
    // ...
  }
  @:pecan.co((_ : Int)) function acceptsInts() { ... }
  @:pecan.co(null, (_ : String)) function yieldsStrings() { ... }
}
```

A call to a method thusly annotated is equivalent to a call to [`run(...)`](features-invoking), i.e. it will return a coroutine instance.
</div>

<!--label:features-invoking-->
## Invoking

To invoke a declared coroutine, call `run(...)`. The arguments of `run` correspond to the arguments declared in the coroutine. The `run` call returns an instance of the coroutine, which will be of type [`pecan.ICo<...>`](api-pecan-ico).

<div class="example">

### Example: `run()` call with no arguments

```haxe
var noArgs = pecan.Co.co({
  trace("no arguments...");
});
noArgs.run(); // output: no arguments...
noArgs.run(); // output: no arguments...
```
</div>

<div class="example">

### Example: `run(...)` call with arguments

```haxe
withArgs = pecan.Co.co((a:String) -> {
  trace('called with $a');
});
withArgs.run("x"); // output: called with x
withArgs.run("y"); // output: called with y
```
</div>

By default, `run(...)` will start and immediately [`tick()`](api-pecan-ico#tick) the coroutine. If instead the coroutine should be started in a [suspended state](features-states), the `runSuspended(...)` method with the same signature can be used.

<div class="example">

### Example: `runSuspended()`

```haxe
var factory = pecan.Co.co({ trace("2"); });
var instance = factory.runSuspended();
trace("1");
instance.tick();
trace("3");
// output: 1, 2, 3
```
</div>

<!--label:features-suspending-->
## Suspending calls

The ability to suspend and later resume execution is the most important aspect of a coroutine. There are multiple ways to suspend a coroutine:

 - [`suspend()`](features-suspending#suspend),
 - [`terminate()`](features-suspending#terminate),
 - [`accept()`](features-io#input) or [`yield(...)`](features-io#output), or
 - a call to a [`@:pecan.action`](features-suspending#custom) or [`@:pecan.accept` function](features-io#custom)

<!--sublabel:suspend-->
### `suspend()`

The `suspend()` call is always available within a coroutine body. It simply suspends the coroutine until it is woken up again externally with a [`wakeup()`](api-pecan-ico#wakeup) call.

<div class="example">

### Example: `suspend()` call

```haxe
var co = pecan.Co.co({
  trace(1);
  suspend();
  trace(3);
}).run();
trace(2);
co.wakeup();
// output: 1, 2, 3
```
</div>

<!--sublabel:terminate-->
### `terminate()`

The `terminate()` call stops execution of the coroutine immediately, and prevents it from being woken up again. No error is thrown and the [`returned` field](features-states#return) is not updated.

<div class="example">

### Example: `terminate()` call

```haxe
var co = pecan.Co.co({
  trace(1);
  suspend();
  terminate();
  trace(3);
}).run();
trace(2);
co.wakeup();
// output: 1, 2
```
</div>

<!--sublabel:custom-->
### Custom suspending functions

It is possible to declare methods as suspending. These methods must:

 - have the `:pecan.action` metadata and
 - take the coroutine [`pecan.ICo<...>`](api-pecan-ico) as their last argument, ideally optional.

Functions declared this way can then be called from within coroutines, with the last argument being replaced by the coroutine instance automatically.

<div class="example">

### Example: `haxe.Timer.delay` as a suspending function

```haxe
class Foobar {
  @:pecan.action public static function delay(
    ms:Int,
    ?co:pecan.ICo<Any, Any, Any>
  ):Void {
    haxe.Timer.delay(co.wakeup, ms);
    co.suspend();
  }
}
```

Usage:

```haxe
pecan.Co.co({
  trace("Hello,");
  Foobar.delay(1000); // one second delay
  trace("Haxe!");
}).run();
```
</div>

Note that a `@:pecan.action` function is not automatically suspending. If there is no [`co.suspend()`](api-pecan-ico#suspend) call, the coroutine will continue after the call as usual.

<!--label:features-io-->
## Input and output

Coroutines can `accept()` inputs and `yield(...)` outputs. To ensure type safety, the types for inputs and outputs must be declared as part of the `co` macro call (see [declaration](features-declaration)).

<!--sublabel:input-->
### Input

Within coroutine code, `accept()` can be used to accept input of the declared type. The call suspends the coroutine until the value is available.

<div class="example">

### Example: `accept()` usage

```haxe
var greeter = pecan.Co.co({
  trace('Hello, ${accept()}, from ${accept()}!');
}, (_ : String)).run();
greeter.give("Haxe");
greeter.give("pecan"); // output: Hello, Haxe, from pecan!
```
</div>

All `accept()` calls within an expression are evaluated before the expression itself. The evaluation order of complex expressions involving calls to `accept()` and other functions may therefore be different than expected. Boolean operators with `accept()` will not short-circuit.

<!--sublabel:output-->
### Output

Within coroutine code, `yield(...)` can be used to provide output from the coroutine. The call suspends the coroutine until the value is taken.

<div class="example">

### Example: `yield(...)` usage

```haxe
var languages = pecan.Co.co({
  yield("Haxe");
  yield("Haxe 4");
}, null, (_ : String)).run();
trace('${languages.take()} is awesome!'); // output: Haxe is awesome!
trace('${languages.take()} is awesome!'); // output: Haxe 4 is awesome!
```
</div>

<!--sublabel:custom-->
### Custom input functions

It is possible to declare methods similar to `accept`. These methods must:

 - have the `:pecan.accept` metadata;
 - take the coroutine [`pecan.ICo<...>`](api-pecan-ico) as their last argument, ideally optional;
 - take a function `T->Void` as their second-to-last argument, ideally optional; and
 - have a return type of the same type `T`.

Functions declared this way can then be called from within coroutines, with the last two arguments filled in automatically. The second-to-last argument is how the custom input function provides the "real" return value.

> The return value of the function is never used! It is only used for type inference. Returning `null` (or a default value on static targets) is recommended.

Unlike [custom suspending functions](features-suspending#custom), custom input functions always suspend the coroutine and always wake it up when the value is returned.

<div class="example">

### Example: delay that eventually returns a `String`

```haxe
class Foobar {
  @:pecan.accept public static function acceptDelay(
    ms:Int,
    ?ret:String->Void,
    ?co:pecan.ICo<Any, Any, Any>
  ):String {
    haxe.Timer.delay(() -> ret("foo"), ms);
    return null;
  }
}
```

Usage:

```haxe
pecan.Co.co({
  trace("Hello,");
  var x = Foobar.acceptDelay(1000);
  trace(x); // output: foo
}).run();
```
</div>

<!--label:features-labels-->
## Labels

Labels can be declared inside coroutine bodies with the `label(...)` call. Labels identify positions in the coroutine code that can be jumped to with a [`goto(...)`](api-pecan-ico#goto) call. Label names must be a constant string expression.

<div class="example">

### Example: `label(...)` and `goto(...)` usage

```haxe
var weather = pecan.Co.co({
  label("sunny");
  while (true) yield("sunny!");
  label("rainy");
  while (true) yield("rainy!");
}, null, (_:String)).run();
trace(weather.take()); // output: sunny!
trace(weather.take()); // output: sunny!
weather.goto("rainy");
trace(weather.take()); // output: rainy!
weather.goto("sunny");
trace(weather.take()); // output: sunny!
```
</div>

<!--label:features-states-->
## States

Any coroutine instance is in one of the following states, which can be checked with the [`state`](api-pecan-ico#state) variable:

 - `Ready` - running or just created with [`runSuspended(...)`](features-invoking) and not yet `tick()`ed.
 - `Suspended` - suspended with a [`suspend()`](features-suspending) call (or similar).
 - `Accepting` - waiting for a value after an [`accept()`](features-io#input) call.
 - `Yielding` - waiting to provide a value with a [`yield(...)`](features-io#output) call.
 - `Expecting` - waiting for a value after a [custom accept call](features-io#custom).
 - `Terminated` - finished, cannot be woken up again.

<!--sublabel:return-->
### Return value

If a coroutine terminated with a `return` statement, the returned value is available in the [`returned`](api-pecan-ico#returned) field. Otherwise, the field is set to `null`. Coroutines that return `Void` will have `returned` with a type of `pecan.Void`.

<div class="example">

### Example: `returned` usage

```haxe
var adder = pecan.Co.co(function():String {
  var x = accept();
  var y = accept();
  return '$x + $y = ${x + y}';
}, (_ : Int));

var instance = adder.run();
instance.give(1);
instance.give(2);
trace(instance.returned); // output: 1 + 2 = 3
```
</div>
