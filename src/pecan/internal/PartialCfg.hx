package pecan.internal;

#if macro

/**
"Partial" control-flow graph, where each node may have multiple exit points,
and each exit point may or may not yet be resolved.
 */
class PartialCfg {
  public static function mkSync(e:TypedExpr)
    return mk((slot, slots) -> new PartialCfg(Sync(e, slot()), slots));
  public static function mkGoto()
    return mk((slot, slots) -> new PartialCfg(Goto(slot()), slots));
  public static function mkGotoIf(e:TypedExpr)
    return mk((slot, slots) -> new PartialCfg(GotoIf(e, slot(), slot()), slots));
  public static function mkGotoSwitch(e:TypedExpr, cases:Array<{
    values:Array<TypedExpr>,
  }>)
    return mk((slot, slots) -> new PartialCfg(GotoSwitch(e, cases.map(c -> {
      values: c.values,
      next: slot(),
    }), slot()), slots));
  public static function mkAccept(v:TVar)
    return mk((slot, slots) -> new PartialCfg(Accept(v, slot()), slots));
  public static function mkYield(e:TypedExpr)
    return mk((slot, slots) -> new PartialCfg(Yield(e, slot()), slots));
  public static function mkSuspend()
    return mk((slot, slots) -> new PartialCfg(Suspend(slot()), slots));
  public static function mkLabel(label:String)
    return mk((slot, slots) -> new PartialCfg(Label(label, slot()), slots));
  public static function mkJoin()
    return mk((slot, slots) -> new PartialCfg(Join(slot()), slots));
  public static function mkBreak()
    return mk((slot, slots) -> new PartialCfg(Break(slot()), slots));
  public static function mkHalt()
    return mk((slot, slots) -> new PartialCfg(Halt, slots));

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

  public var kind:CfgKind<PartialSlot>;
  public var slots:Array<PartialSlot>;
  var cached:Cfg;

  public function new(kind:CfgKind<PartialSlot>, slots:Array<PartialSlot>) {
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
    cached = new Cfg(null);
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
      case Break(next): Break(resolveSlot(next));
      case Halt: Halt;
    });
    return cached;
  }
}

typedef PartialSlot = {
  cfg:Null<PartialCfg>,
};

#end
