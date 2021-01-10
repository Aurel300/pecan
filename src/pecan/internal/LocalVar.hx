package pecan.internal;

#if macro

typedef LocalVar = {
  /**
    Name of the original variable.
  **/
  name:String,

  type:ComplexType,

  /**
    Position where the original variable was declared.
  **/
  declaredPos:Position,

  /**
    Name of the renamed variable, field on the variables class.
  **/
  renamed:String,

  /**
    `false` if the variable cannot be written to in user code, e.g. when it is
    actually a loop variable.
  **/
  readOnly:Bool,

  argOptional:Bool
};

#end
