package pecan.internal;

#if macro

/**
Control-flow graph representation.
 */
class Cfg {
  public var catches:CfgCatch<Cfg>;
  public var kind:CfgKind<Cfg>;

  public var successors(get, never):Array<Cfg>;
  public var successorsCatch(get, never):Array<Cfg>;
  public var successorsAll(get, never):Array<Cfg>;

  function get_successors():Array<Cfg> {
    return (switch (kind) {
      case Sync(_, next) | Goto(next) | Accept(_, next) | Yield(_, next)
        | Suspend(next) | Label(_, next) | Join(next) | ExtSuspend(_, next)
        | ExtAccept(_, next): [next];
      case GotoIf(_, nextIf, nextElse): [nextIf, nextElse];
      case GotoSwitch(_, cases, nextDef): cases.map(c -> c.next).concat([nextDef]);
      case Halt(_): [];
    });
  }

  function get_successorsCatch():Array<Cfg> {
    var ret = [];
    var c = catches;
    while (c != null) {
      ret = ret.concat(c.handlers.map(h -> h.cfg));
      c = c.parent;
    }
    return ret;
  }

  function get_successorsAll():Array<Cfg> {
    return successors.concat(successorsCatch);
  }

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
        case Label(_, next): walk(next);
        case Join(next): walk(next);
        case ExtSuspend(_, next): walk(next);
        case ExtAccept(_, next): walk(next);
        case Halt(_):
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
