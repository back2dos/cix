package cix.css;

import cix.css.Ast;
import tink.csss.Selector;
import haxe.macro.*;

#if macro
import haxe.macro.Expr;
import haxe.macro.Type;
#end
import tink.parse.*;

using StringTools;
#if macro
using haxe.io.Path;
using haxe.macro.Tools;
using tink.MacroApi;
#end
using tink.CoreApi;

typedef OwnerType = 
  #if macro 
    BaseType 
  #else 
    {
      final pack:Array<String>;
      final name:String;
    }  
  #end
;

class Generator<Result> {//TODO: should work outside macro mode
  
  #if macro 
  static var initialized = false;
  static final META = ':cix-output';
  static public function resultExpr(localType:OwnerType, pos:Position, className:String, css:String) 
    return {
      #if cix_output
        localType.meta.add(META, [macro @:pos(pos) $v{css}], pos);
        if (!initialized) {
          initialized = true;
          Context.onGenerate(types -> {
            Context.onAfterGenerate(() -> {

              var out = 
                sys.io.File.write(
                  switch Context.definedValue('cix-output').trim() {
                    case asIs = _.charAt(0) => '.' | '/':
                      asIs;
                    case relToOut:
                      Path.join([sys.FileSystem.absolutePath(Compiler.getOutput().directory()), relToOut]);
                  }
                );

              var first = true;
              for (t in types)
                switch t {
                  case TInst(_.get().meta => m, _)
                      | TEnum(_.get().meta => m, _)
                      | TAbstract(_.get().meta => m, _) if (m.has(META) && m.has(':used')):
                    for (tag in m.extract(META))
                      for (e in tag.params)
                        switch e.expr {
                          case EConst(CString(s)):
                            if (first)
                              first = false;
                            else 
                              s = '\n\n\n$s';
                            out.writeString(s);
                          default: throw 'assert';
                        }
                  default:
                }

              out.close();
            });
          });
        }
        macro @:pos(pos) ($v{className}:tink.domspec.ClassName);
      #else
        if (!initialized) {
          initialized = true;
          switch Context.getType('cix.css.Runtime').reduce() {
            case TInst(_.get().meta.has(':notSupported') => true, _):
              pos.error('Embedded mode not supported on this platform. See https://github.com/back2dos/cix#css-generation');
            default:
          }
        }
        macro @:pos(pos) cix.css.Declarations.add($v{className}, () -> $v{css});
      #end
    }
  #end

  @:persistent static var counter = 0;

  static public var namespace = 
    switch #if macro Context.definedValue #else Compiler.getDefine #end ('cix-namespace') {
      case null | '': 'cix';
      case v: v; 
    }

  static function typeName(b:OwnerType)
    return b.pack.concat([b.name]).join('.');

  static dynamic public function showSource(src:DeclarationSource)
    return
      #if debug
        switch src {
          case InlineRule(_, t, m): join([typeName(t), m]);
          case NamedRule(n, t, m): join([typeName(t), m, n.value]);
          case Field(n, t): join([typeName(t), n.value]);
        }
      #else
        '';
      #end

  static public function strip(parts:Array<String>)
    return [for (p in parts) if (p != null) switch p.trim() {
      case '': continue;
      case v: v;
    }];  

  static public dynamic function join(parts:Array<String>)
    return parts.join('–');// this is an en dash (U+2013) to avoid collision with the more likely minus

  static public dynamic function generateClass(src:DeclarationSource, decl:NormalizedDeclaration):String
    return join(strip([namespace, showSource(src), '${counter++}']));
  
  function compoundValue(v:CompoundValue) 
    return [
      for (v in v.components) 
        [for (single in v) singleValue(single)].join(' ')
    ].join(', ');

  var generateResult:(pos:Position, className:String, css:String)->Result;
  var makeClass:(src:DeclarationSource, decl:NormalizedDeclaration)->String;

  public function new(generateResult, ?makeClass) {
    this.generateResult = generateResult;
    this.makeClass = switch makeClass {
      case null: generateClass;
      case v: v;
    }
  }

  public function rule(src:DeclarationSource, d:NormalizedDeclaration) {
    var className = generateClass(src, d);
    return generateResult(
      switch src {
        case InlineRule(pos, _): pos;
        case NamedRule(n, _) | Field(n, _): n.pos;
      },
      className, 
      {
        var ret = [];

        for (k in d.keyframes)
          ret.push(generateKeyframes(k));

        for (f in d.fonts)
          ret = ret.concat(properties(() -> '@font-face', f));
        
        ret.push(generateDeclaration(['.$className'], d));

        for (m in d.mediaQueries) 
          ret.push('@media ${mediaQuery(m.conditions)} {\n' + generateDeclaration(['.$className'], d, '\t') + '\n}');

        ret.join('\n\n');
      }
    );
  }

  function mediaQuery(conditions:ListOf<FullMediaCondition>) {
    function cond(c:MediaCondition)
      return switch c {
        case And(a, b): '${cond(a)} and ${cond(b)}';
        case Feature(name, val): '(${name.value}: ${singleValue(val)})';
        case Type(t): t;
      }
    return [for (c in conditions) 
      (if (c.negated) 'not' else '')
      + cond(c.value)
    ].join(',\n');
  }

  function generateKeyframes(k:Keyframes)
    return 
      '@keyframes ${k.name.value} {\n'
        + [for (f in k.frames) properties(() -> '${f.pos}%', f.properties, '\t').join('\n')].join('\n') 
        + '\n}';

  function properties(prefix, properties:ListOf<Property>, indent = '') 
    return 
      switch properties {
        case []: [];
        case props:

          var all = '$indent${prefix()} {';
        
          for (p in props)
            all += '\n$indent\t${p.name.value}: ${compoundValue(p.value)}${[for (i in 0...p.value.importance) ' !important'].join('')};';
        
          [all +'\n$indent}'];
      }

  function generateDeclaration(paths:Array<String>, d:PlainDeclaration, ?indent = '') {

    var ret = properties(paths.join.bind(',\n$indent'), d.properties, indent);

    for (c in d.childRules) {
      var decl = generateDeclaration(
        [for (p in paths) for (o in c.selector.value) Printer.combine(' ', p, o)], 
        c.declaration, 
        indent
      );
      if (decl != '') ret.push(decl);
    }

    return ret.join('\n\n');
  }

  static public function singleValue(s:SingleValue):String {

    function rec(s)
      return singleValue(s);

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
        '$lh $op $rh';
      case VCall(name, [for (a in _) rec(a)].join(',') => args):
        '${name.value}($args)';
      default: 
        throw 'assert ${s.value}';
    }
  }
}

enum DeclarationSource {
  InlineRule(pos:Position, localType:OwnerType, localMethod:Null<String>);
  NamedRule(name:StringAt, localType:OwnerType, localMethod:Null<String>);
  Field(name:StringAt, cls:OwnerType);
}

private class Printer extends tink.csss.Printer {
  var path:String;
  var found:Bool = false;
  function new(space, path) {
    super(space);
    this.path = path;
  }

  static public function combine(space:String, path:String, option:SelectorOption) {
    var p = new Printer(space, path);
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