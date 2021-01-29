package pecan.internal;

#if macro

// TODO: shorthand syntax for inputs, outputs, or arguments?

class Syntax {
  public static function build():Array<Field> {
    var fields = Context.getBuildFields();
    return [ for (field in fields) {
      switch (field.kind) {
        case FFun(f):
          if (f.expr != null) {
            f.expr = process(f.expr);
          }
        case _:
      }
      field;
    } ];
  }

  static function process(e:Expr):Expr {
    return (switch (e.expr) {
      case EUnop(OpNot, false, e = {expr: EBlock(_)}):
        macro {
          var _co = pecan.Co.co($e{process(e)}, null, null).run();
          _co.tick();
          _co;
        };
      case _: ExprTools.map(e, process);
    });
  }
}

#end
