package pecan;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ExprTools;

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
};

typedef LocalScope = Map<String, Array<LocalVar>>;

typedef ProcessContext = {
  /**
    The AST representation, changed with each processing stage.
  **/
  block:Expr,

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

  typeInput:ComplexType,
  typeOutput:ComplexType
};

class Co {
  static var typeCounter = 0;
  static var ctx:ProcessContext;

  /**
    Initialise the type path and complex type for the class that will hold
    the coroutine-local variables.
  **/
  static function initVariableClass():Void {
    ctx.varsTypePath = {name: 'CoVariables${typeCounter++}', pack: ["pecan", "instances"]};
    ctx.varsComplexType = ComplexType.TPath(ctx.varsTypePath);
  }

  static function declareLocal(varsExpr:Expr, name:String, type:ComplexType, expr:Expr, readOnly:Bool):LocalVar {
    if (type == null && expr == null)
      Context.error('invalid variable declaration for $name - must have either a type hint or an expression', varsExpr.pos);
    if (type == null) {
      type = (switch (expr) {
        case {expr: ECall({expr: EConst(CIdent("accept"))}, [])}:
          ctx.typeInput;
        case _:
          try Context.toComplexType(Context.typeof(expr)) catch (e:Dynamic) Context.error('cannot infer type for $name - provide a type hint', expr.pos);
      });
    }
    if (name != null && !ctx.topScope.exists(name))
      ctx.topScope[name] = [];
    var localVar = {
      name: name,
      type: type,
      declaredPos: varsExpr.pos,
      renamed: '_coLocal${ctx.localCounter++}',
      readOnly: readOnly
    }
    if (name != null)
      ctx.topScope[name].push(localVar);
    ctx.locals.push(localVar);
    // trace('${localVar.renamed} <- $name', ctx.scopes);
    return localVar;
  }

  static function accessLocal(expr:Expr, name:String, write:Bool):Null<Expr> {
    for (i in 0...ctx.scopes.length) {
      var ri = ctx.scopes.length - i - 1;
      if (ctx.scopes[ri].exists(name)) {
        var scope = ctx.scopes[ri][name];
        // trace(name, scope);
        if (scope.length > 0) {
          var localVar = scope[scope.length - 1];
          if (localVar.readOnly && write)
            Context.error('cannot write to read-only variable $name', expr.pos);
          return accessLocal2(localVar, expr.pos);
        }
      }
    }
    return null;
  }

  static function withPos(expr:Expr, ?pos:Position):Expr {
    return {expr: expr.expr, pos: pos != null ? pos : expr.pos};
  }

  static function accessLocal2(localVar:LocalVar, ?pos:Position):Expr {
    var varsComplexType = ctx.varsComplexType;
    var renamed = localVar.renamed;
    return withPos(macro (cast self.vars : $varsComplexType).$renamed, pos);
  }

  /**
    Renames variables to unique identifiers to match variable scopes.
  **/
  static function processVariables():Void {
    ctx.scopes = [ctx.topScope = []];
    function scoped<T>(visit:() -> T):T {
      ctx.scopes.push(ctx.topScope = []);
      var ret = visit();
      ctx.scopes.pop();
      ctx.topScope = ctx.scopes[ctx.scopes.length - 1];
      return ret;
    }
    function walk(e:Expr):Expr {
      return {
        pos: e.pos,
        expr: (switch (e.expr) {
          // manage scopes
          case EBlock(sub):
            EBlock(scoped(() -> sub.map(walk)));
          case ESwitch(e, cases, edef):
            ESwitch(walk(e), [
              for (c in cases)
                {expr: c.expr != null ? walk(c.expr) : null, guard: c.guard != null ? walk(c.guard) : null, values: ExprArrayTools.map(c.values, walk)}
            ], edef == null || edef.expr == null ? edef : scoped(() -> walk(edef)));
          // change `for` loops to `while` loops
          case EFor({expr: EBinop(OpIn, ev = {expr: EConst(CIdent(v))}, it)}, body):
            var exprs = [];
            try {
              if (!Context.unify(Context.typeof(it), Context.resolveType(macro : Iterator<Dynamic>, Context.currentPos())))
                throw 0;
            } catch (e:Dynamic) {
              it = macro $it.iterator();
            }
            var iterVarAccess = accessLocal2(declareLocal(it, null, null, it, true), it.pos);
            var loopVar = declareLocal(ev, v, null, macro $it.next(), true);
            exprs.push(macro $iterVarAccess = $it);
            exprs.push(macro while ($iterVarAccess.hasNext()) {
              $e{accessLocal2(loopVar, ev.pos)} = $iterVarAccess.next();
              $e{walk(body)};
            });
            return macro $b{exprs};
          // rename variables
          case EVars(vars):
            var exprs = [];
            for (v in vars) {
              if (v.isFinal)
                Context.error("final variables are not supported in coroutines", e.pos);
              var localVar = declareLocal(e, v.name, v.type, v.expr, false);
              if (v.expr != null) {
                var access = accessLocal2(localVar);
                exprs.push(macro $access = $e{v.expr});
              }
            }
            return macro $b{exprs};
          // resolve identifiers to renamed variables
          case EBinop(binop = OpAssign | OpAssignOp(_), ev = {expr: EConst(CIdent(ident))}, rhs):
            var res = accessLocal(ev, ident, true);
            return res != null ? {expr: EBinop(binop, res, rhs), pos: e.pos} : e;
          case EConst(CIdent(ident)):
            // trace('ident: $ident -> ${lookup(ident)}');
            var res = accessLocal(e, ident, false);
            return res != null ? res : e;
          case _:
            return ExprTools.map(e, walk);
        })
      };
    }
    ctx.block = walk(ctx.block);
    ctx.scopes = null;
    ctx.topScope = null;
    // Sys.println(new haxe.macro.Printer().printExpr(ctx.block));
  }

  /**
    Defines the class for coroutine-local variables.
  **/
  static function finaliseVariableClass():Void {
    var varsTypeName = ctx.varsTypePath.name;
    var varsType = macro class $varsTypeName extends pecan.CoVariables {
      public function new() {}
    };
    varsType.pack = ["pecan", "instances"];
    for (localVar in ctx.locals) {
      varsType.fields.push({
        access: [APublic],
        name: localVar.renamed,
        kind: FVar(localVar.type, null),
        pos: localVar.declaredPos
      });
    }
    // Sys.println(new haxe.macro.Printer().printTypeDefinition(varsType));
    Context.defineType(varsType);
  }

  /**
    Converts a code block to a valid `Co` construction.
  **/
  static function convert():Void {
    var top:Array<Expr>;
    var blockStack = [top = []];
    function sub(f:() -> Void):Array<Expr> {
      blockStack.push(top = []);
      f();
      top = blockStack[blockStack.length - 2];
      return blockStack.pop();
    }
    function flatten(e:Array<Expr>):Array<Expr> {
      return (switch (e) {
        case [
          {
            expr: ENew({name: "Co", sub: "CoAction", pack: ["pecan"]}, [{expr: ECall({expr: EConst(CIdent("Block"))}, [{expr: EArrayDecl([e])}])}])
          }
        ]:
          [e];
        case _: e;
      });
    }
    var tin = ctx.typeInput;
    var tout = ctx.typeOutput;
    function walk(e:Expr):Void {
      top.push(switch (e.expr) {
        case EBinop(binop = OpAssign | OpAssignOp(_), target, {expr: ECall({expr: EConst(CIdent("accept"))}, [])}):
          macro new pecan.CoAction(Accept(function(self:pecan.Co<$tin, $tout>, value:$tin):Void {
            ${{expr: EBinop(binop, target, macro value), pos: e.pos}};
          }));
        case ECall({expr: EConst(CIdent("terminate"))}, []):
          macro new pecan.CoAction(Sync(function(self:pecan.Co<$tin, $tout>):Void {
            self.terminate();
          }));
        case ECall({expr: EConst(CIdent("suspend"))}, []):
          macro new pecan.CoAction(Suspend());
        case ECall({expr: EConst(CIdent("suspend"))}, [f]):
          macro new pecan.CoAction(Suspend(function(self:pecan.Co<$tin, $tout>, wakeup:() -> Void):Bool {
            $f(self, wakeup);
            return true;
          }));
        case ECall({expr: EConst(CIdent("yield"))}, [expr]):
          macro new pecan.CoAction(Yield(function(self:pecan.Co<$tin, $tout>):$tout {
            return $expr;
          }));
        case EBlock(bs):
          var sub = macro $a{sub(() -> bs.map(walk))};
          macro new pecan.CoAction(Block($sub));
        case EIf(cond, eif, eelse):
          var subif:Expr = macro $a{flatten(sub(() -> walk(eif)))};
          var subelse:Expr = macro null;
          if (eelse != null) subelse = macro $a{flatten(sub(() -> walk(eelse)))};
          macro new pecan.CoAction(If(function(self:pecan.Co<$tin, $tout>):Bool return $cond, $subif, $subelse));
        case EWhile(cond, e, normalWhile):
          var sub:Expr = macro $a{flatten(sub(() -> walk(e)))};
          macro new pecan.CoAction(While(function(self:pecan.Co<$tin, $tout>):Bool return $cond, $sub, $v{normalWhile}));
        case _:
          macro new pecan.CoAction(Sync(function(self:pecan.Co<$tin, $tout>):Void$e));
      });
    }
    var converted = sub(() -> walk(ctx.block));
    ctx.block = macro $a{converted};
    // Sys.println(new haxe.macro.Printer().printExpr(ctx.block));
  }

  /**
    Parse an expr like `(_ : Type)` to a ComplexType.
  **/
  static function parseIOType(e:Expr):ComplexType {
    return (switch (e) {
      case {expr: ECheckType(_, t) | EParenthesis({expr: ECheckType(_, t)})}: t;
      case macro null: macro:Void;
      case _: throw "invalid i/o type";
    });
  }

  public static function co(block:Expr, ?tin:Expr, ?tout:Expr):Expr {
    ctx = {
      block: block,
      localCounter: 0,
      varsTypePath: null,
      varsComplexType: null,
      locals: [],
      topScope: null,
      scopes: null,
      typeInput: parseIOType(tin),
      typeOutput: parseIOType(tout)
    };

    initVariableClass();
    processVariables();
    finaliseVariableClass();
    convert();

    var actions = ctx.block;
    var varsTypePath = ctx.varsTypePath;
    var tin = ctx.typeInput;
    var tout = ctx.typeOutput;
    ctx = null;

    return macro new pecan.CoFactory<$tin, $tout>($actions, () -> new $varsTypePath());
  }
}
