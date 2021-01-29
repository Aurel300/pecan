package pecan.internal;

#if macro

import pecan.internal.TastTools.*;

/**
Embeds the processed control-flow graph back into a typed expression.
 */
class Embedder {
  var ctx:CoContext;

  public function new(ctx:CoContext) {
    this.ctx = ctx;
  }

  /**
  Finds locals used in more than one CFG node, replaces their declarations with
  assignments, then returns the declarations (with default values assigned
  according to the type of the local).
   */
  function extractLocals(states:Array<Cfg>):Array<TypedExpr> {
    var varsUsed = new Map();
    function use(v:TVar, state:Cfg):Void {
      if (!varsUsed.exists(v.id)) {
        varsUsed[v.id] = new Map();
      }
      varsUsed[v.id][states.indexOf(state)] = true;
    }
    for (state in states) {
      function findUses(e:TypedExpr):Void {
        if (e == null)
          return;
        switch (e.expr) {
          case TLocal(tv): use(tv, state);
          case TVar(tv, init):
            findUses(init);
            use(tv, state);
          case _: TypedExprTools.iter(e, findUses);
        }
      }
      switch (state.kind) {
        case Sync(e, _): findUses(e);
        case GotoIf(e, _, _): findUses(e);
        case GotoSwitch(e, cases, _):
          findUses(e);
          cases.iter(c -> c.values.iter(findUses));
        case Accept(v, _): use(v, state);
        case Yield(e, _): findUses(e);
        case _:
      }
    }
    var locals = [];
    function replaceDecls(e:TypedExpr):TypedExpr {
      return (switch (e.expr) {
        case TVar(v, expr) if (varsUsed[v.id].count() > 1):
          locals.push({
            t: e.t,
            expr: TVar(v, switch (v.t) {
              case TAbstract(_.get().name => "Int", []): tint(0);
              case TAbstract(_.get().name => "Bool", []): tbool(false);
              case TAbstract(_.get().name => "Float", []): tfloat(0);
              case TAbstract(_.get().name => "Void", []): null;
              case _: tnull(v.t);
            }),
            pos: e.pos,
          });
          expr != null ? tassign(tlocal(v), expr) : tlocal(v);
        case _: TypedExprTools.map(e, replaceDecls);
      });
    }
    for (state in states) {
      state.kind = (switch (state.kind) {
        case Sync(e, next): Sync(replaceDecls(e), next);
        case GotoIf(e, nextIf, nextElse): GotoIf(replaceDecls(e), nextIf, nextElse);
        case GotoSwitch(e, cases, nextDef):
          GotoSwitch(
            replaceDecls(e),
            cases.map(c -> {
              values: c.values.map(replaceDecls),
              next: c.next,
            }),
            nextDef
          );
        case Yield(e, next): Yield(replaceDecls(e), next);
        case _: state.kind;
      });
    }
    return locals;
  }

  /**
  Replaces references to `self` with the local generated during embedding.
   */
  function replaceSelf(states:Array<Cfg>, selfVar:TypedExpr):Void {
    var tvarSelf;
    var tvarSelfAlt;
    switch (ctx.typedBlock.expr) {
      case TFunction(tf):
        tvarSelf = tf.args[0].v;
        tvarSelfAlt = tf.args[1].v;
      case _: throw "!";
    }
    function walk(e:TypedExpr):TypedExpr {
      return (switch (e.expr) {
        case TLocal(tv) if (tv.id == tvarSelf.id || tv.id == tvarSelfAlt.id): selfVar;
        case _: TypedExprTools.map(e, walk);
      });
    }
    for (state in states) {
      state.kind = (switch (state.kind) {
        case Sync(e, next): Sync(walk(e), next);
        case GotoIf(e, nextIf, nextElse): GotoIf(walk(e), nextIf, nextElse);
        case GotoSwitch(e, cases, nextDef):
          GotoSwitch(
            walk(e),
            cases.map(c -> {
              values: c.values.map(walk),
              next: c.next,
            }),
            nextDef
          );
        case Yield(e, next): Yield(walk(e), next);
        case _: state.kind;
      });
    }
  }

  public function embed(cfg:Cfg):TypedExpr {
    var ctCo = ctx.ctCo;
    var ctIn = ctx.ctIn;
    var ctOut = ctx.ctOut;
    /*
    ((_pecan_self, args...) -> T{
      var locals ...;
      _pecan_self.acceptActions = ...;
      _pecan_self.yieldActions = ...;
      _pecan_self.actions = function ():Int return (switch (_pecan_self.cfgState) {
        
      });
    })(this, args...)
    */
    var states = cfg.enumerate();
    var locals = extractLocals(states);
    function tstate(cfg:Cfg):TypedExpr {
      return tint(states.indexOf(cfg));
    }
    var retFuncUntyped = macro function(_pecan_self:$ctCo):Void {
      @:privateAccess _pecan_self;
      @:privateAccess _pecan_self.cfgState;
      @:privateAccess _pecan_self.ready;
      @:privateAccess _pecan_self.accepting;
      @:privateAccess _pecan_self.yielding;
      @:privateAccess _pecan_self.terminated;
      @:privateAccess _pecan_self.actions;
      @:privateAccess _pecan_self.accepts;
      @:privateAccess _pecan_self.yields;
      @:privateAccess _pecan_self.labels;
    };
    switch (retFuncUntyped.expr) {
      case EFunction(_, f):
        // add dummy version of arguments for typing
        for (a in ctx.args) {
          f.args.push(a);
        }
      case _: throw "!";
    }
    var retFunc = Context.typeExpr(retFuncUntyped);
    var selfVar;
    var selfAccessState;
    var selfAccessReady;
    var selfAccessAccepting;
    var selfAccessYielding;
    var selfAccessTerminated;
    var selfAccessActions;
    var selfAccessAccepts;
    var selfAccessYields;
    var selfAccessLabels;
    var retFuncTf = (switch (retFunc.expr) {
      case TFunction(tf = {expr: {expr: TBlock(es)}}):
        switch (ctx.typedBlock.expr) {
          case TFunction(otf):
            for (i in 0...ctx.args.length) {
              // first 7 arguments in otf are pecan-reserved
              tf.args[i + 1] = otf.args[i + 7];
            }
          case _: throw "!";
        }
        selfVar = es[0];
        selfAccessState = es[1];
        selfAccessReady = es[2];
        selfAccessAccepting = es[3];
        selfAccessYielding = es[4];
        selfAccessTerminated = es[5];
        selfAccessActions = es[6];
        selfAccessAccepts = es[7];
        selfAccessYields = es[8];
        selfAccessLabels = es[9];
        tf;
      case _: throw "!";
    });
    replaceSelf(states, selfVar);
    var acceptsFunc = Context.typeExpr(macro function(_pecan_accepted:$ctIn):Int return 0);
    var acceptsFuncTf = (switch (acceptsFunc.expr) {
      case TFunction(tf): tf;
      case _: throw "!";
    });
    var yieldsFunc = Context.typeExpr(macro function():$ctOut throw 0);
    var yieldsFuncTf = (switch (yieldsFunc.expr) {
      case TFunction(tf): tf;
      case _: throw "!";
    });
    var actionsFunc = Context.typeExpr(macro function():Int return 0);
    var actionsFuncTf = (switch (actionsFunc.expr) {
      case TFunction(tf): tf;
      case _: throw "!";
    });
    var acceptsCases:Array<TypedCase> = [];
    var yieldsCases:Array<TypedCase> = [];
    var labels:Map<String, Int> = [];
    var actionsCases:Array<TypedCase> = [ for (stateIdx => state in states) {
      values: [tint(stateIdx)],
      expr: tblock(switch (state.kind) {
        case Sync(e, next): [e, tstate(next)];
        case Goto(next): [tstate(next)];
        case GotoIf(e, nextIf, nextElse):
          [{
            expr: TIf(e, tstate(nextIf), tstate(nextElse)),
            pos: ctx.pos,
            t: typeInt,
          }];
        case GotoSwitch(e, cases, nextDef):
          [{
            expr: TSwitch(e, cases.map(c -> {
              values: c.values,
              expr: tstate(c.next),
            }), tstate(nextDef)),
            pos: ctx.pos,
            t: typeInt,
          }];
        case Accept(v, next):
          acceptsCases.push({
            values: [tint(stateIdx)],
            expr: tblock([
              tassign(tlocal(v), tlocal(acceptsFuncTf.args[0].v)),
              tstate(next),
            ]),
          });
          [
            tassign(selfAccessAccepting, tbool(true)),
            tassign(selfAccessReady, tbool(false)),
            tint(stateIdx),
          ];
        case Yield(e, next):
          yieldsCases.push({
            values: [tint(stateIdx)],
            expr: tblock([
              tassign(selfAccessState, tstate(next)),
              e,
            ]),
          });
          [
            tassign(selfAccessYielding, tbool(true)),
            tassign(selfAccessReady, tbool(false)),
            tint(stateIdx),
          ];
        case Suspend(next):
          [
            tassign(selfAccessReady, tbool(false)),
            tstate(next),
          ];
        case Label(label, next):
          labels[label] = stateIdx;
          [tstate(next)];
        case Join(next): [tstate(next)];
        case Break(next): [tstate(next)];
        case Halt:
          [
            tassign(selfAccessTerminated, tbool(true)),
            tassign(selfAccessReady, tbool(false)),
            tint(-1),
          ];
      }),
    } ];
    var invalid = Context.typeExpr(macro throw "invalid state");
    acceptsFuncTf.expr = treturn({
      expr: TSwitch(selfAccessState, acceptsCases, invalid),
      pos: ctx.pos,
      t: typeInt,
    });
    yieldsFuncTf.expr = treturn({
      expr: TSwitch(selfAccessState, yieldsCases, invalid),
      pos: ctx.pos,
      t: yieldsFuncTf.t,
    });
    actionsFuncTf.expr = treturn({
      expr: TSwitch(selfAccessState, actionsCases, invalid),
      pos: ctx.pos,
      t: typeInt,
    });
    var retFuncExprs = locals.copy();
    if (ctx.hasIn) {
      retFuncExprs.push(tassign(selfAccessAccepts, acceptsFunc));
    }
    if (ctx.hasOut) {
      retFuncExprs.push(tassign(selfAccessYields, yieldsFunc));
    }
    retFuncExprs.push(tassign(selfAccessActions, actionsFunc));
    var labelsArr = [ for (k => v in labels) {
      expr: EBinop(OpArrow, macro $v{k}, macro $v{v}),
      pos: ctx.pos,
    } ];
    retFuncExprs.push(tassign(
      selfAccessLabels,
      Context.typeExpr(macro ($a{labelsArr}:Map<String, Int>))
    ));
    retFuncTf.expr = {
      expr: TBlock(retFuncExprs),
      pos: ctx.pos,
      t: typeVoid,
    };
    if (ctx.debug) trace("init function", new haxe.macro.Printer().printExpr(Context.getTypedExpr(retFunc)));
    return retFunc;
  }
}

typedef TypedCase = {
  values:Array<TypedExpr>,
  expr:TypedExpr,
};

#end
