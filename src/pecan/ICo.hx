package pecan;

/**
Interface for any generated coroutine instance.

The type parameter `TIn` represents values that the coroutine can `accept()`,
`TOut` represents values that the coroutine can `yield(...)`, and `TRet`
represents the return value.
 */
interface ICo<TIn, TOut, TRet> {
  /**
  Current state of the coroutine.
   */
  var state(get, never):CoState;

  /**
  Value returned by the coroutine, if available. `null` otherwise.
   */
  var returned(get, never):Null<TRet>;

  /**
  Callback invoked when the coroutine terminates in any manner. This field
  should never be set to `null`.

  Note that adding a callback after a coroutine has finished has no effect.
  This may be important for coroutines that do not suspend at all between their
  invocation and their termination. The callback can be set after a
  `runSuspended(...)` call to avoid this problem.
   */
  var onHalt:()->Void;

  /**
  Moves the coroutine forward until a suspend point is hit, but only if it was
  in a `Ready` state to begin with. Does nothing otherwise.
   */
  function tick():Void;

  /**
  Suspends the coroutine, stopping its execution, and changes its state to
  `Suspended`.
   */
  function suspend():Void;

  /**
  Wakes up and `tick`s a coroutine from a `Ready` or `Suspended` state.
   */
  function wakeup():Void;

  /**
  Terminates the coroutine, stopping its execution, and changes its state to
  `Terminated`. A terminated coroutine may not be woken up again.
   */
  function terminate():Void;

  /**
  Gives a value to a coroutine in an `Accepting` state. This should be called
  when a coroutine expects a value from an `accept()` call. The coroutine is
  `tick`ed beforehand.
   */
  function give(value:TIn):Void;

  /**
  Takes a value from a coroutine in a `Yielding` state. This should be called
  when a coroutine is providing a value using a `yield(...)` call. The
  coroutine is `tick`ed beforehand.
   */
  function take():TOut;

  /**
  Goes to a label defined in the coroutine with a `label("...")` point, then
  `tick`. Throws an exception if the label does not exist.
   */
  function goto(label:String):Void;
}
