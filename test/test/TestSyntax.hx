package test;

import pecan.Co.co;

class TestSyntax extends Test implements pecan.Syntax {
  @:pecan.co((_ : Int), (_ : String)) function coField(x:Int):Int {
    yield('x$x');
    suspend();
    var x = accept();
    return 2 + x;
  }

  function testField() {
    var c = coField(1);
    eq(c.state, Ready);
    c.tick();
    eq(c.take(), "x1");
    eq(c.state, Suspended);
    c.wakeup();
    c.give(5);
    eq(c.state, Terminated);
    eq(c.returned, 7);
  }

  function testSyntax() {
    var done = false;
    var a = 1;
    var c = !{
      eq(a, 1);
      a++;
      suspend();
      eq(a, 3);
      a++;
    };
    eq(a, 2);
    a++;
    c.wakeup();
    eq(a, 4);
  }
}
