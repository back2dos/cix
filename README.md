# cix: Css In Haxe

This library aims at creating (semi-)scoped CSS styles for Haxe projects. In essence, it consumes styles and produces CSS class names, which you can then apply to elements. A CSS classname is defined like so:

## Class Names

```haxe
package tink.domspec;

abstract ClassName(String) to String {
  
  @:op(a + b) public function add(that:ClassName):ClassName;

  @:from static function ofMap(parts:Map<String, Bool>):ClassName;  
  @:from static function ofArray(parts:Array<String>):ClassName;
  @:from static function ofString(s:String):ClassName;
  @:from static function ofDynamicAccess(parts:haxe.DynamicAccess<Bool>):ClassName;
}
```

With such class names, you can write code like `<button class=${BUTTON.add(HUGE)} />`.

To create these class names names via cix, you would use one of the macros from its facade:

```haxe
package cix;

class Style {
  static public macro function rule(css);
  static public macro function sheet(css);
}
```

The first macro creates a single `ClassName`, while the second creates an object, the fields of which are class names, so to create a `BUTTON` and a `HUGE` class, you would do either of the following (we'll talk about the syntax of defining the style in details just below):

1. Two single class names:

   ```haxe
   var BUTTON = cix.Style.rule('
     border: none;
     padding: 1em 2em;
     background: darkturquoise;
   ');
   var HUGE = cix.Style.rule({
     fontSize: '2em'
   });
   ```

2. A sheet with the two styles in it:

   ```haxe
   var styles = cix.Style.sheet({
     BUTTON: {
       border: none,
       padding: '1em 2em',
       background: darkturquoise
     },
     HUGE: {
       fontSize: '2em'
     }
   });
   var HUGE = styles.HUGE,
       BUTTON = style.BUTTON;
   ```

## Rule Syntax


### Sassy syntax

This syntax is leaning towards sass, to the degree that it's practical.

```haxe
css('
  border: none !important;
  $color: red;
  div {
    padding: 2em;
    background: $color;
  }  
  &:hover {
    background: $color;
    div {
      background: blue;
    }
  }
')
```

### Haxy syntax

```haxe
css({
  border: 'none !important',
  $color: red,
  div: {
    padding: '2em',
    background: $color,
  },
  '&:hover': {
    background: $color,
    div: {
      background: blue,
    }
  }
})
```

### Mixing both

You can put haxy rules into sassy rules wrapped by `${<haxy styles>}`, wherever a style block is expected. You can do the converse as `'{<sassy styles>}'`, like so:

```haxe
css('
  border: none !important;
  $color: red;
  div {
    padding: 2em;
    background: $color;
  }  
  &:hover ${{
    background: $color,
    div: '{
      background: blue;
    }'
  }}
')
```

You should avoid mixing syntax in this manner. It's mostly meant to easy copy-pasting styles from one syntax into another. Please note that in a haxy rule set, the distinction between a value and a sassy sub-rule is made by looking whether the first non-white-space character is a `{` or not. This is relatively fragile.