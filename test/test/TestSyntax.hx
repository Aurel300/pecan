package test;

import pecan.Co.co;

class TestSyntax extends Test implements pecan.Syntax {
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
