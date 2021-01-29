package pecan;

import haxe.macro.Expr;

class Co {
  public static function co(block:Expr, ?eIn:Expr, ?eOut:Expr):Expr {
    return pecan.internal.CoContext.build(block, eIn, eOut, false);
  }

  public static function coDebug(block:Expr, ?eIn:Expr, ?eOut:Expr):Expr {
    return pecan.internal.CoContext.build(block, eIn, eOut, true);
  }
}
