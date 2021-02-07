<!--menu:Implementation details-->
<!--label:implementation-->
# Implementation details

This chapter describes some internal aspects of `pecan`.

<!--label:overview-->
## Overview

A `pecan.Co.co(...)` (or any of the syntax shorthands) will perform the following steps:

 - If the expression was a function, remember the arguments and continue with the body of the function.
 - Check the I/O types and normalise them.
   - Types are normalised with [`resolveType`](api:haxe/macro/Context#resolveType), followed by [`toComplexType`](api:haxe/macro/Context#toComplexType).
 - Define the instance type of the coroutine.
   - This type must be defined quite early so that the coroutine can access its own instance when typing the body expression.
 - Type a function of the form `function(reserved..., args...) { body; }`.
   - `reserved...` are `pecan`-reserved identifiers, such as `suspend` or `accept`. These must be in context for the `body` to type properly.
 - Canonise the typed AST.
   - This step converts expressions into a larger number of simpler expressions and many temporary variables. This allows the analysis performed in the next step to be simpler. For example, any `accept()` call will end up in its own "statement" or in a `somevar = accept()` assignment.
 - Convert the AST into a graph by performing [control flow analysis](https://en.wikipedia.org/wiki/Control_flow_analysis).
 - Embed the graph back into the untyped AST as a state machine.
   - The embedding is a closure that first defines variables that are used from multiple CFG states, then defines the behaviour of `accept`, `yield` and the coroutine itself as a set of functions, each of which is approximately in the form `while (validState) currentState = (switch (currentState) { ... })`. The cases of the `switch` correspond to CFG nodes.
 - Define the factory type of the coroutine.
 - Return an expression of the form `new Factory((co, args...) -> { ... })`.
   - The embedded graph is the closure given as a parameter to the factory. This allows closure semantics, i.e. the coroutine can access variables defined outside its own body.

<!--label:implementation-types-->
## Type system

### Factory type

Every occurrence of `pecan.Co.co(...)` internally declares a new class that is a *factory* for instances of the created coroutine. This class cannot implement any particular interface, because every coroutine declaration may have a different number of arguments. Informally, the interface is:

```haxe
interface CoFactory<T> { // T is the coroutine instance type
  function run(args...):T;
  function runSuspended(args...):T;
}
```

### Instance type

Every occurrence of `pecan.Co.co(...)` also declares an *instance* type. An instance represents a called coroutine and it is responsible for storing its internal state.

Every coroutine instance type implements the [interface `pecan.ICo<TIn, TOut, TRet>`](api-pecan-ico), where:

 - `TIn` is the input type (the type returned by [`accept()` calls](features-io)) or `Void`,
 - `TOut` is the output type (the argument provided to [`yield(...)` calls](features-io)) or `Void`, and
 - `TRet` is the return type.

A `Void` return type is always replaced by [`pecan.Void`](repo:src/pecan/Void.hx), to avoid issues with `Void cannot be used as a value` errors in Haxe.

<!--label:history-->
## History

The current version of `pecan` is my second attempt at macro-based Haxe coroutines. The paper ["Theory and Practice of Coroutines with Snapshots"](https://2018.ecoop.org/details/ecoop-2018-papers/14/Theory-and-Practice-of-Coroutines-with-Snapshots) (A. Prokopec and F. Liu, ECOOP 2018) provided a source of inspiration for some aspects of the current implementation.

The first version (archived on GitHub in commit [`c6c1a75`](https://github.com/Aurel300/pecan/commit/c6c1a751307976b6f6abfdb63954ac574ab4002f)) was based on transforming the untyped AST. This approach had many problems, required explicit type annotations in many places that Haxe would normally infer, and could not handle many parts of Haxe syntax, such as `try ... catch` blocks.
