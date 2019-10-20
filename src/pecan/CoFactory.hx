package pecan;

class CoFactory<TIn, TOut> {
  public final actions:Array<CoAction<TIn, TOut>>;
  public final vars:Array<Dynamic>->CoVariables;
  public final position:Int;

  public function new(actions:Array<CoAction<TIn, TOut>>, vars:Array<Dynamic>->CoVariables, position:Int) {
    this.actions = actions;
    this.vars = vars;
    this.position = position;
  }

  public function runBase(args:Array<Dynamic>):Co<TIn, TOut> {
    return new Co(actions, vars(args), position);
  }
}
