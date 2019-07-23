package pecan;

class CoAction<TIn, TOut> {
  public final kind:CoActionKind<TIn, TOut>;
  public final pos:haxe.PosInfos;

  public function new(kind:CoActionKind<TIn, TOut>, ?pos:haxe.PosInfos) {
    this.kind = kind;
    this.pos = pos;
  }

  public function toString():String {
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

enum CoActionKind<TIn, TOut> {
  Sync(_:(self:Co<TIn, TOut>) -> Void);
  Suspend(?_:(self:Co<TIn, TOut>, wakeup:() -> Void) -> Bool);
  Block(_:Array<CoAction<TIn, TOut>>);
  If(cond:(self:Co<TIn, TOut>) -> Bool, eif:Array<CoAction<TIn, TOut>>, ?eelse:Array<CoAction<TIn, TOut>>);
  While(cond:(self:Co<TIn, TOut>) -> Bool, _:Array<CoAction<TIn, TOut>>, normalWhile:Bool);
  Accept(_:(self:Co<TIn, TOut>, value:TIn) -> Void);
  Yield(_:(self:Co<TIn, TOut>) -> TOut);
}
