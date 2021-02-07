package test;

import pecan.Co.co;
import utest.Async;

using test.TestExtension.ExtraStaticExtension;

class TestExtension extends Test {
  function testDelay(async:Async) {
    var done = false;
    co({
      eq(done, false);
      Extra.delay(10);
      done = true;
      async.done();
    }).runSuspended().tick();
    eq(done, false);
  }

  function testDelayStaticExtension(async:Async) {
    var done = false;
    co({
      eq(done, false);
      10.delay();
      done = true;
      async.done();
    }).runSuspended().tick();
    eq(done, false);
  }

  function testDelayInstance(async:Async) {
    var delayer = new ExtraInstance(10);
    var done = false;
    co({
      eq(done, false);
      delayer.delay();
      done = true;
      async.done();
    }).runSuspended().tick();
    eq(done, false);
  }

  function testNop() {
    var c = co({
      Extra.nop();
    }).runSuspended();
    c.tick();
    eq(c.state, Terminated);
  }

  function testAccept(async:Async) {
    var done = false;
    co({
      eq(done, false);
      var x = Extra.accept(10);
      done = true;
      eq(x, 42);
      async.done();
    }).runSuspended().tick();
    eq(done, false);
  }
}

class Extra {
  @:pecan.action public static function delay<T, U, V>(delay:Int, ?co:pecan.ICo<T, U, V>):Void {
    haxe.Timer.delay(co.wakeup, delay);
    co.suspend();
  }

  @:pecan.accept public static function accept<T, U, V>(delay:Int, ?ret:Int->Void, ?co:pecan.ICo<T, U, V>):Int {
    haxe.Timer.delay(() -> {
      ret(42);
      co.wakeup();
    }, delay);
    co.suspend();
    return 0;
  }

  @:pecan.action public static function nop<T, U, V>(?co:pecan.ICo<T, U, V>):Void {}
}

class ExtraStaticExtension {
  @:pecan.action public static function delay<T, U, V>(delay:Int, ?co:pecan.ICo<T, U, V>):Void {
    haxe.Timer.delay(co.wakeup, delay);
    co.suspend();
  }
}

class ExtraInstance {
  var time:Int;

  public function new(time:Int) {
    this.time = time;
  }

  @:pecan.action public function delay<T, U, V>(?co:pecan.ICo<T, U, V>):Void {
    haxe.Timer.delay(co.wakeup, time);
    co.suspend();
  }
}
