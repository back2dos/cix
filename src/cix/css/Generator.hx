package cix.css;

#if macro 
import tink.csss.Selector;
import haxe.macro.*;
import haxe.macro.Expr;
import haxe.macro.Type;
import tink.parse.*;
import cix.css.Ast;
import cix.css.*;
import tink.color.*;

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

  static function valToCol(v:SingleValue)
    return switch v.value {
      case VColor(c): Success(c);
      default: Failure('Color expected');
    }

  static function valToRatio(v:SingleValue)
    return switch v.value {
      case VNumeric(f, null): Success(f);
      case VNumeric(f, Pct): Success(f / 100);
      default: Failure('Ratio expected');
    }    

  static function valToAngle(v:SingleValue)
    return switch v.value {
      case VNumeric(f, null | Deg): Success(f);
      default: Failure('Ratio expected');
    }        

  static function valToStr(v:SingleValue):Outcome<StringAt, String>
    return switch v.value {
      case VString(s): Success({ value: s, pos: v.pos });
      default: Failure('String expected');
    }

  static function normalizer(pos)
    return new Normalizer(
      tink.parse.Reporter.expr(Context.getPosInfos(pos).file),
      calls,
      resolveDotPath
    );

  static var mimeTypes = Lazy.ofFunc(() -> {//TODO: this seems to be slow ... try to optimize
    var raw:haxe.DynamicAccess<{ extensions: Null<Array<String>> }> = haxe.Json.parse(sys.io.File.getContent(Context.resolvePath('mime-db.json')));
    [for (key => value in raw) 
      if (value.extensions != null)
        for (ext in value.extensions) ext => key
    ];
  });

  static var calls:CallResolver = {
    mix: CallResolver.makeCall3(valToCol, valToCol, valToRatio, (c1, c2, f) -> Success(VColor(c1.mix(c2, f))), .5),
    invert: CallResolver.makeCall1(valToCol, c -> Success(VColor(c.invert()))),
    fade: CallResolver.makeCall2(valToCol, valToRatio, (c, f) -> Success(VColor(c.with(ALPHA, Math.round(c.get(ALPHA) * f))))),
    opacity: CallResolver.makeCall2(valToCol, valToRatio, (c, f) -> Success(VColor(c.with(ALPHA, Math.round(ChannelValue.FULL * f))))),
    huerotate: CallResolver.makeCall2(valToCol, valToAngle, (c, f) -> Success(VColor(Color.hsv(c.hue + f, c.saturation, c.value)))),
    hue: CallResolver.makeCall2(valToCol, valToAngle, (c, f) -> Success(VColor(Color.hsv(f, c.saturation, c.value)))),
    saturate: CallResolver.makeCall2(valToCol, valToRatio, (c, f) -> Success(VColor(Color.hsv(c.hue, c.saturation * f, c.value)))),
    saturation: CallResolver.makeCall2(valToCol, valToRatio, (c, f) -> Success(VColor(Color.hsv(c.hue, f, c.value)))),
    dataUri: {
      CallResolver.makeCall2(valToStr, valToStr, 
        (path, contentType) -> {
          var file = Path.join([Context.getPosInfos(path.pos).file.directory(), path.value]);
          var content = 
            try sys.io.File.getBytes(file)
            catch (e:Dynamic) {
              return Failure({ value: 'cannot read file $file', pos: path.pos });
            }
          var contentType = switch contentType.value {
            case 'auto': switch mimeTypes.get()[path.value.extension()] {
              case null: 
                return Failure({ value: 'cannot automatically determine mime type of ${path.value}', pos: path.pos });
              case v: v;
            }
            case v: v;
          }
          Success(VCall({ value: 'url', pos: path.pos }, [{ pos: path.pos, value: VString('data:$contentType;base64,${haxe.crypto.Base64.encode(content)}')}]));
        },
        { value: 'auto', pos: (macro null).pos }
      );
    },
  }

  static function resolveDotPath(s:StringAt) 
    return switch Context.typeExpr(macro @:pos(s.pos) $p{s.value.split('.')}) {
      case { expr: TField(_, fa) }:
        switch fa {
          case FStatic(_, _.get() => f) if (f.isFinal || f.kind.match(FVar(AccInline, _))): 
            switch f.expr() {
              case { pos: pos, expr: TConst(TString(v)) }: 
                switch Parser.parseVal({ pos: pos, expr: EConst(CString(v)) }) {
                  case Success({ components: [[v]], importance: 0 }): v;
                  case Success(_): 
                    s.pos.error('${s.value} should be a single css value');
                  case Failure(e): 
                    s.pos.error('${s.value} is not a css value because ${e.message}');
                }
              default: 
                s.pos.error('${s.value} is not a string constant');
            }
          default: s.pos.error('can only access final or inline static fields');
        }
      case { expr: TLocal(_) }: s.pos.error('cannot access local variables');
      default: null;
    }

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
    var cl = makeClass(InlineRule(e.pos, localType(), localMethod(e.pos)));
    var decl = normalizer(e.pos).normalizeRule(parse(e));

    return macro @:pos(e.pos) ${export(e.pos, [{ field: { value: 'css', pos: e.pos }, className: cl, css: printer.print('.$cl', decl) }])}.css;
  }

  static function parse(e:Expr)
    return switch e {
      case macro @css $e: parse(e);
      case { expr: EConst(CString(v)) }: Parser.parseDecl(e).sure();
      case HxParser.parses(_) => true: HxParser.parse(e);
      default: e.reject('expected string literal or block or object literal');
    } 

  static public function makeSheet(e) {
    var sheet = normalizer(e.pos).normalizeSheet(parse(e));

    var type = localType(),
        method = localMethod(e.pos);
    
    return export(e.pos, [for (rule in sheet) {
      var cl = makeClass(NamedRule(rule.name, type, method));
      {
        field: rule.name,
        className: cl,
        css: printer.print('.$cl', rule.decl)
      }
    }]);
  }

  static final META = ':cix-output';
  static final isEmbedded = #if cix_output false #else true #end;
  static var initialized = false;
  @:persistent static var classCounter = 0;
  static function export(pos:Position, classes:ListOf<{ final field:StringAt; final className:String; final css:String; }>) 
    return {
      if (!initialized) {
        initialized = true;
        #if cix_output
          Context.onGenerate(types -> {
            Context.onAfterGenerate(() -> {

              var out = 
                sys.io.File.write(
                  switch Context.definedValue('cix_output').trim() {
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
          
      var name = 'Cix${classCounter++}';
      for (i in 0...100) // TODO: this loop pretty much duplicates logic in tink.macro.BuildCache
        if (name.definedType() == None) break;
        else name = 'Cix${classCounter++}';

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
      case null | '': 'χ';
      case v: v; 
    }

  static function typeName(b:BaseType)
    return join(b.pack.concat([b.name]));

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

  static public dynamic function makeClass(src:DeclarationSource, ?state:State):String
    return namespace + join(strip([showSource(src), id(counter++)]));

  static var CHARS = 'abcdefghijklmnopqrstuvwxyz0123456789_-';
  static function id(i:Int) {
    var ret = '';
    while (i > 0) {
      ret += CHARS.charAt(i % CHARS.length);
      i = Std.int(i / CHARS.length);
    }
    return ret;
  }

}

enum DeclarationSource {
  InlineRule(pos:Position, localType:BaseType, localMethod:Null<String>);
  NamedRule(name:StringAt, localType:BaseType, localMethod:Null<String>);
  Field(name:StringAt, cls:BaseType);
}
#end