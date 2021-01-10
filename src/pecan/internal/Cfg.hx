package pecan.internal;

#if macro

typedef Cfg = {
  kind:CfgKind,
  expr:Null<Expr>,
  next:Array<Cfg>,
  prev:Array<Cfg>,
  idx:Int
};

#end
