package pecan;

/**
Provides a syntactic shortcut for immediately invoked coroutines with no input,
no output, and no arguments. Use in classes by implementing this interface.

```haxe
!{
  ...
}
```

Is translated into:

```haxe
pecan.Co.co({
  ...
}).run();
```

The coroutine is also immediately `tick`ed.
 */
@:autoBuild(pecan.internal.Syntax.build()) interface Syntax {}
