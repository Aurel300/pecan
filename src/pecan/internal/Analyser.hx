package pecan.internal;

#if macro

import pecan.internal.TastTools.*;
import pecan.internal.PartialCfg.PartialCatch;

/**
Performs control flow analysis to convert a typed expression into a
control-flow graph.
 */
class Analyser {
  var ctx:CoContext;
  var tvarSelf:TVar;
  var tvarSelfAlt:TVar;
  var tvarWakeupRet:TVar;
  var tvarAccept:TVar;
  var tvarYield:TVar;
  var tvarSuspend:TVar;
  var tvarTerminate:TVar;
  var tvarLabel:TVar;
  var catches:PartialCatch;
  var loops:Array<{
    head:PartialCfg,
    tail:PartialCfg,
  }> = [];

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
    tvarWakeupRet = tf.args[2].v;
    tvarAccept = tf.args[3].v;
    tvarYield = tf.args[4].v;
    tvarSuspend = tf.args[5].v;
    tvarLabel = tf.args[6].v;
    tvarTerminate = tf.args[7].v;

    var partial = walk(tf.expr);
    partial.last.chain(PartialCfg.mkHalt(null));
    var cfg = partial.first.resolve();
    if (ctx.debug) trace("cfg before optimisation", CfgPrinter.print(cfg));
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
    var tArg = target == null ? typeAny : target.t;
    var ctArg = Context.toComplexType(tArg);
    var retFunc = Context.typeExpr(macro function(_arg:$ctArg):Void {});
    var retFuncTf = (switch (retFunc.expr) {
      case TFunction(tf): tf;
      case _: throw "!";
    });
    if (target != null) {
      retFuncTf.expr = tblock([
        tassign(tlocal(target), tlocal(retFuncTf.args[0].v)),
        {expr: TCall(tlocal(tvarWakeupRet), []), pos: ctx.pos, t: typeVoid},
      ]);
    } else {
      retFuncTf.expr = {expr: TCall(tlocal(tvarWakeupRet), []), pos: ctx.pos, t: typeVoid};
    }
    args[retPos] = retFunc;
  }

  /**
  Converts a typed expression into a CFG strand. This is where pecan reserved
  functions and various control-flow expressions are converted into appropriate
  CFG nodes.
   */
  function walk(e:TypedExpr):CfgStrand {
    if (e == null)
      return null;
    var pos = e.pos;
    TastTools.pos = pos;
    return (switch (e.expr) {
      case TCall({expr: TLocal(tv)}, []) if (tv.id == tvarAccept.id):
        ss(PartialCfg.mkAccept(catches, null));
      case TBinop(OpAssign, {expr: TLocal(lhs)}, {expr: TCall({expr: TLocal(tv)}, [])}) if (tv.id == tvarAccept.id):
        ss(PartialCfg.mkAccept(catches, lhs));
      case TVar(lhs, {expr: TCall({expr: TLocal(tv)}, [])}) if (tv.id == tvarAccept.id):
        strand([
          ss(PartialCfg.mkSync(catches, {
            t: e.t,
            pos: e.pos,
            expr: TVar(lhs, null),
          })),
          ss(PartialCfg.mkAccept(catches, lhs)),
        ]);
      case TCall({expr: TLocal(tv)}, []) if (tv.id == tvarAccept.id):
        ss(PartialCfg.mkAccept(catches, null));
      case TCall({expr: TLocal(tv)}, [arg]) if (tv.id == tvarYield.id):
        ss(PartialCfg.mkYield(catches, arg));
      case TCall({expr: TLocal(tv)}, []) if (tv.id == tvarSuspend.id):
        ss(PartialCfg.mkSuspend(catches));
      case TCall({expr: TLocal(tv)}, [{expr: TConst(TString(label))}]) if (tv.id == tvarLabel.id):
        ss(PartialCfg.mkLabel(catches, label));
      case TCall({expr: TLocal(tv)}, []) if (tv.id == tvarTerminate.id):
        ss(PartialCfg.mkHalt(catches));
      case TCall({expr: TField(_, fa)}, args) if (isPecanAction(fa)):
        insertSelf(args, fieldToFunc(fa));
        ss(PartialCfg.mkExtSuspend(catches, e));
      case TBinop(OpAssign, {expr: TLocal(lhs)}, call = {expr: TCall({expr: TField(_, fa)}, args)}) if (isPecanAccept(fa)):
        var tf = fieldToFunc(fa);
        insertRet(args, tf, lhs);
        insertSelf(args, tf);
        ss(PartialCfg.mkExtAccept(catches, call));
      case TVar(lhs, call = {expr: TCall({expr: TField(_, fa)}, args)}) if (isPecanAccept(fa)):
        var tf = fieldToFunc(fa);
        insertRet(args, tf, lhs);
        insertSelf(args, tf);
        strand([
          ss(PartialCfg.mkSync(catches, {
            t: e.t,
            pos: e.pos,
            expr: TVar(lhs, null),
          })),
          ss(PartialCfg.mkExtAccept(catches, call)),
        ]);
      case TCall({expr: TField(_, fa)}, args) if (isPecanAccept(fa)):
        var tf = fieldToFunc(fa);
        insertRet(args, tf, null);
        insertSelf(args, tf);
        ss(PartialCfg.mkExtAccept(catches, e));
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
        var ccond = PartialCfg.mkGotoIf(catches, econd.val);
        var before = strand([
          econd.pre,
          ss(ccond),
        ]);
        var after = ss(PartialCfg.mkJoin(catches));
        ccond.chain(strand([eif, after]).first, 0);
        ccond.chain(strand([eelse, after]).first, 1);
        {
          first: before.first,
          last: after.last,
        };
      case TWhile(walkBlock(_) => econd, body, true):
        var ccond = PartialCfg.mkGotoIf(catches, econd.val);
        var before = strand([
          ss(PartialCfg.mkJoin(catches)),
          econd.pre,
          ss(ccond),
        ]);
        var after = PartialCfg.mkJoin(catches);
        loops.push({
          head: before.first,
          tail: after,
        });
        var body = walk(body);
        loops.pop();
        ccond.chain(body.first, 0);
        body.last.chain(before.first);
        ccond.chain(after, 1);
        {
          first: before.first,
          last: after,
        };
      case TWhile(walkBlock(_) => econd, body, false):
        var ccond = PartialCfg.mkGotoIf(catches, econd.val);
        var before = PartialCfg.mkJoin(catches);
        var after = PartialCfg.mkJoin(catches);
        loops.push({
          head: before,
          tail: after,
        });
        var body = walk(body);
        loops.pop();
        var mid = strand([
          ss(before),
          body,
          econd.pre,
          ss(ccond),
        ]);
        ccond.chain(before, 0);
        ccond.chain(after, 1);
        {
          first: before,
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
      case TFor(tv, walkBlock(_) => eit, body):
        var before = strand([
          ss(PartialCfg.mkJoin(catches)),
          eit.pre,
          ss(PartialCfg.mkJoin(catches)),
        ]);
        var after = PartialCfg.mkJoin(catches);
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
            var ccond = PartialCfg.mkGotoIf(catches, {
              t: hasNext.t,
              pos: eit.val.pos,
              expr: TCall({
                t: callH.t,
                pos: eit.val.pos,
                expr: TField(eit.val, faH),
              }, []),
            });
            before.last.chain(ccond);
            var mid = strand([
              ss(PartialCfg.mkJoin(catches)),
              ss(PartialCfg.mkSync(catches, {
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
              })),
            ]);
            loops.push({
              head: mid.first,
              tail: after,
            });
            var body = walk(body);
            loops.pop();
            ccond.chain(mid.first, 0);
            ccond.chain(after, 1);
            mid.last.chain(body.first);
            body.last.chain(ccond);
            {
              first: before.first,
              last: after,
            };
          case _:
            Context.fatalError("invalid for loop", pos);
        }
      case TFor(_): Context.fatalError("invalid for loop", pos);
      case TBreak | TContinue:
        if (loops.length == 0)
          Context.fatalError("invalid break", pos);
        var goto = PartialCfg.mkGoto(catches);
        goto.chain(e.expr == TBreak ? loops[loops.length - 1].tail : loops[loops.length - 1].head);
        {
          first: goto,
          last: PartialCfg.mkHalt(catches), // dummy to not override the goto
        };
      case TSwitch(walkBlock(_) => esw, cases, def):
        var sw = PartialCfg.mkGotoSwitch(catches, esw.val, cases);
        var before = strand([
          esw.pre,
          ss(sw),
        ]);
        var after = PartialCfg.mkJoin(catches);
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
      case TMeta({name: ":ast", params: [_]}, e):
        // This is here because switches get an `@:ast` meta after typing.
        walk(e);
      case TTry(e, newCatches):
        var after = PartialCfg.mkJoin(catches);
        catches = {
          handlers: [ for (c in newCatches) {
            var handler = walk(c.expr);
            handler.last.chain(after);
            {
              v: c.v,
              cfg: handler.first,
            };
          }],
          parent: catches,
        };
        var ret = walk(e);
        ret.last.chain(after);
        catches = catches.parent;
        {
          first: ret.first,
          last: after,
        };
      case TReturn(e):
        ss(PartialCfg.mkHalt(catches, e));
      case _: ss(PartialCfg.mkSync(catches, e));
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
