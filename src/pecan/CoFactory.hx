package pecan;

class CoFactory<TIn, TOut> {
  public final actions:Array<CoAction<TIn, TOut>>;
  public final vars:Array<Dynamic>->CoVariables;

  public function new(actions:Array<CoAction<TIn, TOut>>, vars:Array<Dynamic>->CoVariables) {
    this.actions = actions;
    this.vars = vars;
  }

  public function runBase(args:Array<Dynamic>):Co<TIn, TOut> {
    return new Co(actions, vars(args));
  }
}
