package pecan.internal;

#if macro

// TODO: shorthand syntax for inputs, outputs, or arguments?

class Syntax {
  public static function build():Array<Field> {
    var fields = Context.getBuildFields();
    return [ for (field in fields) {
      switch (field.kind) {
        case FFun(f) if (field.meta.exists(m -> m.name == ":pecan.co")):
          var e = {
            expr: EFunction(FAnonymous, f),
            pos: field.pos,
          };
          // keep original argument names when possible, but handle duplicates
          var names = [];
          for (a in f.args) {
            if (!names.contains(a.name)) {
              names.push(a.name);
            } else {
              var i = 0;
              while (names.contains('${a.name}_$i')) i++;
              names.push('${a.name}_$i');
            }
          }
          var callArgs = names.map(n -> macro $i{n});
          var declArgs = [ for (i => a in f.args) {
            value: a.value,
            type: a.type,
            opt: a.opt,
            name: names[i],
            meta: a.meta,
          } ];
          var meta = field.meta.find(m -> m.name == ":pecan.co");
          var typeIn = meta.params != null && meta.params[0] != null ? meta.params[0] : macro null;
          var typeOut = meta.params != null && meta.params[1] != null ? meta.params[1] : macro null;
          field.kind = FFun({
            ret: null,
            expr: macro return pecan.Co.co($e{process(e)}, $typeIn, $typeOut).run($a{callArgs}),
            args: declArgs,
          });
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
      case EUnop(OpNot, false, e = {expr: EFunction(_, f)}):
        f.expr = process(f.expr);
        macro {
          var _co = pecan.Co.co($e, null, null).run();
          _co.tick();
          _co;
        };
      case _: ExprTools.map(e, process);
    });
  }
}

#end
