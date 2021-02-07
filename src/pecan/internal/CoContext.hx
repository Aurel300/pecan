package pecan.internal;

#if macro

/**
Central macro for coroutine building. Dispatches calls to other classes in the
package.
 */
class CoContext {
  public static var instanceCtr = 0;

  public static function build(block:Expr, eIn:Expr, eOut:Expr, debug:Bool):Expr {
    var ctx = new CoContext(block, eIn, eOut, debug);
    ctx.defineInstance();
    ctx.typeExpr();
    ctx.canonise();
    ctx.analyse();
    ctx.embed();
    ctx.defineFactory();
    return ctx.closure();
  }

  public var debug:Bool;
  public var pos:Position;
  public var args:Array<FunctionArg> = [];
  public var ctIn:ComplexType;
  public var ctOut:ComplexType;
  public var ctRet:ComplexType;
  public var tIn:Type;
  public var tOut:Type;
  public var tRet:Type;
  public var hasIn:Bool;
  public var hasOut:Bool;
  public var hasRet:Bool;
  public var tpCo:TypePath;
  public var ctCo:ComplexType;
  public var tpFactory:TypePath;
  public var ctFactory:ComplexType;
  public var block:Expr;
  public var typedBlock:TypedExpr;
  public var cfg:Cfg;
  public var processedBlock:TypedExpr;

  var tempVarCtr = 0;

  public function new(block:Expr, eIn:Expr, eOut:Expr, debug:Bool) {
    this.debug = debug;
    pos = block.pos;
    ctRet = (macro : Void);
    this.block = (switch (block.expr) {
      case EFunction(_, f):
        args = f.args;
        for (a in args) {
          // normalise argument types
          if (a.type != null) {
            a.type = Context.toComplexType(Context.resolveType(a.type, pos));
          }
        }
        if (f.ret != null) {
          ctRet = f.ret;
        }
        f.expr;
      case _: block;
    });
    setupTypes(eIn, eOut);
  }

  public function fresh():String {
    return '_pecan_temp_${tempVarCtr++}';
  }

  function setupTypes(eIn:Expr, eOut:Expr):Void {
    ctIn = parseIOType(eIn);
    ctOut = parseIOType(eOut);
    tIn = Context.resolveType(ctIn, pos);
    tOut = Context.resolveType(ctOut, pos);
    tRet = Context.resolveType(ctRet, pos);
    // normalise types
    ctIn = Context.toComplexType(tIn);
    ctOut = Context.toComplexType(tOut);
    ctRet = Context.toComplexType(tRet);
    hasIn = !tIn.match(TAbstract(_.get().name => "Void", []));
    hasOut = !tOut.match(TAbstract(_.get().name => "Void", []));
    hasRet = !tRet.match(TAbstract(_.get().name => "Void", []));
    var instanceNum = instanceCtr++;
    tpCo = {
      name: 'CoInstance_${instanceNum}', // TODO: more stable naming
      pack: ["pecan", "instances"],
    };
    ctCo = TPath(tpCo);
    tpFactory = {
      name: 'CoFactory_${instanceNum}',
      pack: ["pecan", "instances"],
    };
    ctFactory = TPath(tpFactory);
  }

  /**
    Parses an expr like `(_ : Type)` to a ComplexType.
   */
  static function parseIOType(e:Expr):ComplexType {
    if (e == null)
      return (macro : Void);
    return (switch (e) {
      case {expr: ECheckType(_, t) | EParenthesis({expr: ECheckType(_, t)})}: t;
      case macro null: macro:Void;
      case _: throw "invalid i/o type";
    });
  }

  function defineInstance():Void {
    var ctRetAdj = !hasRet ? (macro : pecan.Void) : ctRet;
    var tdCo = macro class CoInstance implements pecan.ICo<$ctIn, $ctOut, $ctRetAdj> {
      public var state(get, never):pecan.CoState;
      public var returned(get, never):Null<$ctRetAdj>;
      public var onHalt:()->Void = () -> {};
      var actions:()->Int;
      var accepts:(val:$ctIn)->Int;
      var yields:()->$ctOut;
      var labels:Map<String, Int>;
      var ready:Bool = true;
      var terminated:Bool = false;
      var accepting:Bool = false;
      var yielding:Bool = false;
      var returnedValue:Null<$ctRetAdj>;
      var cfgState:Int = 0;

      function new() {}

      inline function get_state():pecan.CoState {
        return (if (terminated) {
          pecan.CoState.Terminated;
        } else if (accepting) {
          pecan.CoState.Accepting;
        } else if (yielding) {
          pecan.CoState.Yielding;
        } else if (ready) {
          pecan.CoState.Ready;
        } else {
          pecan.CoState.Suspended;
        });
      }

      inline function get_returned():Null<$ctRetAdj> $e{hasRet ? macro {
        return returnedValue;
      } : macro {
        return pecan.Void.Void.Void;
      }};

      public function tick():Void {
        if (!ready)
          return;
        while (ready) cfgState = actions();
      }

      public function suspend():Void {
        ready = false;
      }

      public function wakeup():Void {
        if (terminated || accepting || yielding)
          throw "invalid state - can only wakeup Co in Ready or Suspended state";
        ready = true;
        tick();
      }

      public function terminate():Void {
        terminated = true;
        ready = false;
      }

      public function give(value:$ctIn):Void $e{hasIn ? macro {
        tick();
        if (!accepting)
          throw "invalid state - can only give to Co in Accepting state";
        cfgState = accepts(value);
        accepting = false;
        wakeup();
      } : macro throw "cannot give to this coroutine"};

      public function take():$ctOut $e{hasOut ? macro {
        tick();
        if (!yielding)
          throw "invalid state - can only take from Co in Yielding state";
        yielding = false;
        var ret = yields();
        wakeup();
        return ret;
      } : macro throw "cannot take from this coroutine"};

      public function goto(label:String):Void {
        if (terminated)
          throw "invalid state - Co is terminated";
        if (!labels.exists(label))
          throw "no such label";
        cfgState = labels[label];
        accepting = yielding = false;
        wakeup();
      }
    };
    tdCo.meta.push({
      name: ":using",
      params: [macro pecan.CoTools],
      pos: pos,
    });
    tdCo.name = tpCo.name;
    tdCo.pack = tpCo.pack;
    Context.defineType(tdCo);
  }

  function typeExpr():Void {
    var f = macro function(
      _pecan_self:$ctCo,
      self:$ctCo,
      // TODO: don't generate accept or yield when !hasIn or !hasOut
      accept:()->$ctIn,
      yield:$ctOut->Void,
      suspend:()->Void,
      label:String->Void,
      terminate:()->Void
    ):$ctRet {};
    switch (f.expr) {
      case EFunction(_, f):
        args.iter(f.args.push);
        f.expr = block;
      case _: throw "!";
    }
    typedBlock = Context.typeExpr(f);
  }

  function canonise():Void {
    var canoniser = new Canoniser(this);
    switch (typedBlock.expr) {
      case TFunction(tf):
        tf.expr = canoniser.canonise(tf.expr);
        if (debug) trace("canonised TAST", new haxe.macro.Printer().printExpr(Context.getTypedExpr(tf.expr)));
      case _: throw "!";
    }
  }

  function analyse():Void {
    var analyser = new Analyser(this);
    cfg = analyser.analyse(typedBlock);
  }

  function embed():Void {
    var embedder = new Embedder(this);
    processedBlock = embedder.embed(cfg);
  }

  function defineFactory():Void {
    var tdFactory = macro class CoFactory {
      public function new(init) {
        this.init = init;
      }
    };
    tdFactory.fields.push({
      name: "init",
      pos: pos,
      access: [AFinal],
      kind: FVar(TFunction([ctCo].concat(args.map(a -> a.type)), (macro : Void)), null)
    });
    tdFactory.fields.push({
      name: "run",
      pos: pos,
      access: [APublic],
      kind: FFun({
        args: args,
        ret: ctCo,
        expr: macro {
          var _pecan_ret = @:privateAccess new $tpCo();
          init($a{[macro _pecan_ret].concat(args.map(a -> macro $i{a.name}))});
          return _pecan_ret;
        },
      }),
    });
    tdFactory.name = tpFactory.name;
    tdFactory.pack = tpFactory.pack;
    Context.defineType(tdFactory);
  }

  function closure():Expr {
    return macro new $tpFactory($e{Context.storeTypedExpr(processedBlock)});
  }
}

#end
