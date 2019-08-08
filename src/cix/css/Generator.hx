package cix.css;

#if macro 
import tink.csss.Selector;
import haxe.macro.*;
import haxe.macro.Expr;
import haxe.macro.Type;
import tink.parse.*;
import cix.css.Ast;
import cix.css.*;

using StringTools;
using haxe.io.Path;
using haxe.macro.Tools;
using tink.MacroApi;
using tink.CoreApi;

class Generator {
  
  static var initialized = false;
  static final META = ':cix-output';
  static function resultExpr(localType:BaseType, pos:Position, className:String, css:String) 
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

  @:persistent static var counter = 0;

  static public var namespace = 
    switch Context.definedValue('cix-namespace') {
      case null | '': 'cix';
      case v: v; 
    }

  static function typeName(b:BaseType)
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

  static public dynamic function makeClass(src:DeclarationSource, decl:NormalizedDeclaration):String
    return join(strip([namespace, showSource(src), '${counter++}']));

  static public function rule(owner:BaseType, pos:Position, decl:NormalizedDeclaration, localMethod:String, p:Printer) {
    var cl = makeClass(InlineRule(pos, owner, localMethod), decl);
    return resultExpr(owner, pos, cl, p.print(cl, decl));
  }

}

enum DeclarationSource {
  InlineRule(pos:Position, localType:BaseType, localMethod:Null<String>);
  NamedRule(name:StringAt, localType:BaseType, localMethod:Null<String>);
  Field(name:StringAt, cls:BaseType);
}
#end