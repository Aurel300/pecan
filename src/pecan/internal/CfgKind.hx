package pecan.internal;

#if macro

/**
CFG node kinds.
 */
enum CfgKind<T> {
  // Synchronous action.
  Sync(e:TypedExpr, next:T);
  // No action, skip to next node.
  Goto(next:T);
  // Go to a different node based on the result of the expression.
  GotoIf(e:TypedExpr, nextIf:T, nextElse:T);
  // Go to a different node based on a switch match.
  GotoSwitch(e:TypedExpr, cases:Array<{
    values:Array<TypedExpr>,
    next:T,
  }>, nextDef:T);
  // Suspend until a value is accepted into the variable.
  Accept(v:TVar, next:T);
  // Suspend until the computed value is taken.
  Yield(e:TypedExpr, next:T);
  // Suspend unconditionally.
  Suspend(next:T);
  // Give a string label to the current position.
  Label(label:String, next:T);
  // Join separate branches of control-flow expressions.
  Join(next:T);
  // Break in synchronous actions to check current state when executing.
  Break(next:T);
  // Terminate the coroutine, optionally with a return value.
  Halt(?e:TypedExpr);
}

#end
