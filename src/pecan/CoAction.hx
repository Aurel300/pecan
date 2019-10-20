package pecan;

/*
class CoAction<TIn, TOut> {
  public final kind:CoActionKind<TIn, TOut>;
  public final pos:haxe.PosInfos;

  public function new(kind:CoActionKind<TIn, TOut>, ?pos:haxe.PosInfos) {
    this.kind = kind;
    this.pos = pos;
  }

  public function toString():String {
    return "todo";
    function indent(s:String):String {
      return s.split("\n").map(l -> '  $l').join("\n");
    }
    function indentBlock(as:Array<CoAction<TIn, TOut>>):String {
      return "{\n" + [for (a in as) indent(a.toString())].join("\n") + "\n}";
    }
    return switch (kind) {
      case Sync(_): "sync";
      case Suspend(_): "suspend";
      case Block(as): indentBlock(as);
      case If(_, eif, eelse):
        "if (...) " + indentBlock(eif) + (eelse != null ? " else " + indentBlock(eelse) : "");
      case While(_, as, normalWhile):
        normalWhile ? "while (...) " + indentBlock(as) : "do " + indentBlock(as) + " while (...)";
      case Accept(_): "accept";
      case Yield(_): "yield";
    };
  }
}
*/

enum CoAction<TIn, TOut> {
  Sync(_:(self:Co<TIn, TOut>) -> Void, next:Int);
  Suspend(?_:(self:Co<TIn, TOut>, wakeup:() -> Void) -> Bool, next:Int);
  If(cond:(self:Co<TIn, TOut>) -> Bool, nextIf:Int, nextElse:Int);
  Accept(_:(self:Co<TIn, TOut>, value:TIn) -> Void, next:Int);
  Yield(_:(self:Co<TIn, TOut>) -> TOut, next:Int);
}
