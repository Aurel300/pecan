package test;

import pecan.Co.co;
import utest.Async;

class TestCoroutine extends Test {
  /**
    Proper call order:
    - 0 - called after coroutine is created but before coroutine is ticked
    - 1 - first tick in coroutine
    - 2 - coroutine was suspended, call after the tick
    - 3 - coroutine woken up with a call
    - 4 - coroutine woken up with a timer
  **/
  function testOrder(async:Async) {
    var calls = [];
    var c = co({
      calls.push(1);
      if (true) {
        if (false) {
          calls.push(-1);
        } else {
          suspend();
        }
      } else {
        calls.push(-1);
      }
      calls.push(3);
      suspend((self, wakeup) -> haxe.Timer.delay(wakeup, 1));
      calls.push(4);
      aeq(calls, [0, 1, 2, 3, 4]);
      async.done();
    }).run();
    calls.push(0);
    c.tick();
    calls.push(2);
    c.wakeup();
  }

  /**
    Variable scoping.
  **/
  function testVars() {
    co({
      var a = 3;
      var b = 4;
      eq(a, 3);
      eq(b, 4);

      // some ops
      eq(a + b, 7);
      eq(a - b, -1);
      eq(a * b, 12);
      eq(++a, 4);
      eq(a++, 4);
      eq(a, 5);
      t(a == b + 1);
      eq(a - 1 == b ? 1 : 2, 1);

      // `a` here should shadow the first `a`
      var a = 5;
      eq(a, 5);
      eq(b, 4);

      {
        // `a` here shadows the previous `a` but only inside this block
        var a = 7;
        eq(a, 7);
      }

      // back to the previous `a`
      eq(a, 5);

      // switch cases are also scopes
      switch (a) {
        case 3:
          var a = 3;
          assert();
        case 5:
          eq(a, 5);
          var a = 6;
          eq(a, 6);
        case _:
          assert();
      }

      // back to the previous `a`
      eq(a, 5);

      // different type
      var a = "foo";
      eq(a, "foo");
    }).run().tick();
  }

  /**
    Coroutine states and state errors.
  **/
  function testStates() {
    var c = co({
      suspend();
      var a = accept();
      yield(0);
    }, (_ : Int), (_ : Int)).run();
    eq(c.state, Ready);
    exc(() -> c.give(0));
    exc(() -> c.take());
    c.tick();
    eq(c.state, Suspended);
    exc(() -> c.give(0));
    exc(() -> c.take());
    c.tick();
    eq(c.state, Suspended);
    c.wakeup();
    t(c.state.match(Accepting(_)));
    c.tick();
    t(c.state.match(Accepting(_)));
    exc(() -> c.take());
    exc(() -> c.wakeup());
    c.give(0);
    t(c.state.match(Yielding(_)));
    exc(() -> c.give(0));
    exc(() -> c.wakeup());
    c.take();
    eq(c.state, Terminated);
    exc(() -> c.wakeup());
    exc(() -> c.give(0));
    exc(() -> c.take());

    var c = co({
      terminate();
      assert("fail");
    }, (_ : Int)).run();
    c.tick();
    eq(c.state, Terminated);
    c.tick();
    eq(c.state, Terminated);
    exc(() -> c.wakeup());
    exc(() -> c.give(0));
    exc(() -> c.take());
  }

  /**
    Data input and output.
  **/
  function testIO() {
    // input only
    var c = co({
      var a = "foo";
      eq(a, "foo");
      a = accept();
      eq(a, "bar");
      if (true) {
        var a = accept();
        eq(a, "hello");
      }
      eq(a, "bar");
    }, (_ : String)).run();
    c.give("bar");
    c.give("hello");

    // output only
    var c = co({
      yield("foo");
      var a = "bar";
      yield(a);
    }, null, (_ : String)).run();
    eq(c.take(), "foo");
    eq(c.take(), "bar");

    // both input and output
    var c = co({
      yield(0);
      var a = accept();
      eq(a, 1);
      yield(a + 1);
    }, (_ : Int), (_ : Int)).run();
    eq(c.take(), 0);
    c.give(1);
    eq(c.take(), 2);

    // combined assignment operator
    var c = co({
      var a = 3;
      a += accept();
      eq(a, 4);
    }, (_ : Int)).run();
    c.give(1);
  }

  function testSyntax() {
    // if/else blocks
    var c = co({
      if (true) {
        suspend();
        if (false) {
          eq(1, 0);
        } else {
          suspend();
          if (true) {
            suspend();
            eq(1, 1);
          }
        }
      } else {
        suspend();
        eq(1, 0);
      }
    }).run();
    c.tick();
    c.wakeup();
    c.wakeup();
    c.wakeup();

    // loops
    var c = co({
      var counter = 0;
      while (true) yield(counter++);
    }, null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.take(), 1);
    eq(c.take(), 2);
    t(c.state.match(Yielding(_)));

    var c = co({
      while (false) yield(0);
    }, null, (_ : Int)).run();
    c.tick();
    eq(c.state, Terminated);

    var c = co({
      do yield(0) while (false);
    }, null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.state, Terminated);

    var c = co({
      var counter = 0;
      while (counter < 3) yield(counter++);
    }, null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.take(), 1);
    eq(c.take(), 2);
    eq(c.state, Terminated);

    var c = co({
      var counter = 0;
      do yield(counter++) while (counter < 3);
    }, null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.take(), 1);
    eq(c.take(), 2);
    eq(c.state, Terminated);

    var c = co({
      var counter = 0;
      do {
        // yield first in block
        yield(counter++);
        1 + 1;
      } while (counter < 3);
    }, null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.take(), 1);
    eq(c.take(), 2);
    eq(c.state, Terminated);

    var c = co({
      var counter = 0;
      do {
        // yield last in block
        1 + 1;
        yield(counter++);
      } while (counter < 3);
    }, null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.take(), 1);
    eq(c.take(), 2);
    eq(c.state, Terminated);

    var c = co({
      for (i in 0...3) {
        yield(i);
      }
    }, null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.take(), 1);
    eq(c.take(), 2);
    eq(c.state, Terminated);

    var c = co({
      for (i in [0, 1, 2]) yield(i);
    }, null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.take(), 1);
    eq(c.take(), 2);
    eq(c.state, Terminated);

    // without a block
    var c = co(for (i in [0, 1, 2]) yield(i), null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.take(), 1);
    eq(c.take(), 2);
    eq(c.state, Terminated);
  }
}
