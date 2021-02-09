package pecan.internal;

#if macro

/**
"Partial" control-flow graph, where each node may have multiple exit points,
and each exit point may or may not yet be resolved.
 */
class PartialCfg {
  public static function mkSync(c:PartialCatch, e:TypedExpr)
    return mk((slot, slots) -> new PartialCfg(c, Sync(e, slot()), slots));
  public static function mkGoto(c:PartialCatch)
    return mk((slot, slots) -> new PartialCfg(c, Goto(slot()), slots));
  public static function mkGotoIf(c:PartialCatch, e:TypedExpr)
    return mk((slot, slots) -> new PartialCfg(c, GotoIf(e, slot(), slot()), slots));
  public static function mkGotoSwitch(c:PartialCatch, e:TypedExpr, cases:Array<{
    values:Array<TypedExpr>,
  }>)
    return mk((slot, slots) -> new PartialCfg(c, GotoSwitch(e, cases.map(c -> {
      values: c.values,
      next: slot(),
    }), slot()), slots));
  public static function mkAccept(c:PartialCatch, v:TVar)
    return mk((slot, slots) -> new PartialCfg(c, Accept(v, slot()), slots));
  public static function mkYield(c:PartialCatch, e:TypedExpr)
    return mk((slot, slots) -> new PartialCfg(c, Yield(e, slot()), slots));
  public static function mkSuspend(c:PartialCatch)
    return mk((slot, slots) -> new PartialCfg(c, Suspend(slot()), slots));
  public static function mkLabel(c:PartialCatch, label:String)
    return mk((slot, slots) -> new PartialCfg(c, Label(label, slot()), slots));
  public static function mkJoin(c:PartialCatch)
    return mk((slot, slots) -> new PartialCfg(c, Join(slot()), slots));
  public static function mkExtSuspend(c:PartialCatch, e:TypedExpr)
    return mk((slot, slots) -> new PartialCfg(c, ExtSuspend(e, slot()), slots));
  public static function mkExtAccept(c:PartialCatch, e:TypedExpr)
    return mk((slot, slots) -> new PartialCfg(c, ExtAccept(e, slot()), slots));
  public static function mkHalt(c:PartialCatch, ?e:TypedExpr)
    return mk((slot, slots) -> new PartialCfg(c, Halt(e), slots));

  static function mk(f:(slot:Void->PartialSlot, slots:Array<PartialSlot>)->PartialCfg):PartialCfg {
    var slots = [];
    return f(() -> {
      var slot:PartialSlot = {cfg: null};
      slots.push(slot);
      slot;
    }, slots);
  }

  static function resolveSlot(slot:PartialSlot):Cfg {
    if (slot.cfg == null)
      throw "slot not resolved";
    return slot.cfg.resolve();
  }

  static function resolveCatch(catches:PartialCatch):CfgCatch<Cfg> {
    if (catches == null)
      return null;
    return {
      handlers: [ for (h in catches.handlers) {
        v: h.v,
        cfg: h.cfg.resolve(),
      } ],
      parent: resolveCatch(catches.parent),
    };
  }

  public var catches:PartialCatch;
  public var kind:CfgKind<PartialSlot>;
  public var slots:Array<PartialSlot>;
  var cached:Cfg;

  public function new(catches:PartialCatch, kind:CfgKind<PartialSlot>, slots:Array<PartialSlot>) {
    this.catches = catches;
    this.kind = kind;
    this.slots = slots;
  }

  public function chain(next:PartialCfg, ?idx:Int = -1):PartialCfg {
    if (idx == -1) {
      for (s in slots)
        s.cfg = next;
    } else {
      slots[idx].cfg = next;
    }
    return next;
  }

  /**
  Resolves the partial CFG to a CFG. Fails if any exit points are not yet
  resolved.
   */
  public function resolve():Cfg {
    if (cached != null)
      return cached;
    cached = new Cfg(resolveCatch(catches), null);
    cached.kind = (switch (kind) {
      case Sync(e, next): Sync(e, resolveSlot(next));
      case Goto(next): Goto(resolveSlot(next));
      case GotoIf(e, nextIf, nextElse): GotoIf(e, resolveSlot(nextIf), resolveSlot(nextElse));
      case GotoSwitch(e, cases, nextDef):
        GotoSwitch(e, cases.map(c -> {
          values: c.values,
          next: resolveSlot(c.next),
        }), resolveSlot(nextDef));
      case Accept(v, next): Accept(v, resolveSlot(next));
      case Yield(e, next): Yield(e, resolveSlot(next));
      case Suspend(next): Suspend(resolveSlot(next));
      case Label(label, next): Label(label, resolveSlot(next));
      case Join(next): Join(resolveSlot(next));
      case ExtSuspend(e, next): ExtSuspend(e, resolveSlot(next));
      case ExtAccept(e, next): ExtAccept(e, resolveSlot(next));
      case Halt(e): Halt(e);
    });
    return cached;
  }
}

typedef PartialSlot = {
  cfg:Null<PartialCfg>,
};

typedef PartialCatch = CfgCatch<PartialCfg>;

#end
