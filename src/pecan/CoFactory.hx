package pecan;

class CoFactory<TIn, TOut> {
  public final actions:Array<CoAction<TIn, TOut>>;
  public final labels:Map<String, Int>;
  public final vars:Array<Dynamic>->CoVariables;

  public function new(actions:Array<CoAction<TIn, TOut>>, labels:Map<String, Int>, vars:Array<Dynamic>->CoVariables) {
    this.actions = actions;
    this.labels = labels;
    this.vars = vars;
  }

  public function runBase(args:Array<Dynamic>):Co<TIn, TOut> {
    return new Co(actions, labels, vars(args));
  }
}
