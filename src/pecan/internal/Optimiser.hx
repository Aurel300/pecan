package pecan.internal;

#if macro

/**
Optimises a control-flow graph by removing unnecessary nodes (`Join`), and by
merging consecutive `Sync` nodes.
 */
class Optimiser {
  static function mergeArr(arr:Array<TypedExpr>, e:TypedExpr):Array<TypedExpr> {
    switch (e.expr) {
      case TBlock(es): arr = arr.concat(es);
      case _: arr.push(e);
    }
    return arr;
  }

  public static function optimise(cfg:Cfg):Cfg {
    var cache = new Map();
    function walk(cfg:Cfg):Cfg {
      if (cache.exists(cfg))
        return cache[cfg];
      cache[cfg] = new Cfg(null);
      cache[cfg].kind = (switch (cfg.kind) {
        case Sync(_, _) | Goto(_):
          var exprs = [];
          var cur = cfg;
          while (true) {
            switch (cur.kind) {
              case Sync(e, next):
                exprs = mergeArr(exprs, e);
                cur = next;
              case Goto(next):
                cur = next;
              case _: break;
            }
          }
          cur = walk(cur);
          exprs.length > 0
            ? Sync(TastTools.tblock(exprs), cur)
            : (cur.kind == Halt ? Halt : Goto(cur));
        case GotoIf(e, nextIf, nextElse): GotoIf(e, walk(nextIf), walk(nextElse));
        case GotoSwitch(e, cases, nextDef):
          GotoSwitch(e, cases.map(c -> {
            values: c.values,
            next: walk(c.next),
          }), walk(nextDef));
        case Accept(v, next): Accept(v, walk(next));
        case Yield(e, next): Yield(e, walk(next));
        case Suspend(next): Suspend(walk(next));
        case Label(label, next): Label(label, walk(next));
        case Join(next): return cache[cfg] = walk(next);
        case Break(next): Break(walk(next));
        case Halt: Halt;
      });
      return cache[cfg];
    }
    return walk(cfg);
  }
}

#end
