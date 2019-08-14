# cix: Css In Haxe

This library aims at creating (semi-)scoped CSS styles for Haxe projects. 

Sample usage:

```haxe
var big = cix.Style.rule('
  font-size: 2em;
  font-weight: bold;
  padding: 1em;
');

document.body.innerHTML = '<button class="$big">Big Button!</button>';
```

In essence, it offers macros that consume style declarations and produce CSS class names, which you can then apply to elements. A CSS classname is defined like so:

## Class Names

```haxe
package tink.domspec;

abstract ClassName(String) to String {
  
  public function add(that:ClassName):ClassName;

  @:from static function ofMap(parts:Map<String, Bool>):ClassName;  
  @:from static function ofArray(parts:Array<String>):ClassName;
  @:from static function ofString(s:String):ClassName;
  @:from static function ofDynamicAccess(parts:haxe.DynamicAccess<Bool>):ClassName;
}
```

With such class names, you can write code like `<button class=${BUTTON.add(HUGE)} />` (assuming both `BUTTON` and `HUGE` being class names). 

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

Various kinds of syntax are supported by cix in order to cause as much pain and confusion as possible. It's advisable to mix them erratically to maximize hardship.

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
  border = 'none !important';
  var color = 'red';
  div => {
    padding = '2em';
    background = color;
  }
  '&:hover' => {
    background = color;
    div => {
      background = 'blue';
    }
  }
})
```

To be documented ...

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
    background = $color;
    div => '
      background: blue;
    '
  }}
')
```

Mixing syntax in this manner is a great way to make the lives of your colleages miserable. There is one other use case though: easy copy-pasting of styles from one syntax into another, during a refactoring that will of course be followed up by a second step that unfies syntax.

# CSS generation

The css can be generated in two different modes, i.e. embedded or separate.

## Embedded CSS

In this mode, the CSS is embedded into the output, and will be registered via `cix.css.Runtime.addRule`, which is only implemented for the browser (i.e. it will create a style sheet on the fly and add rules as necessary). If you target any other environment, you need shadow the class with an implementation that can do the job.

## Separate CSS

In this mode, cix will output the CSS into a standalone file that you may use as you see fit. To do that, you need to set the `-D cix-output` define in any of these ways:

- `-D cix-output=/absolute/path/file.css`
- `-D cix-output=./path/relative/to/cwd/file.css`
- `-D cix-output=path/relative/to/compiler-output/file.css`