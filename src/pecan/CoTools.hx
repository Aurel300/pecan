package pecan;

class CoTools {
  @:pecan.accept public static function await<T:haxe.Constraints.NotVoid>(
    target:ICo<Any, Any, T>,
    ?ret:T->Void,
    ?co:ICo<Any, Any, Any>
  ):T {
    if (target.state == Terminated) {
      // TODO: separate state for non-error termination?
      ret(target.returned);
      return null;
    }
    var old = target.onHalt;
    target.onHalt = () -> {
      ret(target.returned);
      co.wakeup();
      old();
    };
    co.suspend();
    return null;
  }
}
