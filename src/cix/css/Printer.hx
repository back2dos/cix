package cix.css;

import cix.css.Ast;
import tink.csss.Selector;
import haxe.macro.*;

// #if macro
// import haxe.macro.Expr;
// import haxe.macro.Type;
// #end
import tink.parse.*;

using StringTools;

class Printer {
  
  function compoundValue(v:CompoundValue) 
    return [
      for (v in v.components) 
        [for (single in v) singleValue(single, hSpace)].join(' ')
    ].join(',$hSpace');

  var hSpace:String;
  var vSpace:String;
  var indent:String;

  public function new(?options:{ final ?indent:String; final ?hSpace:String; }) {
    
    this.hSpace = switch options {
      case null | { hSpace: null }: ' ';
      case { hSpace: v }: v;
    }

    this.indent = switch options {
      case null | { indent: null }: '  ';
      case { indent: v }: v;
    }

    this.vSpace = if (this.indent == '') '' else '\n';
  }

  function plainDeclaration(paths:Array<String>, d:PlainDeclaration, ?indent = '') {

    var ret = properties(paths.join.bind(',$vSpace$indent'), d.properties, indent);

    for (c in d.childRules) {
      var decl = plainDeclaration(
        [for (p in paths) for (o in c.selector.value) SelectorPrinter.combine(' ', p, o)], 
        c.declaration, 
        indent
      );
      if (decl != '') ret.push(decl);
    }

    return ret.join('$vSpace$vSpace');
  }

  public function print(path:String, d:NormalizedDeclaration) {
    var ret = [],
        paths = [path];

    for (k in d.keyframes)
      ret.push(printKeyframes(k));

    for (f in d.fonts)
      ret = ret.concat(properties(() -> '@font-face', f.value));
    
    ret.push(plainDeclaration(paths, d));

    for (m in d.mediaQueries) 
      ret.push('@media ${mediaQuery(m.conditions)} {$vSpace' + plainDeclaration(paths, d, indent) + '$vSpace}');

    return ret.join('$vSpace$vSpace');        
  }

  function mediaQuery(conditions:ListOf<FullMediaCondition>) {
    function cond(c:MediaCondition)
      return switch c {
        case And(a, b): '${cond(a)} and ${cond(b)}';
        case Feature(name, val): '(${name.value}:$hSpace${singleValue(val, hSpace)})';
        case Type(t): t;
      }
    return [for (c in conditions) 
      (if (c.negated) 'not' else '')
      + cond(c.value)
    ].join(',$vSpace');
  }

  function printKeyframes(k:Keyframes)
    return 
      '@keyframes ${k.name.value}$hSpace{$vSpace'
        + [for (f in k.frames) properties(() -> '${f.pos}%', f.properties, indent).join(vSpace)].join(vSpace) 
        + '$vSpace}';

  function properties(prefix, properties:ListOf<Property>, indent = '') 
    return 
      switch properties {
        case []: [];
        case props:

          var all = '$indent${prefix()}$hSpace{';
        
          for (p in props)
            all += '$vSpace$indent${this.indent}${p.name.value}:$hSpace${compoundValue(p.value)}${[for (i in 0...p.value.importance) '$hSpace!important'].join('')};';
        
          [all +'$vSpace$indent}'];
      }

  static public function singleValue(s:SingleValue, ?hSpace = ' '):String {

    function rec(s)
      return singleValue(s, hSpace);

    return switch s.value {
      case VNumeric(value, unit): 
        value + switch unit {
          case null: '';
          case v: v;
        }
      case VAtom(value):
        value;
      case VString(value):
        '"' + value.replace('"', '\\"') + '"';
      case VBinOp(op, rec(_) => lh, rec(_) => rh):
        '$lh$hSpace$op$hSpace$rh';
      case VCall(name, [for (a in _) rec(a)].join(',$hSpace') => args):
        '${name.value}($args)';
      case VColor(r, g, b, 1):
        '#${r.hex(2)}${g.hex(2)}${b.hex(2)}';
      case VColor(r, g, b, a):
        'rgba($r, $g, $b, $a)';
      default: 
        throw 'assert ${s.value}';
    }
  }
}

private class SelectorPrinter extends tink.csss.Printer {
  var path:String;
  var found:Bool = false;
  function new(space, path) {
    super(space);
    this.path = path;
  }

  static public function combine(space:String, path:String, option:SelectorOption) {
    var p = new SelectorPrinter(space, path);
    var ret = p.option(option);
    return 
      if (p.found) ret;
      else '$path $ret';
  }
  
  override public function part(s:SelectorPart) {
    var ret = super.part(s);
    return 
      if (ret.charAt(0) == '&') {
        found = true;
        path + ret.substr(1);
      }
      else ret;
  }
}