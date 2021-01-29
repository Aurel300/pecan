package pecan.internal;

#if macro

import pecan.internal.TastTools.*;

/**
Performs control flow analysis to convert a typed expression into a
control-flow graph.
 */
class Analyser {
  var ctx:CoContext;
  var tvarSelf:TVar;
  var tvarSelfAlt:TVar;
  var tvarAccept:TVar;
  var tvarYield:TVar;
  var tvarSuspend:TVar;
  var tvarTerminate:TVar;
  var tvarLabel:TVar;

  public function new(ctx:CoContext) {
    this.ctx = ctx;
  }

  public function analyse(typed:TypedExpr):Cfg {
    // extract typed arguments so pecan functions can be resolved
    var tf = switch (typed.expr) {
      case TFunction(tf): tf;
      case _: throw "!";
    };
    tvarSelf = tf.args[0].v;
    tvarSelfAlt = tf.args[1].v;
    tvarAccept = tf.args[2].v;
    tvarYield = tf.args[3].v;
    tvarSuspend = tf.args[4].v;
    tvarLabel = tf.args[5].v;
    tvarTerminate = tf.args[6].v;

    var partial = walk(tf.expr);
    partial.last.chain(PartialCfg.mkHalt());
    var cfg = partial.first.resolve();
    cfg = Optimiser.optimise(cfg);
    if (ctx.debug) trace("cfg after optimisation", CfgPrinter.print(cfg));
    return cfg;
  }

  /**
  Creates a CFG strand from a single partial CFG node.
   */
  static function ss(e:PartialCfg):CfgStrand {
    if (e == null)
      return null;
    return {
      first: e,
      last: e,
    };
  }

  /**
  Creates a CFG strand from multiple strands; the last node in each is
  connected to the first node in the next one.
   */
  static function strand(es:Array<CfgStrand>):CfgStrand {
    es = es.filter(e -> e != null);
    if (es.length == 0)
      return null;
    for (i in 0...es.length - 1) {
      es[i].last.chain(es[i + 1].first);
    }
    return {
      first: es[0].first,
      last: es[es.length - 1].last,
    };
  }

  /**
  Processes a typed expression that may be a block. All expressions of the
  block except for the last one are made into a CFG strand, the last expression
  is returned separately.
   */
  function walkBlock(e:TypedExpr):{
    pre:CfgStrand,
    val:TypedExpr,
  } {
    return (switch (e.expr) {
      case TBlock(exprs): {
        pre: strand(exprs.slice(0, exprs.length - 1).map(walk)),
        val: exprs[exprs.length - 1],
      };
      case _: {
        pre: null,
        val: e,
      };
    });
  }

  /**
  Checks if the given field access is accessing a user-defined pecan action.
   */
  function isPecanAction(fa:FieldAccess):Bool {
    // TODO: check that last argument is of pecan.ICo type?
    return (switch (fa) {
      case FInstance(_, _, _.get().meta.has(":pecan.action") => true): true;
      case FStatic(_, _.get().meta.has(":pecan.action") => true): true;
      case FAnon(_.get().meta.has(":pecan.action") => true): true;
      // TODO: add warning about old syntax?
      case FInstance(_, _, _.get().meta.has(":pecan.suspend") => true): true;
      case FStatic(_, _.get().meta.has(":pecan.suspend") => true): true;
      case FAnon(_.get().meta.has(":pecan.suspend") => true): true;
      case _: false;
    });
  }

  /**
  Checks if the given field access is accessing a user-defined pecan accept
  function.
   */
  function isPecanAccept(fa:FieldAccess):Bool {
    return (switch (fa) {
      case FInstance(_, _, _.get().meta.has(":pecan.accept") => true): true;
      case FStatic(_, _.get().meta.has(":pecan.accept") => true): true;
      case FAnon(_.get().meta.has(":pecan.accept") => true): true;
      case _: false;
    });
  }

  function fieldToFunc(fa:FieldAccess):TFunc {
    var cf = (switch (fa) {
      case FInstance(_, _, _.get() => cf): cf;
      case FStatic(_, _.get() => cf): cf;
      case FAnon(_.get() => cf): cf;
      case _: throw "!";
    });
    return (switch (cf.expr().expr) {
      case TFunction(tf): tf;
      case _: throw "!";
    });
  }

  /**
  Ensures the last argument of a call to a pecan action is a reference to the
  current coroutine, if the argument was `null` (most likely skipped in the
  untyped AST call), or not present (as in the TAST for dynamic targets).
   */
  function insertSelf(args:Array<TypedExpr>, tf:TFunc):Void {
    var last = tf.args.length - 1;
    if (last >= args.length || args[last].expr.match(TConst(TNull))) {
      args[last] = tlocal(tvarSelf);
    }
  }

  /**
  Adds a "return" function to calls to user-defined accepts.
   */
  function insertRet(args:Array<TypedExpr>, tf:TFunc, target:TVar):Void {
    var retPos = tf.args.length - 2;
    if (args[retPos] != null && !args[retPos].expr.match(TConst(TNull))) {
      Context.fatalError("invalid call to @:pecan.accept function", args[retPos].pos);
    }
    var arg = tvar("_arg", target.t);
    args[retPos] = {
      expr: TFunction({
        expr: tassign(tlocal(target), tlocal(arg.v)),
        args: [{value: null, v: arg.v}],
        t: typeVoid,
      }),
      pos: ctx.pos,
      t: tf.args[retPos].v.t,
    };
  }

  /**
  Converts a typed expression into a CFG strand. This is where pecan reserved
  functions and various control-flow expressions are converted into appropriate
  CFG nodes.
   */
  function walk(e:TypedExpr):CfgStrand {
    // TODO: try catch blocks ...
    if (e == null)
      return null;
    var pos = e.pos;
    return (switch (e.expr) {
      case TCall({expr: TLocal(tv)}, []) if (tv.id == tvarAccept.id):
        ss(PartialCfg.mkAccept(null));
      case TBinop(OpAssign, {expr: TLocal(lhs)}, {expr: TCall({expr: TLocal(tv)}, [])}) if (tv.id == tvarAccept.id):
        ss(PartialCfg.mkAccept(lhs));
      case TVar(lhs, {expr: TCall({expr: TLocal(tv)}, [])}) if (tv.id == tvarAccept.id):
        strand([
          ss(PartialCfg.mkSync({
            t: e.t,
            pos: e.pos,
            expr: TVar(lhs, null),
          })),
          ss(PartialCfg.mkAccept(lhs)),
        ]);
      case TCall({expr: TLocal(tv)}, [arg]) if (tv.id == tvarYield.id):
        ss(PartialCfg.mkYield(arg));
      case TCall({expr: TLocal(tv)}, []) if (tv.id == tvarSuspend.id):
        ss(PartialCfg.mkSuspend());
      case TCall({expr: TLocal(tv)}, [{expr: TConst(TString(label))}]) if (tv.id == tvarLabel.id):
        ss(PartialCfg.mkLabel(label));
      case TCall({expr: TLocal(tv)}, []) if (tv.id == tvarTerminate.id):
        ss(PartialCfg.mkHalt());
      case TCall({expr: TField(_, fa)}, args) if (isPecanAction(fa)):
        insertSelf(args, fieldToFunc(fa));
        strand([
          ss(PartialCfg.mkSync(e)),
          ss(PartialCfg.mkBreak()),
        ]);
      case TBinop(OpAssign, {expr: TLocal(lhs)}, call = {expr: TCall({expr: TField(_, fa)}, args)}) if (isPecanAccept(fa)):
        var tf = fieldToFunc(fa);
        insertRet(args, tf, lhs);
        insertSelf(args, tf);
        strand([
          ss(PartialCfg.mkSync(call)),
          ss(PartialCfg.mkBreak()),
        ]);
      case TVar(lhs, call = {expr: TCall({expr: TField(_, fa)}, args)}) if (isPecanAccept(fa)):
        var tf = fieldToFunc(fa);
        insertRet(args, tf, lhs);
        insertSelf(args, tf);
        strand([
          ss(PartialCfg.mkSync({
            t: e.t,
            pos: e.pos,
            expr: TVar(lhs, null),
          })),
          ss(PartialCfg.mkSync(call)),
          ss(PartialCfg.mkBreak()),
        ]);
      case TLocal(tv) if (
        tv.id == tvarAccept.id
        || tv.id == tvarYield.id
        || tv.id == tvarSuspend.id
        || tv.id == tvarTerminate.id
        || tv.id == tvarLabel.id
      ):
        Context.fatalError("cannot use pecan functions (accept, yield, suspend, label, or terminate) as values", e.pos);
      case TField(_, fa) if (isPecanAction(fa)):
        Context.fatalError("cannot use pecan actions as values", e.pos);
      case TBlock(_.map(walk) => exprs): strand(exprs);
      case TIf(walkBlock(_) => econd, walk(_) => eif, walk(_) => eelse):
        var ccond = PartialCfg.mkGotoIf(econd.val);
        var before = strand([
          econd.pre,
          ss(ccond),
        ]);
        var after = ss(PartialCfg.mkJoin());
        ccond.chain(strand([eif, after]).first, 0);
        ccond.chain(strand([eelse, after]).first, 1);
        {
          first: before.first,
          last: after.last,
        };
      case TWhile(walkBlock(_) => econd, walk(_) => e, true):
        var ccond = PartialCfg.mkGotoIf(econd.val);
        var before = strand([
          econd.pre,
          ss(ccond),
        ]);
        var after = PartialCfg.mkJoin();
        ccond.chain(e.first, 0);
        e.last.chain(before.first);
        ccond.chain(after, 1);
        {
          first: before.first,
          last: after,
        };
      case TWhile(walkBlock(_) => econd, walk(_) => e, false):
        var ccond = PartialCfg.mkGotoIf(econd.val);
        var before = strand([
          e,
          econd.pre,
          ss(ccond),
        ]);
        var after = PartialCfg.mkJoin();
        ccond.chain(before.first, 0);
        ccond.chain(after, 1);
        {
          first: before.first,
          last: after,
        };
      // `TFor`s require some ugly type resolution because `.iterator()` is
      // inserted by typing.
      // for (x in {...; foo; }.iterator()) ...
      // must be converted into
      // for (x in {...; foo.iterator(); }) ...
      case TFor(tv, eit = {expr: TCall({expr: TField(eitb, FInstance(_, _, _.get().name => "iterator"))}, [])}, body):
        var ident = ctx.fresh();
        var tt = Context.storeTypedExpr({
          t: eitb.t,
          pos: eitb.pos,
          expr: TConst(TNull),
        });
        var citb = walkBlock(eitb);
        var iterator = Context.typeExpr(macro {
          var $ident = $tt.iterator();
          $i{ident};
        });
        switch (iterator.expr) {
          case TBlock([decl = {expr: TVar(dv, {expr: TCall(itc = {expr: TField(_, fa)}, [])})}, loc = {expr: TLocal(_)}]):
            var mut = {
              t: e.t,
              pos: e.pos,
              expr: TFor(tv, {
                t: iterator.t,
                pos: e.pos,
                expr: TBlock([
                  {
                    t: decl.t,
                    pos: e.pos,
                    expr: TVar(dv, {
                      t: dv.t,
                      pos: e.pos,
                      expr: TCall({
                        t: itc.t,
                        pos: e.pos,
                        expr: TField(citb.val, fa),
                      }, []),
                    }),
                  },
                  loc,
                ]),
              }, body),
            };
            return strand([
              citb.pre,
              walk(mut),
            ]);
          case _:
            throw "!";
        }
      case TFor(tv, walkBlock(_) => eit, walk(_) => body):
        var before = strand([
          eit.pre,
          ss(PartialCfg.mkJoin()),
        ]);
        var after = PartialCfg.mkJoin();
        var tt = Context.storeTypedExpr({
          t: eit.val.t,
          pos: eit.val.pos,
          expr: TConst(TNull),
        });
        var hasNext = Context.typeExpr(macro $tt.hasNext());
        var next = Context.typeExpr(macro $tt.next());
        switch [hasNext.expr, next.expr] {
          case [
            TCall(callH = {expr: TField(itH, faH)}, []),
            TCall(callN = {expr: TField(_, faN)}, []),
          ]:
            var ccond = PartialCfg.mkGotoIf({
              t: hasNext.t,
              pos: eit.val.pos,
              expr: TCall({
                t: callH.t,
                pos: eit.val.pos,
                expr: TField(eit.val, faH),
              }, []),
            });
            before.last.chain(ccond);
            var mid = PartialCfg.mkSync({
              t: typeVoid,
              pos: eit.val.pos,
              expr: TVar(tv, {
                t: next.t,
                pos: eit.val.pos,
                expr: TCall({
                  t: callN.t,
                  pos: eit.val.pos,
                  expr: TField(eit.val, faN),
                }, []),
              }),
            });
            ccond.chain(mid, 0);
            ccond.chain(after, 1);
            mid.chain(body.first);
            body.last.chain(ccond);
            {
              first: before.first,
              last: after,
            };
          case _:
            Context.fatalError("invalid for loop", pos);
        }
      case TFor(_): Context.fatalError("invalid for loop", pos);
      case TSwitch(walkBlock(_) => esw, cases, def):
        var sw = PartialCfg.mkGotoSwitch(esw.val, cases);
        var before = strand([
          esw.pre,
          ss(sw),
        ]);
        var after = PartialCfg.mkJoin();
        for (i in 0...cases.length) {
          var cc = walk(cases[i].expr);
          sw.chain(cc.first, i);
          cc.last.chain(after);
        }
        if (def != null) {
          var cc = walk(def);
          sw.chain(cc.first, cases.length);
          cc.last.chain(after);
        } else {
          sw.chain(after, cases.length);
        }
        {
          first: before.first,
          last: after,
        };
      case TMeta(m, e):
        // TODO: will dropping all metas cause issues?
        // This is here because switches get an `@:ast` meta after typing.
        walk(e);
      case _: ss(PartialCfg.mkSync(e));
    });
  }
}

/**
A CFG strand is a piece of a CFG with an entry point and a single exit point.
Such a strand can be produced for any expression. Control flow expressions like
`if` can also have a single exit point by inserting a `Join` node as a
successor to all paths.

`first` and `last` may be the same node.
 */
typedef CfgStrand = {
  first:PartialCfg,
  last:PartialCfg,
};

#end
