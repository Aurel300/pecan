package pecan;

enum CoAction<TIn, TOut> {
  Sync(_:(self:Co<TIn, TOut>) -> Void, next:Int);
  Suspend(_:(self:Co<TIn, TOut>) -> Bool, next:Int);
  If(cond:(self:Co<TIn, TOut>) -> Bool, nextIf:Int, nextElse:Int);
  Accept(_:(self:Co<TIn, TOut>, value:TIn) -> Void, next:Int);
  Yield(_:(self:Co<TIn, TOut>) -> TOut, next:Int);
}
