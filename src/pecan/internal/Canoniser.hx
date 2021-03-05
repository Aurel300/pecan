package pecan.internal;

#if macro

import pecan.internal.TastTools.*;

/**
Converts a TAST into a simpler, "canonical" form, to make analysis simpler.
In the canonical form, complex expressions are deconstructed into multiple
simpler assignments to temporary variables, where the RHS of the assignment
conceptually performs a single "operation".
 */
class Canoniser {
  var ctx:CoContext;
  var pos:Position;

  public function new(ctx:CoContext) {
    this.ctx = ctx;
  }

  public function canonise(ast:TypedExpr):TypedExpr {
    return walkSub(ast, false);
  }

  function walkSub(e:TypedExpr, ?useResult:Bool = true, ?outVar:TypedExpr, ?simplifyBlock:Bool = true):TypedExpr {
    if (e == null)
      return null;
    var ret = [];
    ret.push(walk(e, ret, useResult, outVar));
    return tblock(ret);
  }

  // TODO: tempvars seem to create duplicate tlocals in the output
  function walk(e:TypedExpr, pre:Array<TypedExpr>, ?useResult:Bool = true, ?outVar:TypedExpr):TypedExpr {
    if (e == null)
      return null;
    TastTools.pos = e.pos;
    function forceOutVar(type:Type, init:TypedExpr):TypedExpr {
      if (outVar == null) {
        var ident = ctx.fresh();
        var tvar = tvar(ident, type, init);
        pre.push(tvar.decl);
        outVar = tlocal(tvar.v);
      } else if (init != null) {
        pre.push(tassign(outVar, init));
      }
      return outVar;
    }
    var createTempVar = true;
    var innerAssign = false;
    function inner():Void {
      createTempVar = false;
      innerAssign = true;
      if (useResult)
        forceOutVar(e.t, null);
    }
    var ret = {pos: e.pos, t: e.t, expr: (switch (e.expr) {
      case TConst(_)
        | TLocal(_)
        | TTypeExpr(_)
        | TFunction(_)
        | TBreak
        | TContinue
        | TIdent(_):
        createTempVar = false;
        e.expr;
      case TArray(walk(_, pre) => e1, walk(_, pre) => e2):
        createTempVar = false;
        TArray(e1, e2);
      case TBinop(OpBoolAnd, e1, e2):
        return walk({
          pos: e.pos,
          t: e.t,
          expr: TIf(e1, e2, tbool(false)),
        }, pre);
      case TBinop(OpBoolOr, e1, e2):
        return walk({
          pos: e.pos,
          t: e.t,
          expr: TIf(e1, tbool(true), e2),
        }, pre);
      case TBinop(op, walk(_, pre) => e1, walk(_, pre) => e2): TBinop(op, e1, e2);
      case TField(walk(_, pre) => e, fa):
        createTempVar = false;
        TField(e, fa);
      case TParenthesis(walk(_, pre) => e):
        createTempVar = false;
        TParenthesis(e);
      case TObjectDecl(fields):
        TObjectDecl(fields.map(field -> {
          name: field.name,
          expr: walk(field.expr, pre),
        }));
      case TArrayDecl(values): TArrayDecl(values.map(e -> walk(e, pre)));
      case TCall(walk(_, pre) => e, params): TCall(e, params.map(e -> walk(e, pre)));
      case TNew(t, params, args): TNew(t, params, args.map(e -> walk(e, pre)));
      case TUnop(op, postFix, walk(_, pre) => e): TUnop(op, postFix, e);
      case TVar(v, init):
        if (useResult)
          Context.fatalError("variable declarations cannot be used as values", e.pos);
        TVar(v, walk(init, pre));
      case TBlock([]): TObjectDecl([]); // TODO: can this happen?
      case TBlock(exprs):
        inner();
        var sub = [];
        for (i in 0...exprs.length) {
          sub.push(walk(
            exprs[i],
            sub,
            i == exprs.length - 1 ? useResult : false,
            i == exprs.length - 1 ? outVar : null
          ));
        }
        TBlock(sub);
      // TFor
      case TIf(econd, eif, eelse):
        inner();
        TIf(
          walkSub(econd),
          walkSub(eif, useResult, outVar),
          walkSub(eelse, useResult, outVar)
        );
      case TWhile(econd, e, normalWhile):
        if (useResult)
          Context.fatalError("while loops cannot be used as values", e.pos);
        createTempVar = false;
        innerAssign = true;
        TWhile(walkSub(econd), walkSub(e, false), normalWhile);
      case TSwitch(e, cases, edef):
        inner();
        TSwitch(walkSub(e), cases.map(c -> {
          values: c.values,
          expr: walkSub(c.expr, useResult, outVar),
        }), walkSub(edef, useResult, outVar));
      case TTry(e, catches):
        inner();
        TTry(walkSub(e, useResult, outVar), catches.map(c -> {
          v: c.v,
          expr: walkSub(c.expr, useResult, outVar),
        }));
      case TReturn(walk(_, pre) => e):
        createTempVar = false;
        TReturn(e);
      case TThrow(walk(_, pre) => e):
        createTempVar = false;
        TThrow(e);
      case TCast(walk(_, pre, useResult, outVar) => e, t): TCast(e, t);
      case TMeta(s, walk(_, pre, useResult, outVar) => e): TMeta(s, e);
      case TEnumParameter(walk(_, pre, useResult, outVar) => e, ef, index): TEnumParameter(e, ef, index);
      case TEnumIndex(walk(_, pre, useResult, outVar) => e): TEnumIndex(e);
      case _: trace(e.expr); throw "!";
    })};
    if (!useResult)
      return ret;
    if (outVar == null && createTempVar && !innerAssign)
      return forceOutVar(null, ret);
    if (createTempVar)
      forceOutVar(e.t, null);
    if (outVar != null) {
      if (innerAssign)
        pre.push(ret);
      else
        pre.push(tassign(outVar, ret));
      return outVar;
    }
    return ret;
  }
}

#end
