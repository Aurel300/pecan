package pecan.internal;

#if macro

/**
Pretty printer for control-flow graphs.
 */
class CfgPrinter {
  public static function print(cfg:Cfg):String {
    var out = new StringBuf();
    var arr = cfg.enumerate();
    var printer = new haxe.macro.Printer();
    function num(next:Cfg):Int {
      return arr.indexOf(next);
    }
    function print(e:TypedExpr):String {
      return printer.printExpr(Context.getTypedExpr(e));
    }
    function printVar(v:TVar):String {
      return '${v.name} : ${printer.printComplexType(Context.toComplexType(v.t))}';
    }
    function tabVar(v:TVar):Void {
      if (v == null) {
        out.add("  (none)");
        return;
      }
      out.add("  " + printVar(v));
    }
    function tab(e:TypedExpr):Void {
      if (e == null) {
        out.add("  (none)");
        return;
      }
      out.add("  " + print(e).split("\n").join("\n  "));
    }
    out.add("\n");
    for (i in 0...arr.length) {
      out.add('C$i ');
      switch (arr[i].kind) {
        case Sync(e, next):
          out.add("Sync\n");
          tab(e);
          out.add('\n  -> C${num(next)}');
        case Goto(next): out.add('Goto -> C${num(next)}');
        case GotoIf(e, nextIf, nextElse):
          out.add("GotoIf\n");
          tab(e);
          out.add('\n  -> C${num(nextIf)}, C${num(nextElse)}');
        case GotoSwitch(e, cases, nextDef):
          out.add("GotoSwitch\n");
          tab(e);
          for (c in cases) {
            out.add('\n  (${c.values.map(print)}) -> C${num(c.next)}');
          }
          out.add('\n  default -> C${num(nextDef)}');
        case Accept(v, next):
          out.add("Accept\n");
          tabVar(v);
          out.add('\n  -> C${num(next)}');
        case Yield(e, next):
          out.add("Yield\n");
          tab(e);
          out.add('\n  -> C${num(next)}');
        case Suspend(next): out.add('Suspend -> C${num(next)}');
        case Label(label, next): out.add('Label($label) -> C${num(next)}');
        case Join(next): out.add('Join -> C${num(next)}');
        case Break(next): out.add('Break -> C${num(next)}');
        case Halt(e):
          out.add("Halt\n");
          tab(e);
      }
      var c = arr[i].catches;
      while (c != null) {
        out.add("\n  (catch group)");
        for (h in c.handlers) {
          out.add('\n  catch(${printVar(h.v)}) -> C${num(h.cfg)}');
        }
        c = c.parent;
      }
      out.add("\n\n");
    }
    return out.toString();
  }
}

#end
