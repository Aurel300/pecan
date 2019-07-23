package pecan;

class Co<TIn, TOut> {
  public static macro function co(block, tin, tout):Expr {}

  public final actions:Array<CoAction<TIn, TOut>>;
  public final vars:CoVariables;
  public var position:Array<Int> = [0];
  public var state:CoState<TIn, TOut> = Ready;

  public function new(actions:Array<CoAction<TIn, TOut>>, vars:CoVariables) {
    this.actions = actions;
    this.vars = vars;
  }

  function getActionStack():Array<CoActionStack<TIn, TOut>> {
    var last:CoActionStack<TIn, TOut> = null;
    var stack = [last = {actions: actions}];
    for (index in position) {
      var indexUsed = false;
      while (!indexUsed) {
        indexUsed = true;
        if (last.actions != null) {
          stack.push(last = {action: last.actions[index]});
        } else if (last.action != null) {
          switch (last.action.kind) {
            case Block(b) | While(_, b, _):
              indexUsed = false;
              stack.push(last = {actions: b});
            case If(_, eif, eelse):
              stack.push(last = {actions: index == 0 ? eif : eelse});
            case _:
              throw "!";
          }
        }
      }
    }
    return stack;
  }

  function getCurrentAction():CoAction<TIn, TOut> {
    var stack = getActionStack();
    return stack[stack.length - 1].action;
  }

  function advanceAction():Bool {
    var stack = getActionStack();
    stack.pop(); // discard leaf action
    var work = true;
    while (work && position.length > 0 && stack.length > 0) {
      work = false;
      var top = stack[stack.length - 1];
      if (top.actions == null)
        throw "!";
      if (++position[position.length - 1] >= top.actions.length) {
        position.pop();
        stack.pop(); // discard actions
        if (stack.length > 0)
          switch (stack[stack.length - 1].action.kind) {
            case If(_, _, _):
              position.pop(); // discard if/else branch index
            case While(cond, _, _):
              if (cond(this)) {
                //position.push(0);
                return true;
              }
            case _:
          }
        stack.pop(); // discard action
        work = true;
      }
    }
    if (position.length == 0 || stack.length == 0) {
      return false;
    }
    return true;
  }

  function checkEnd():Bool {
    if (actions.length == 0 || position.length == 0) {
      terminate();
      return true;
    }
    return false;
  }

  public function tick():Void {
    if (state != Ready)
      return;
    if (checkEnd())
      return;
    var tickMore = true;
    while (tickMore) {
      var nextAction = true;
      var current = getCurrentAction();
      // trace("ticking", position, current);
      tickMore = (switch (current.kind) {
        case Sync(f): f(this); state != Suspended && state != Terminated;
        case Suspend(f): if (f == null || f(this, wakeup)) suspend(); state != Suspended && state != Terminated;
        case Block(_):
          nextAction = false;
          position.push(0);
          true;
        case If(cond, _, eelse):
          if (cond(this)) {
            nextAction = false;
            position.push(0);
            position.push(0);
          } else if (eelse != null) {
            nextAction = false;
            position.push(1);
            position.push(0);
          }
          true;
        case While(cond, _, normalWhile):
          if (!normalWhile || cond(this)) {
            nextAction = false;
            position.push(0);
          }
          true;
        case Accept(f):
          state = Accepting(f);
          // the position is advanced in give
          nextAction = false;
          false;
        case Yield(f):
          state = Yielding(f);
          // the position is advanced in take
          nextAction = false;
          false;
      });
      if (nextAction && !advanceAction())
        tickMore = false;
    }
    if (state.match(Ready | Suspended))
      checkEnd();
  }

  public function suspend():Void {
    state = Suspended;
  }

  public function wakeup():Void {
    if (state != Ready && state != Suspended)
      throw "invalid state - can only wakeup Co in Ready or Suspended state";
    state = Ready;
    tick();
  }

  public function terminate():Void {
    state = Terminated;
  }

  public function give(value:TIn):Void {
    tick();
    switch (state) {
      case Accepting(f):
        f(this, value);
        if (advanceAction()) {
          state = Suspended;
          wakeup();
        } else
          state = Terminated;
      case _:
        throw "invalid state - can only give to Co in Accepting state";
    }
  }

  public function take():TOut {
    tick();
    switch (state) {
      case Yielding(f):
        var ret = f(this);
        if (advanceAction()) {
          state = Suspended;
          wakeup();
        } else
          state = Terminated;
        return ret;
      case _:
        throw 'invalid state - can only take from Co in Yielding state (is $state)';
        //throw "invalid state - can only take from Co in Yielding state";
    }
  }

  public function toString():String {
    return "co\n" + actions.map(a -> a.toString()).join("\n");
  }
}

enum CoState<TIn, TOut> {
  Ready;
  Suspended;
  Terminated;

  Accepting(_:(self:Co<TIn, TOut>, value:TIn) -> Void);
  Yielding(_:(self:Co<TIn, TOut>) -> TOut);
}

typedef CoActionStack<TIn, TOut> = {?actions:Array<CoAction<TIn, TOut>>, ?action:CoAction<TIn, TOut>};
