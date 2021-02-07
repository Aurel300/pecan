package pecan.internal;

#if macro

/**
Typed AST tools.
 */
class TastTools {
  public static var pos:Position;

  public static var typeInt = Context.resolveType((macro : Int), (macro null).pos);
  public static var typeFloat = Context.resolveType((macro : Float), (macro null).pos);
  public static var typeBool = Context.resolveType((macro : Bool), (macro null).pos);
  public static var typeVoid = Context.resolveType((macro : Void), (macro null).pos);
  public static var typeAny = Context.resolveType((macro : Any), (macro null).pos);

  public static function tint(n:Int):TypedExpr {
    return {
      expr: TConst(TInt(n)),
      pos: pos,
      t: typeInt,
    };
  }

  public static function tfloat(n:Float):TypedExpr {
    return {
      expr: TConst(TFloat('$n')),
      pos: pos,
      t: typeFloat,
    };
  }

  public static function tbool(n:Bool):TypedExpr {
    return {
      expr: TConst(TBool(n)),
      pos: pos,
      t: typeBool,
    };
  }

  public static function tnull(t:Type):TypedExpr {
    return {
      expr: TConst(TNull),
      pos: pos,
      t: t,
    };
  }

  public static function tassign(lhs:TypedExpr, rhs:TypedExpr):TypedExpr {
    return {
      expr: TBinop(OpAssign, lhs, rhs),
      pos: pos,
      t: rhs.t,
    };
  }

  public static function tlocal(v:TVar):TypedExpr {
    return {
      expr: TLocal(v),
      pos: pos,
      t: v.t,
    };
  }

  public static function treturn(e:TypedExpr):TypedExpr {
    return {
      expr: TReturn(e),
      pos: pos,
      t: typeVoid,
    };
  }

  public static function tvar(ident:String, ?type:Type, ?init:TypedExpr):{
    decl:TypedExpr,
    v:TVar,
  } {
    var e = (if (init != null) {
      Context.typeExpr(macro var $ident = $e{Context.storeTypedExpr(init)});
    } else if (type != null) {
      var t = Context.toComplexType(type);
      Context.typeExpr(macro var $ident:$t);
    } else {
      throw "!";
      Context.typeExpr(macro var $ident);
    });
    return {
      decl: e,
      v: switch (e.expr) {
        case TVar(tv, _): tv;
        case _: throw "!";
      },
    };
  }

  public static function tdeclare(v:TVar):TypedExpr {
    return {
      expr: TVar(v, switch (v.t) {
        case TAbstract(_.get().name => "Int", []): tint(0);
        case TAbstract(_.get().name => "Bool", []): tbool(false);
        case TAbstract(_.get().name => "Float", []): tfloat(0);
        case TAbstract(_.get().name => "Void", []): null;
        case _: tnull(v.t);
      }),
      pos: pos,
      t: typeVoid,
    };
  }

  public static function tblock(es:Array<TypedExpr>, ?cpos:Position):TypedExpr {
    if (cpos == null)
      cpos = es.length > 0 ? es[0].pos : pos;
    if (es.length == 0) {
      return {pos: cpos, t: typeVoid, expr: TBlock([])};
    }
    es = es.map(e -> switch (e.expr) {
      case TBlock(es): es;
      case _: [e];
    }).flatten();
    if (es.length == 1)
      return es[0];
    return {pos: cpos, t: es[0].t, expr: TBlock(es)};
  }
}

#end
