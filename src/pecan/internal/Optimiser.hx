package pecan.internal;

#if macro

/**
Optimises a control-flow graph by removing unnecessary nodes (`Goto`, `Join`),
and by merging consecutive `Sync` nodes.
 */
class Optimiser {
  static function mergeArr(arr:Array<TypedExpr>, e:TypedExpr):Array<TypedExpr> {
    switch (e.expr) {
      case TBlock(es): arr = arr.concat(es);
      case _: arr.push(e);
    }
    return arr;
  }

  static function replaceSuccessor(prev:Cfg, old:Cfg, rep:Cfg):Void {
    inline function replace(c:Cfg):Cfg {
      return c == old ? rep : c;
    }
    prev.kind = (switch (prev.kind) {
      case Sync(e, next): Sync(e, replace(next));
      case Goto(next): Goto(replace(next));
      case GotoIf(e, nextIf, nextElse): GotoIf(e, replace(nextIf), replace(nextElse));
      case GotoSwitch(e, cases, nextDef):
        GotoSwitch(e, cases.map(c -> {
          values: c.values,
          next: replace(c.next),
        }), replace(nextDef));
      case Accept(e, next): Accept(e, replace(next));
      case Yield(e, next): Yield(e, replace(next));
      case Suspend(next): Suspend(replace(next));
      case Label(e, next): Label(e, replace(next));
      case Join(next): Join(replace(next));
      case ExtSuspend(e, next): ExtSuspend(e, replace(next));
      case ExtAccept(e, next): ExtAccept(e, replace(next));
      case Halt(e): Halt(e);
    });
  }

  // static var totalRemoved = 0;

  public static function optimise(root:Cfg):Cfg {
    var flat = root.enumerate();
    //var nodesBefore = flat.length;

    // find predecessors
    var preds = new Map();
    for (cfg in flat) {
      for (succ in cfg.successorsAll) {
        if (!preds.exists(succ)) preds[succ] = [];
        preds[succ].push(cfg);
      }
    }

    /*
    // (debug) only Join and Label nodes should ever have multiple predecessors
    for (cfg => preds in preds) {
      switch (cfg.kind) {
        case Join(_) | Label(_, _):
        case _:
          if (preds.length != 1) {
            Sys.println(CfgPrinter.print(root));
            throw "!";
          }
      }
    }
    */

    // remove Goto nodes
    for (cfg in flat) {
      switch (cfg.kind) {
        case Goto(next):
          while (true) {
            switch (next.kind) {
              case Goto(n): next = n;
              case _: break;
            }
          }
          for (pred in preds[cfg]) {
            replaceSuccessor(pred, cfg, next);
          }
        case _:
      }
    }
    flat = root.enumerate();

    /*
    // (debug)
    for (cfg in flat) {
      if (cfg.kind.match(Goto(_))) {
        throw "!";
      }
    }
    */

    // flatten Sync chains
    for (cfg in flat) {
      switch (cfg.kind) {
        case Sync(e, next):
          var exprs = [e];
          var cur = next;
          while (true) {
            switch (cur.kind) {
              case Sync(e, next):
                exprs = mergeArr(exprs, e);
                cur = next;
              case _: break;
            }
          }
          cfg.kind = Sync(TastTools.tblock(exprs), cur);
        case _:
      }
    }
    flat = root.enumerate();

    // remove Join nodes
    for (cfg in flat) {
      switch (cfg.kind) {
        case Join(next):
          while (true) {
            switch (next.kind) {
              case Join(n): next = n;
              case _: break;
            }
          }
          for (pred in preds[cfg]) {
            replaceSuccessor(pred, cfg, next);
          }
        case _:
      }
    }

    /*
    // (debug)
    flat = root.enumerate();
    var nodesAfter = flat.length;
    totalRemoved += nodesBefore - nodesAfter;
    trace("removed", totalRemoved);
    */

    return root;
  }
}

#end
