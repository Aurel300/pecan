package pecan;

class CoFactory<TIn, TOut> {
  public final actions:Array<CoAction<TIn, TOut>>;
  public final vars:() -> CoVariables;

  public function new(actions:Array<CoAction<TIn, TOut>>, vars:() -> CoVariables) {
    this.actions = actions;
    this.vars = vars;
  }

  public function run():Co<TIn, TOut> {
    return new Co(actions, vars());
  }
}
