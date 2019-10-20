package pecan;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ExprTools;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;

using haxe.macro.MacroStringTools;

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

typedef LocalScope = Map<String, Array<LocalVar>>;

typedef ProcessContext = {
  /**
    The AST representation, changed with each processing stage.
  **/
  block:Expr,

  pos:Position,

  entryPosition:Int,

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

class Co {
  static var typeCounter = 0;
  static var ctx:ProcessContext;

  /**
    Initialises the type path and complex type for the class that will hold
    the coroutine-local variables.
  **/
  static function initVariableClass():Void {
    ctx.varsTypePath = {name: 'CoVariables$typeCounter', pack: ["pecan", "instances"]};
    ctx.varsComplexType = ComplexType.TPath(ctx.varsTypePath);
  }

  static function declareLocal(varsExpr:Expr, name:String, type:ComplexType, expr:Expr, readOnly:Bool):LocalVar {
    if (type == null && expr == null)
      Context.error('invalid variable declaration for $name - must have either a type hint or an expression', varsExpr.pos);
    if (type == null) {
      function mapType(e:Expr):Expr {
        return (switch (e.expr) {
          case ECall({expr: EConst(CIdent("accept"))}, []):
            var tin = ctx.typeInput;
            macro (null : $tin);
          case _:
            ExprTools.map(e, mapType);
        });
      }
      var mapped = mapType(expr);
      type = try Context.toComplexType(Context.typeof(mapped)) catch (e:Dynamic) Context.error('cannot infer type for $name - provide a type hint', expr.pos);
    }
    if (name != null && !ctx.topScope.exists(name))
      ctx.topScope[name] = [];
    var localVar = {
      name: name,
      type: type,
      declaredPos: varsExpr.pos,
      renamed: '_coLocal${ctx.localCounter++}',
      readOnly: readOnly,
      argOptional: false
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
    return withPos(macro(cast self.vars : $varsComplexType).$renamed, pos);
  }

  /**
    Checks if the coroutine block consists of a function, parses the arguments
    into separate variables if so.
  **/
  static function processArguments():Void {
    switch (ctx.block.expr) {
      case EFunction(_, f):
        if (f.ret != null)
          Context.error("coroutine function should not have a return type hint", ctx.block.pos);
        if (f.params != null && f.params.length > 0)
          Context.error("coroutine function should not have type parameters", ctx.block.pos);
        var block = [];
        for (arg in f.args) {
          var argLocal = declareLocal(ctx.block, arg.name, arg.type, arg.value, false);
          ctx.arguments.push(argLocal);
          var argAccess = accessLocal2(argLocal, ctx.block.pos);
          if (arg.opt)
            argLocal.argOptional = true;
          if (arg.opt && arg.value != null) {
            block.push(macro {
              if ($argAccess == null)
                $argAccess = ${arg.value};
            });
          }
        }
        function stripReturn(e:Expr):Expr {
          return (switch (e.expr) {
            case EBlock([e]) | EReturn(e) | EMeta({name: ":implicitReturn"}, e):
              stripReturn(e);
            case _:
              e;
          });
        }
        block.push(stripReturn(f.expr));
        ctx.block = withPos(macro $b{block}, ctx.block.pos);
      case _:
    }
  }

  /**
    Renames variables to unique identifiers to match variable scopes.
  **/
  static function processVariables():Void {
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
          // change key-value `for` loops to `while` loops
          case EFor({expr: EBinop(OpArrow, kv = {expr: EConst(CIdent(k))}, {expr: EBinop(OpIn, vv = {expr: EConst(CIdent(v))}, it)})}, body):
            var exprs = [];
            try {
              if (!Context.unify(Context.typeof(it), Context.resolveType(macro:KeyValueIterator<Dynamic>, Context.currentPos())))
                throw 0;
            } catch (e:Dynamic) {
              it = macro $it.keyValueIterator();
            }
            var iterVarAccess = accessLocal2(declareLocal(it, null, null, it, true), it.pos);
            var iterStructAccess = accessLocal2(declareLocal(it, null, null, macro $it.next(), true), it.pos);
            var keyVar = declareLocal(kv, k, null, macro $it.next().key, true);
            var valueVar = declareLocal(vv, v, null, macro $it.next().value, true);
            exprs.push(macro $iterVarAccess = $it);
            exprs.push(macro while ($iterVarAccess.hasNext()) {
              $iterStructAccess = $iterVarAccess.next();
              $e{accessLocal2(keyVar, kv.pos)} = $iterStructAccess.key;
              $e{accessLocal2(valueVar, vv.pos)} = $iterStructAccess.value;
              $e{walk(body)};
            });
            return macro $b{exprs};
          // change `for` loops to `while` loops
          case EFor({expr: EBinop(OpIn, ev = {expr: EConst(CIdent(v))}, it)}, body):
            var exprs = [];
            try {
              if (!Context.unify(Context.typeof(it), Context.resolveType(macro:Iterator<Dynamic>, Context.currentPos())))
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
            return {expr: EBinop(binop, res != null ? res : ev, walk(rhs)), pos: e.pos};
          case EConst(CIdent(ident)):
            // trace('ident: $ident -> ${lookup(ident)}');
            var res = accessLocal(e, ident, false);
            return res != null ? res : e;
          // handle format strings
          case EConst(CString(s)):
            if (MacroStringTools.isFormatExpr(e))
              return walk(s.formatString(e.pos));
            return e;
          case _:
            return ExprTools.map(e, walk);
        })
      };
    }
    ctx.block = walk(ctx.block);
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
    varsType.pack = ctx.varsTypePath.pack;
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

  static function convert():Void {
    var actions:Array<Expr> = [];
    function push(action:Expr):Int {
      var idx = actions.length;
      actions.push(action);
      return idx;
    }
    var tin = ctx.typeInput;
    var tout = ctx.typeOutput;
    var loops:Array<{idxCond:Int, idxNext:Int}> = [];
    function walkExpr(e:Expr, idxNext:Int):{e:Expr, idx:Int} {
      function sub(e:Expr):Expr {
        var ret = walkExpr(e, idxNext);
        idxNext = ret.idx;
        return ret.e;
      }
      return (switch (e.expr) {
        // special calls
        case ECall({expr: EConst(CIdent("accept"))}, []):
          //if (!allowAccept)
          //  Context.error("invalid location for accept() call", e.pos);
          var tmpVarAccess = accessLocal2(declareLocal(e, null, tin, null, true), e.pos);
          var acceptIdx = push(macro pecan.CoAction.Accept(function(self:pecan.Co<$tin, $tout>, value:$tin):Void {
            $tmpVarAccess = value;
          }, $v{idxNext}));
          {e: macro $tmpVarAccess, idx: acceptIdx};
        // expressions which should have been filtered out by now
        case EFor(_, _):
          Context.error("unexpected", e.pos);
        // normal expressions
        case EConst(_):
          {e: e, idx: idxNext};
        case EArray(e1, e2):
          var e1 = walkExpr(e1, idxNext);
          var e2 = walkExpr(e2, e1.idx);
          {e: {expr: EArray(e1.e, e2.e), pos: e.pos}, idx: e2.idx};
        case EBinop(op, e1, e2): // TODO: order of evaluation? short circuiting?
          var e1 = walkExpr(e1, idxNext);
          var e2 = walkExpr(e2, e1.idx);
          {e: {expr: EBinop(op, e1.e, e2.e), pos: e.pos}, idx: e2.idx};
        case EField(e1, field):
          var e1 = walkExpr(e1, idxNext);
          {e: {expr: EField(e1.e, field), pos: e.pos}, idx: e1.idx};
        case EParenthesis(e1):
          var e1 = walkExpr(e1, idxNext);
          {e: {expr: EParenthesis(e1.e), pos: e.pos}, idx: e1.idx};

        case EArrayDecl(values):
          var values = values.map(sub);
          {e: {expr: EArrayDecl(values), pos: e.pos}, idx: idxNext};
        case ECall(e1, params):
          var params = params.map(sub);
          var e1 = sub(e1);
          {e: {expr: ECall(e1, params), pos: e.pos}, idx: idxNext};

        case EUnop(op, postFix, e1):
          var e1 = sub(e1);
          {e: {expr: EUnop(op, postFix, e1), pos: e.pos}, idx: idxNext};

        case ECast(e1, t):
          var e1 = sub(e1);
          {e: {expr: ECast(e1, t), pos: e.pos}, idx: idxNext};

        case ETernary(e1, e2, e3):
          var e1 = sub(e1);
          var e2 = sub(e2);
          var e3 = sub(e3);
          {e: {expr: ETernary(e1, e2, e3), pos: e.pos}, idx: idxNext};
        case ECheckType(e1, t):
          var e1 = sub(e1);
          {e: {expr: ECheckType(e1, t), pos: e.pos}, idx: idxNext};

        case _:
          {e: e, idx: idxNext};
          //Context.error('complex expr ${e.expr}', e.pos);
      });
    }
    function walk(e:Expr, idxNext:Int):Int {
      return (switch (e.expr) {
        // special calls
        case ECall({expr: EConst(CIdent("terminate"))}, []):
          push(macro pecan.CoAction.Sync(function(self:pecan.Co<$tin, $tout>):Void {
            self.terminate();
          }, -1));
        case ECall({expr: EConst(CIdent("suspend"))}, []):
          push(macro pecan.CoAction.Suspend(null, $v{idxNext}));
        case ECall({expr: EConst(CIdent("suspend"))}, [f]):
          push(macro pecan.CoAction.Suspend(function(self:pecan.Co<$tin, $tout>, wakeup:() -> Void):Bool {
            $f(self, wakeup);
            return true;
          }, $v{idxNext}));
        case ECall({expr: EConst(CIdent("yield"))}, [expr]):
          var idxYield = push(null);
          var expr = walkExpr(expr, idxYield);
          actions[idxYield] = macro pecan.CoAction.Yield(function(self:pecan.Co<$tin, $tout>):$tout {
            return $e{expr.e};
          }, $v{idxNext});
          expr.idx;
        case ECall(f, args) if (checkSuspending(f)):
          var idxCall = push(null);
          var next = idxCall;
          var args = [ for (ri in 0...args.length) {
            var ret = walkExpr(args[args.length - ri - 1], next);
            next = ret.idx;
            ret.e;
          } ];
          args.push(macro self);
          args.push(macro wakeup);
          actions[idxCall] = macro pecan.CoAction.Suspend(function(self:pecan.Co<$tin, $tout>, wakeup:() -> Void):Bool {
            return $f($a{args});
          }, $v{idxNext});
          next;
        // normal blocks
        case EBlock(es):
          var next = idxNext;
          for (ri in 0...es.length)
            next = walk(es[es.length - ri - 1], next);
          next;
        case EIf(cond, eif, eelse):
          var idxCond = push(null);
          var cond = walkExpr(cond, idxCond);
          var idxIf = walk(eif, idxNext);
          var idxElse = eelse == null ? idxNext : walk(eelse, idxNext);
          actions[idxCond] = macro pecan.CoAction.If(function(self:pecan.Co<$tin, $tout>):Bool {
            return $e{cond.e};
          }, $v{idxIf}, $v{idxElse});
          cond.idx;
        case EWhile(cond, body, normalWhile):
          var idxCond = push(null);
          var cond = walkExpr(cond, idxCond);
          loops.push({idxCond: cond.idx, idxNext: idxNext});
          var idxBody = walk(body, cond.idx);
          loops.pop();
          actions[idxCond] = macro pecan.CoAction.If(function(self:pecan.Co<$tin, $tout>):Bool {
            return $e{cond.e};
          }, $v{idxBody}, $v{idxNext});
          normalWhile ? cond.idx : idxBody;
        case EBreak if (loops.length > 0):
          loops[loops.length - 1].idxNext;
        case EContinue if (loops.length > 0):
          loops[loops.length - 1].idxCond;
        case EBreak | EContinue:
          Context.error("break and continue are only allowed in loops", e.pos);
        case _:
          var idxSync = push(null);
          var res = walkExpr(e, idxSync);
          actions[idxSync] = macro pecan.CoAction.Sync(function(self:pecan.Co<$tin, $tout>):Void {
            $e{res.e};
          }, $v{idxNext});
          res.idx;
      });
    }
    ctx.entryPosition = walk(ctx.block, -1);
    ctx.block = macro $a{actions};
    // trace(ctx.entryPosition);
    // Sys.println(new haxe.macro.Printer().printExpr(ctx.block));
  }

  static function checkSuspending(f:Expr):Bool {
    var tin = ctx.typeInput;
    var tout = ctx.typeOutput;
    var typed = try Context.typeExpr(macro function(self:pecan.Co<$tin, $tout>) {
      $f;
    }) catch (e:Dynamic) null;
    if (typed == null)
      return false;
    switch (typed.expr) {
      case TFunction({expr: {expr: TBlock([{expr: TField(_, FStatic(_, _.get().meta.has(":pecan.suspend") => true))}])}}):
        return true;
      case _:
        return false;
    }
  }

  /**
    Converts a code block to a valid `Co` construction.
  **/
  /*
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
    function walkExpr(e:Expr, ?allowAccept:Bool = true):Expr {
      return (switch (e.expr) {
        case ECall({expr: EConst(CIdent("accept"))}, []):
          if (!allowAccept)
            Context.error("invalid location for accept() call", e.pos);
          var tmpVarAccess = accessLocal2(declareLocal(e, null, tin, null, true), e.pos);
          top.push(macro new pecan.CoAction(Accept(function(self:pecan.Co<$tin, $tout>, value:$tin):Void {
            $tmpVarAccess = value;
          })));
          macro $tmpVarAccess;
        case _:
          ExprTools.map(e, walkExpr.bind(_, allowAccept));
      });
    }
    function walkStatement(e:Expr):Void {
      function pushSync():Void {
        top.push(macro new pecan.CoAction(Sync(function(self:pecan.Co<$tin, $tout>):Void {
          $e{walkExpr(e)};
        })));
      }
      top.push(switch (e.expr) {
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
            return $e{walkExpr(expr)};
          }));
        case ECall(f, args):
          var typed = try Context.typeExpr(macro function(self:pecan.Co<$tin, $tout>) {
            $f;
          }) catch (e:Dynamic) null;
          if (typed == null)
            return pushSync();
          switch (typed.expr) {
            case TFunction({expr: {expr: TBlock([{expr: TField(_, FStatic(_, _.get().meta.has(":pecan.suspend") => true))}])}}):
              var args = args.map(walkExpr.bind(_, true));
              args.push(macro self);
              args.push(macro wakeup);
              macro new pecan.CoAction(Suspend(function(self:pecan.Co<$tin, $tout>, wakeup:() -> Void):Bool {
                return $f($a{args});
              }));
            case _:
              return pushSync();
          }
        case EBlock(bs):
          var sub = macro $a{sub(() -> bs.map(walkStatement))};
          macro new pecan.CoAction(Block($sub));
        case EIf(cond, eif, eelse):
          var subif:Expr = macro $a{flatten(sub(() -> walkStatement(eif)))};
          var subelse:Expr = macro null;
          if (eelse != null) subelse = macro $a{flatten(sub(() -> walkStatement(eelse)))};
          macro new pecan.CoAction(If(function(self:pecan.Co<$tin, $tout>):Bool return $e{walkExpr(cond)}, $subif, $subelse));
        case EWhile(cond, e, normalWhile):
          var sub:Expr = macro $a{flatten(sub(() -> walkStatement(e)))};
          macro new pecan.CoAction(While(function(self:pecan.Co<$tin, $tout>):Bool return $e{walkExpr(cond, false)}, $sub, $v{normalWhile}));
        case _:
          return pushSync();
      });
    }
    var converted = sub(() -> walkStatement(ctx.block));
    ctx.block = macro $a{converted};
    // Sys.println(new haxe.macro.Printer().printExpr(ctx.block));
  }
  */

  /**
    Builds and returns a factory subtype.
  **/
  static function buildFactory():Expr {
    var tin = ctx.typeInput;
    var tout = ctx.typeOutput;
    var varsTypePath = ctx.varsTypePath;
    var factoryTypePath = {name: 'CoFactory$typeCounter', pack: ["pecan", "instances"]};
    var factoryTypeName = factoryTypePath.name;
    var factoryType = macro class $factoryTypeName extends pecan.CoFactory<$tin, $tout> {
      public function new(actions:Array<pecan.CoAction<$tin, $tout>>) {
        super(actions, args -> {
          var ret = new $varsTypePath();
          $b{
            [
              for (i in 0...ctx.arguments.length)
                macro $p{["ret", ctx.arguments[i].renamed]} = args[$v{i}]
            ]
          };
          ret;
        }, $v{ctx.entryPosition});
      }
    };
    factoryType.pack = factoryTypePath.pack;
    factoryType.fields.push({
      access: [APublic],
      kind: FFun({
        args: [
          for (i in 0...ctx.arguments.length)
            {
              name: 'arg$i',
              type: ctx.arguments[i].type,
              opt: ctx.arguments[i].argOptional
            }
        ],
        expr: macro return $e{
          {
            expr: ECall({expr: EConst(CIdent("runBase")), pos: ctx.pos}, [
              {
                expr: EArrayDecl([
                  for (i in 0...ctx.arguments.length)
                    {
                      expr: EConst(CIdent('arg$i')),
                      pos: ctx.pos
                    }
                ]),
                pos: ctx.pos
              }
            ]),
            pos: ctx.pos
          }
        },
        ret: macro:pecan.Co<$tin, $tout>
      }),
      name: "run",
      pos: ctx.pos
    });
    // Sys.println(new haxe.macro.Printer().printTypeDefinition(factoryType));
    Context.defineType(factoryType);
    // actions are passed by argument to allow for closure variable capture
    return macro new $factoryTypePath(${ctx.block});
  }

  /**
    Parses an expr like `(_ : Type)` to a ComplexType.
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
      entryPosition: 0,
      pos: block.pos,
      localCounter: 0,
      varsTypePath: null,
      varsComplexType: null,
      locals: [],
      arguments: [],
      topScope: [],
      scopes: null,
      typeInput: parseIOType(tin),
      typeOutput: parseIOType(tout)
    };
    ctx.scopes = [ctx.topScope];

    initVariableClass();
    processArguments();
    processVariables();
    convert();
    finaliseVariableClass();
    var factory = buildFactory();

    typeCounter++;
    ctx = null;
    return factory;
  }
}
