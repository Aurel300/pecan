package pecan.internal;

#if macro

typedef CfgCatch<T> = {
  handlers:Array<{
    v:TVar,
    cfg:T,
  }>,
  parent:Null<CfgCatch<T>>,
};

#end
