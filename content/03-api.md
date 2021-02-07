<!--menu:API-->
<!--label:api-->
# API

<!-- TODO: figure out a way to embed dox-like things automatically -->

<!--menu:pecan.ICo-->
<!--label:api-pecan-ico-->
## `pecan.ICo<...>`

`pecan.ICo<TIn, TOut, TRet>` is the interface of a coroutine.

The type parameter `TIn` represents values that the coroutine can `accept()`, `TOut` represents values that the coroutine can `yield(...)`, and `TRet` represents the return value.

<!--sublabel:state-->
### `public var state(get, never):pecan.CoState`

Current state of the coroutine.

 - `Ready` - ready to execute actions, can be invoked to run with `tick`.
 - `Suspended` - (temporarily) suspended, may wake up later to become `Ready`.
 - `Terminated` - no more actions will be executed.
 - `Accepting` - waiting for a value of type `TIn`, can be provided with `give`.
 - `Yielding` - ready to give a value of type `TOut`, can be accepted with `take`.

<!--sublabel:returned-->
### `public var returned(get, never):Null<TRet>`

Value returned by the coroutine, if available. `null` otherwise.

### `public var onHalt:()->Void`

Callback invoked when the coroutine terminates in any manner. This field should never be set to `null`.

Note that adding a callback after a coroutine has finished has no effect. This may be important for coroutines that do not suspend at all between their invocation and their termination. The callback can be set after a `runSuspended(...)` call to avoid this problem.

<!--sublabel:tick-->
### `public function tick():Void`

Moves the coroutine forward until a suspend point is hit, but only if it was in a `Ready` state to begin with. Does nothing otherwise.

<!--sublabel:suspend-->
### `public function suspend():Void`

Suspends the coroutine, stopping its execution, and changes its state to `Suspended`.

<!--sublabel:wakeup-->
### `public function wakeup():Void`

Wakes up and `tick`s a coroutine from a `Ready` or `Suspended` state.

<!--sublabel:terminate-->
### `public function terminate():Void`

Terminates the coroutine, stopping its execution, and changes its state to `Terminated`. A terminated coroutine may not be woken up again.

<!--sublabel:give-->
### `public function give(value:TIn):Void`

Gives a value to a coroutine in an `Accepting` state. This should be called when a coroutine expects a value from an `accept()` call. The coroutine is `tick`ed beforehand.

<!--sublabel:take-->
### `public function take():TOut`

Takes a value from a coroutine in a `Yielding` state. This should be called when a coroutine is providing a value using a `yield(...)` call. The coroutine is `tick`ed beforehand.

<!--sublabel:goto-->
### `public function goto(label:String):Void`

Goes to a label defined in the coroutine with a `label("...")` point, then `tick`. Throws an exception if the label does not exist.

<!--menu:pecan.CoTools-->
<!--label:api-pecan-cotools-->
## `pecan.CoTools`

`pecan.CoTools` provides static extension to `pecan.ICo<...>` instances. It is added to coroutine instances using `@:using(...)`, so it need *not* be imported with `using pecan.CoTools;`.

### `public static function await<T>(waitFor):T`

This is a [`@:pecan.accept`](features-io#custom) function that can be used from within a coroutine to wait for the completion of another coroutine.

<div class="example">

### Example: `await` usage

```haxe
var a = pecan.Co.co(function():String {
  suspend();
  return "Haxe";
}).run();
var b = pecan.Co.co({
  var result = a.await();
  trace('Hello, $result!');
}).run();
a.wakeup(); // output: Hello, Haxe!
```
</div>
