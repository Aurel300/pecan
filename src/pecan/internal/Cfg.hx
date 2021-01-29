package pecan.internal;

#if macro

/**
Control-flow graph representation.
 */
class Cfg {
  public var catches:CfgCatch<Cfg>;
  public var kind:CfgKind<Cfg>;

  public function new(catches:CfgCatch<Cfg>, kind:CfgKind<Cfg>) {
    this.catches = catches;
    this.kind = kind;
  }

  /**
  Flattens the CFG into an array, such that the position in the array can be
  used as an index for each node in the graph.
   */
  public function enumerate():Array<Cfg> {
    var cache = new Map();
    var ret = [];
    function walk(cfg:Cfg):Void {
      //if (cfg == null)
      //  return;
      //if (cfg.kind == null)
      //  cfg.kind = Label("<invalid>", null);
      if (cache.exists(cfg))
        return;
      ret.push(cfg);
      cache[cfg] = true;
      switch (cfg.kind) {
        case Sync(_, next): walk(next);
        case Goto(next): walk(next);
        case GotoIf(_, nextIf, nextElse):
          walk(nextIf);
          walk(nextElse);
        case GotoSwitch(_, cases, nextDef):
          for (c in cases)
            walk(c.next);
          walk(nextDef);
        case Accept(_, next): walk(next);
        case Yield(_, next): walk(next);
        case Suspend(next): walk(next);
        case Label(label, next): walk(next);
        case Join(next): walk(next);
        case Break(next): walk(next);
        case Halt:
      }
      var c = cfg.catches;
      while (c != null) {
        for (h in c.handlers) {
          walk(h.cfg);
        }
        c = c.parent;
      }
    }
    walk(this);
    return ret;
  }
}

#end
