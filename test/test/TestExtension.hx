package test;

import pecan.Co.co;
import utest.Async;

class TestExtension extends Test {
  function testDelay(async:Async) {
    var done = false;
    co({
      Extra.delay(50);
      eq(done, false);
      done = true;
      async.done();
    }).run().tick();
    eq(done, false);
  }

  function testNop() {
    var c = co({
      Extra.nop();
    }).run();
    c.tick();
    eq(c.state, Terminated);
  }
}

class Extra {
  @:pecan.suspend public static function delay<T, U>(delay:Int, co:pecan.Co<T, U>, wakeup:()->Void):Bool {
    haxe.Timer.delay(wakeup, delay);
    return true;
  }

  @:pecan.suspend public static function nop<T, U>(co:pecan.Co<T, U>, wakeup:()->Void):Bool {
    return false;
  }
}
