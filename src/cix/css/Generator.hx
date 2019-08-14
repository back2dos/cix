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
  static function localType():BaseType
    return switch Context.getLocalType().reduce() {
      case TInst(_.get() => t, _): t;
      case TAbstract(_.get() => t, _): t;
      default: throw 'assert';
    }

  static public var printer = new Printer();

  static function normalize(decl, pos)
    return new Normalizer(
      tink.parse.Reporter.expr(Context.getPosInfos(pos).file),
      (name, reporter) -> (_, _) -> Failure(reporter.makeError('unknown method ${name.value}', name.pos))
    ).normalize(decl);

  static function localMethod(pos:Position) {
    var ret = Context.getLocalMethod();

    if (!isEmbedded) {
      var cl = Context.getLocalClass().get();
      switch [cl.findField(ret, true), cl.findField(ret, false)] {
        case [v, null] | [null, v]: 
          switch v.kind {
            case FMethod(MethInline) | FVar(AccInline, _):
              var pos = 
                switch [Context.getPosInfos(Context.currentPos()), Context.getPosInfos(pos)] {
                  case [p1, p2] if (p1.file == p2.file && p1.min < p2.min && p1.max > p2.max):
                    Context.makePosition({ file: p1.file, min: p1.min, max: p2.min });
                  default: pos;
                }
              pos.error('cannot declare styles in inline fields/methods in embedded mode');
            default:
          }
        default: throw 'assert';
      }
    }
    return ret;
  }

  static public function makeRule(e) {
    var decl = normalize(Parser.parseDecl(e).sure(), e.pos),
        src = InlineRule(e.pos, localType(), localMethod(e.pos));

    var cl = makeClass(src, decl);
    return macro @:pos(e.pos) ${export(src, [{ field: { value: 'css', pos: e.pos }, className: cl, css: printer.print(cl, decl) }])}.css;
  }

  static public function makeSheet(e) {
    var sheet = Parser.parseDecl(e).sure(),
        t = localType(),
        localMethod = localMethod(e.pos);

    if (sheet.properties.length > 0)
      sheet.properties[0].name.pos.error('no properties allowed on top level');

    if (sheet.mediaQueries.length > 0)
      sheet.mediaQueries[0].conditions[0].pos.error('no properties allowed on top level');

    sheet = {
      properties: sheet.properties,
      keyframes: sheet.keyframes,
      variables: sheet.variables,
      fonts: sheet.fonts,
      mediaQueries: sheet.mediaQueries,
      childRules: [
        for (c in sheet.childRules)
          switch c.selector.value {
            case [[
                { tag: name, id: null, classes: [] } 
              | { tag: '' | '*' | null, classes: [name], id: null }
              | { classes: [], tag: '' | '*' | null, id: name }
              ]]: 
                {
                  declaration: c.declaration,
                  selector: {
                    pos: c.selector.pos,
                    value: [[{ classes: [makeClass(NamedRule({ pos: c.selector.pos, value: name }, t, localMethod), null)] }]]
                  }
                }
            default: c.selector.pos.error('only simple selectors allowed here');
          }
      ],
    };

    return macro null;
  }

  static final META = ':cix-output';
  static final isEmbedded = #if cix_output false #else true #end;
  static var initialized = false;
  static function export(src:DeclarationSource, classes:ListOf<{ final field:StringAt; final className:String; final css:String; }>) 
    return {
      var pos = 
        switch src {
          case InlineRule(pos, _) 
              | NamedRule({ pos: pos }, _) 
              | Field({ pos: pos}, _): 
                pos;
        };
        
      if (!initialized) {
        initialized = true;
        #if cix_output
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
                  case TInst(_.get() => cl, _) if (cl.meta.has(META) && cl.meta.has(':used')):
                    for (f in cl.fields.get())
                      for (tag in f.meta.extract(META))
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
        #else
          switch Context.getType('cix.css.Runtime').reduce() {
            case TInst(_.get().meta.has(':notSupported') => true, _):
              pos.error('Embedded mode not supported on this platform. See https://github.com/back2dos/cix#css-generation');
            default:
          }
        #end
      }
          
      var name = 'Cix${counter++}'; // TODO: should be a separate counter

      var cls = {
        var p = name.asTypePath();
        macro class $name {
          function new() {}
          static public final inst = new $p();
        }
      }

      cls.meta.push({ name: META, params: [], pos: pos });
      
      for (c in classes)
        cls.fields.push({
          name: c.field.value,
          pos: c.field.pos,
          access: [APublic, AFinal],
          kind: FVar(
            macro : tink.domspec.ClassName, 
            #if cix_output 
              macro $v{c.className} 
            #else 
              macro cix.css.Declarations.add($v{c.className}, () -> $v{c.css})
            #end  
          ),
          meta: [#if cix_output { name: META, params: [macro $v{c.css}], pos: c.field.pos } #end],
        });

      Context.defineType(cls);

      macro @:pos(pos) $i{name}.inst;
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

}

enum DeclarationSource {
  InlineRule(pos:Position, localType:BaseType, localMethod:Null<String>);
  NamedRule(name:StringAt, localType:BaseType, localMethod:Null<String>);
  Field(name:StringAt, cls:BaseType);
}
#end