package pecan;

/**
Possible states for a coroutine. See `ICo.state`.
 */
enum CoState {
  Ready;
  Suspended;
  Terminated;
  Accepting;
  Yielding;
  Expecting;
}
