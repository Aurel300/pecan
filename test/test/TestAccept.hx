package test;

import pecan.Co.co;

class TestAccept extends Test {
  function testExpressions() {
    var c = co({
      var a = accept();
      eq(a, 0);
    }, (_ : Int)).run();
    c.tick();
    c.give(0);
    eq(c.state, Terminated);

    var c = co({
      var a = accept() + accept();
      eq(a, 3);
    }, (_ : Int)).run();
    c.tick();
    c.give(1);
    c.give(2);
    eq(c.state, Terminated);

    var c = co({
      if (accept()) {
        eq(1, 1);
      } else {
        eq(0, 1);
      }
    }, (_ : Bool)).run();
    c.tick();
    c.give(true);
    eq(c.state, Terminated);

    var c = co({
      var a = accept() ? 1 : 0;
      eq(1, 1);
    }, (_ : Bool)).run();
    c.tick();
    c.give(true);
    eq(c.state, Terminated);

    var c = co({
      var a = true ? accept() : accept();
      eq(1, 1);
    }, (_ : Int)).run();
    c.tick();
    c.give(1);
    c.give(2);
    eq(c.state, Terminated);

    var c = co({
      yield(accept() + 1);
    }, (_ : Int), (_ : Int)).run();
    c.tick();
    c.give(0);
    eq(c.take(), 1);
    eq(c.state, Terminated);
  }
}
