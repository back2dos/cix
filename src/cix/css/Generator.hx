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

using sys.FileSystem;
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

    var file = Context.resolvePath('mime-db.json');
    var source = sys.io.File.getContent(file);

    var raw:haxe.DynamicAccess<{ extensions: Null<Array<String>> }> = Context.parse(source, Context.makePosition({ file: file, min: 0, max: file.length })).eval();
    [for (key => value in raw)
      if (value.extensions != null)
        for (ext in value.extensions) ext => key
    ];
  });

  static var calls:CallResolver = {
    mix: CallResolver.makeCall3(valToCol, valToCol, valToRatio, (c1, c2, f) -> Success(VColor(c1.mix(c2, f))), .5),
    invert: CallResolver.makeCall1(valToCol, c -> Success(VColor(c.invert()))),
    raw: CallResolver.makeCall1(valToStr, s -> Success(VCall({ value: 'raw', pos: s.pos }, [{ pos: s.pos, value: VString(s.value) }]))),
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

  static function parseConstant(path:StringAt, expr:TypedExpr) {

    function fail(reason):Dynamic
      return path.pos.error('${path.value} $reason');

    function getString(t:TypedExpr):String
      return switch t.expr {
        case TConst(TString(v) | TInt(Std.string(_) => v) | TFloat(v)): v;
        case TBinop(OpAdd, t1, t2): getString(t1) + getString(t2);
        default: fail('is not a constant string nor number');
      }

    return switch Parser.parseVal({ pos: expr.pos, expr: EConst(CString(getString(expr))) }) {
      case Success({ components: [[v]], importance: 0 }): v;
      case Success(_):
        fail('should be a single css value');
      case Failure(e):
        fail('is not a css value because ${e.message}');
    }
  }

  static function resolveDotPath(s:StringAt)
    return switch Context.typeExpr(macro @:pos(s.pos) $p{s.value.split('.')}) {
      case { expr: TField(_, fa) }:
        switch fa {
          case FStatic(_, _.get() => f) if (f.isFinal || f.kind.match(FVar(AccInline, _))):
            parseConstant(s, f.expr());
          default: s.pos.error('can only access final or inline static fields');
        }
      case { expr: TLocal(_) }: s.pos.error('cannot access local variables');
      case t:
        parseConstant(s, t);
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

  static final META = ':cix.output';
  static final isEmbedded = #if cix_output false #else true #end;
  static var initialized = false;
  #if cix_output
    static final exported = new Array<Named<String>>();
  #end
  @:persistent static var classCounter = 0;
  static function export(pos:Position, classes:ListOf<{ final field:StringAt; final className:String; final css:String; }>)
    return {
      if (!initialized) {
        initialized = true;
        #if cix_output
          #if (cix_output != "skip")
          var kept = new Map();
          tink.OnBuild.after.exprs.whenever(_ -> _ -> e -> switch e {
            case { expr: TCast({ expr: TConst(TString(s)) }, null), t:TAbstract(_.toString() => 'tink.domspec.ClassName', _) }:
              kept[s] = true;
            default:
          });

          tink.OnBuild.after.types.after(tink.OnBuild.EXPR_PASS, types -> {
            function ensureDir(path:String) {
              var directory = path.directory();
              if (!directory.exists()) {
                ensureDir(directory);
                directory.createDirectory();
              }
              return path;
            }
            var out =
              sys.io.File.write(
                ensureDir(
                  switch Context.definedValue('cix_output').trim() {
                    case asIs = _.charAt(0) => '.' | '/':
                      asIs;
                    case relToOut:
                      Path.join([sys.FileSystem.absolutePath(Compiler.getOutput().directory()), relToOut]);
                  }
                )
              );

            var first = true;
            for (e in exported)
              if (kept[e.name]) {
                var css = e.value;
                if (first)
                  first = false;
                else
                  css = '\n\n\n$css';
                out.writeString(css);
              }
            out.close();
          });
          #end
        #else
          switch Context.getType('cix.css.Runtime').reduce() {
            case TInst(_.get().meta.has(':notSupported') => true, _):
              pos.error('Embedded mode not supported on this platform. See https://github.com/back2dos/cix#css-generation');
            default:
          }
        #end
      }

      var buf = new StringBuf();
      for (c in classes) {
        buf.add(c.className);
        buf.add(c.css);
        #if cix_output
          exported.push(new Named(c.className, c.css));
        #end
      }
      var name = 'Cix${haxe.crypto.Sha256.encode(buf.toString())}';

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
          access: [APublic, AFinal #if cix_output , AStatic, AInline #end],
          kind: FVar(
            null,
            #if cix_output
              macro (cast $v{c.className}:tink.domspec.ClassName)
            #else
              macro cix.css.Declarations.add(cast $v{c.className}, () -> $v{c.css})
            #end
          ),
          meta: [#if cix_output { name: META, params: [macro $v{c.className}, macro $v{c.css}], pos: c.field.pos } #end],
        });

      Context.defineType(cls);

      macro @:pos(pos) $i{name} #if !cix_output .inst #end;
    }

  @:persistent static var counter = 0;

  static public var namespace =
    switch Context.definedValue('cix-namespace') {
      case null | '': 'cx';
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