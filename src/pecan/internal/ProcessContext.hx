package pecan.internal;

#if macro

typedef ProcessContext = {
  /**
    The AST representation, changed with each processing stage.
  **/
  block:Expr,

  labels:Map<String, Int>,

  pos:Position,

  /**
    Counter for declaring coroutine-local variables.
  **/
  localCounter:Int,

  topScope:LocalScope,
  scopes:Array<LocalScope>,

  /**
    Type path of the class holding the coroutine-local variables.
  **/
  varsTypePath:TypePath,

  varsComplexType:ComplexType,

  /**
    All locals declared for the coroutine.
  **/
  locals:Array<LocalVar>,

  /**
    Argument variables passed during `run`. A subset of locals.
  **/
  arguments:Array<LocalVar>,

  typeInput:ComplexType,
  typeOutput:ComplexType
};

#end
