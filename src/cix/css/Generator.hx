package cix.css;

#if macro
import cix.css.Ast;
import tink.csss.Selector;
import haxe.macro.*;
import haxe.macro.Expr;
import haxe.macro.Type;
import tink.parse.*;

using StringTools;
using haxe.io.Path;
using haxe.macro.Tools;
using tink.MacroApi;
using tink.CoreApi;

class Generator<Error, Result> {//TODO: should work outside macro mode
  
  #if macro 
  static var initialized = false;
  static final META = ':cix-output';
  static public function resultExpr(localType:BaseType, pos:Position, className:String, css:String) 
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

  static public dynamic function generateClass(src:DeclarationSource, decl:Declaration):String
    return join(strip([namespace, showSource(src), '${counter++}']));

  var reporter:Reporter<Position, Error>;
  
  function compoundValue(v:CompoundValue) 
    return [
      for (v in v.components) 
        [for (single in v) singleValue(single)].join(' ')
    ].join(', ');

  var getCall:(name:StringAt, reporter:Reporter<Position, Error>)->((orig:SingleValue, args:ListOf<SingleValue>)->Outcome<SingleValue, Error>);
  var generateResult:(pos:Position, className:String, css:String)->Result;
  var makeClass:(src:DeclarationSource, decl:Declaration)->String;

  public function new(reporter, getCall, generateResult, ?makeClass) {
    this.reporter = reporter;
    this.getCall = getCall;
    this.generateResult = generateResult;
    this.makeClass = switch makeClass {
      case null: generateClass;
      case v: v;
    }
  }

  function fail(message, pos):Dynamic
    return throw reporter.makeError(message, pos);

  public function rule(src:DeclarationSource, d:Declaration) {
    var className = generateClass(src, d);
    return generateResult(
      switch src {
        case InlineRule(pos, _): pos;
        case NamedRule(n, _) | Field(n, _): n.pos;
      },
      className, 
      {
        var d = normalize(d);
        if (d.mediaQueries.length > 0)
          fail('media queries currently not implemented', d.mediaQueries[0].conditions[0].pos);

        var ret = [];

        for (k in d.keyframes)
          ret.push(generateKeyframes(k));

        for (f in d.fonts)
          ret = ret.concat(properties(() -> '@font-face', f));
        
        ret.push(generateDeclaration(['.$className'], d));

        ret.join('\n\n');
      }
    );
  }

  function generateKeyframes(k:Keyframes)
    return 
      '@keyframes ${k.name.value} {\n'
        + [for (f in k.frames) properties(() -> '${f.pos}%', f.properties, '\t').join('\n')].join('\n') 
        + '\n}';

  function mediaAnd(c1:FullMediaCondition, c2:FullMediaCondition):FullMediaCondition {
    if (c1.negated != c2.negated)
      fail('cannot nest negated and non-negated queries', c2.pos);//probably should try to translate the query to its negative

    return {
      pos: c2.pos,
      value: And(c1.value, c2.value),
      negated: c2.negated
    }
  }  

  function normalize(d:Declaration):NormalizedDeclaration {
    //TODO: this will also have to perform variable substitution
    var fonts:Array<FontFace> = [],
        keyframes:Array<Keyframes> = [],
        mediaQueries:Array<MediaQueryOf<PlainDeclaration>> = [];
    
    function sweep(
        d:Declaration, 
        selectors:ListOf<Located<Selector>>, 
        queries:ListOf<FullMediaCondition>,
        vars:Map<String, SingleValue>
      ):PlainDeclaration {

      vars = vars.copy();

      var resolve = id -> vars.get(id);

      function reduce(v)
        return this.reduce(v, resolve).sure();

      function props(raw:ListOf<Property>):ListOf<Property>
        return [for (p in raw) {
          name: p.name,
          value: {
            var c = p.value;
            {
              importance: c.importance,
              components: [for (values in c.components) [for (v in values) reduce(v)]]
            }
          }
        }];

      for (v in d.variables)
        switch v.value.components {//TODO: probably also forbid !important
          case [[s]]: vars.set(v.name.value, reduce(s));
          default: fail('variables must be initialized with a single value', v.name.pos);
        }

      for (k in d.keyframes) 
        keyframes.push({
          name: k.name,
          frames: [for (f in k.frames) {
            pos: f.pos,
            properties: props(f.properties)
          }]
        });

      for (f in d.fonts)
        fonts.push(props(f));

      for (q in d.mediaQueries) {

        //TODO: variable substitution in q.conditions

        var queries = switch queries {
          case []: q.conditions;
          default: [for (outer in queries) for (inner in q.conditions) mediaAnd(outer, inner)];
        }

        mediaQueries.push({
          conditions: queries,
          declaration: sweep(q.declaration, selectors, queries, vars)
        });
      }

      return {
        properties: props(d.properties),
        childRules: [for (c in d.childRules) {
          selector: c.selector,
          declaration: sweep(c.declaration, selectors.concat([c.selector]), queries, vars)
        }]
      }
    }

    var ret = sweep(d, [], [], new Map());

    return {
      fonts: fonts,
      keyframes: keyframes,
      mediaQueries: mediaQueries,
      properties: ret.properties,
      childRules: ret.childRules,
    }
  }  

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

  function generateDeclaration(paths:Array<String>, d:PlainDeclaration) {

    var ret = properties(paths.join.bind(',\n'), d.properties);

    for (c in d.childRules) {
      var decl = generateDeclaration(
        [for (p in paths) for (o in c.selector.value) Printer.combine(' ', p, o)], 
        c.declaration
      );
      if (decl != '') ret.push(decl);
    }

    return ret.join('\n\n');
  }

  function map(s:SingleValue, f:SingleValue->SingleValue)
    return f(switch s.value {
      case VBinOp(op, lh, rh):
        { pos: s.pos, value: VBinOp(op, f(lh), f(rh)) };
      case VCall(name, args):
        { pos: s.pos, value: VCall(name, [for (a in args) f(a)]) };
      default: s;
    });

  static var CSS_BUILTINS = {
    var list = [
      'calc',

      'url', 'format',
      
      'blur', 'brightness', 'contrast', 'hue-rotate', 'grayscale',
      
      'translate', 'translateX', 'translateY', 'translateZ', 'translate3d',
      'rotate', 'rotateX', 'rotateY', 'rotateZ', 'rotate3d',
      'scale', 'scaleX', 'scaleY', 'scale3d',
      'skew', 'skewX', 'skewY', 'skew3d',
      'perspective', 'matrix', 'matrix3d',
    ];

    [for (l in list) l => true];
  }

  function call(s, name:StringAt, args)
    return switch name.value {
      case CSS_BUILTINS[_] => true: Success(s);
      default: getCall(name, reporter)(s, args);
    }

  function reduce(s:SingleValue, resolve:String->Null<SingleValue>) {
    
    var error = None;

    function fail(msg, ?pos):Dynamic {
      var e = reporter.makeError(msg, switch pos {
        case null: s.pos;
        default: pos;
      });
      error = Some(e);
      throw error;
    }

    function unit(v:SingleValue)
      return switch v.value {
        case VNumeric(_, u): u;
        case VCall({ value: 'calc' }, _): MixedLength;
        default: fail('expected numeric value but got ${reducedValue(v)}', v.pos);
      }  

    function val(v:SingleValue)
      return switch v.value {
        case VNumeric(v, _): v;
        default: throw 'assert';
      }

    function unpack(v:SingleValue)
      return switch v.value { 
        case VCall({ value: 'calc' }, [v]): unpack(v);
        default: v;
      }

    return 
      try 
        Success(map(s, s -> switch s.value {
          case VVar(name):
            switch resolve(name) {
              case null: fail('unknown identifier $name', s.pos);
              case v: v;
            }
          case VBinOp(op, lh, rh):
            var unit = switch [op, unit(lh), unit(rh)] {
              case [OpMult, u, null] | [OpMult, null, u]: u;
              case [OpMult, a, b]: fail('cannot multiply $a and $b', s.pos);
              case [OpDiv, u, null]: u;
              case [OpDiv, _, u]: fail('divisor must be unitless, but has $u', s.pos);
              case [OpAdd | OpSubt, a, b] if (a == b): a;
              case [OpAdd | OpSubt, _.getKind() => a, _.getKind() => b]: 
                if (a == b) MixedLength;//todo: try avoiding nested calcs
                else fail('cannot perform $op on $a and $b', s.pos);
            }
            {
              pos: s.pos,
              value:
                if (unit == MixedLength)
                  VCall({ value: 'calc', pos: s.pos }, [s]);
                else {
                  var lh = val(lh),
                      rh = val(rh);

                  VNumeric(switch op {
                    case OpMult: lh * rh;
                    case OpDiv: lh / rh;
                    case OpAdd: lh + rh;
                    case OpSubt: lh - rh;
                  }, unit);
                }
            }
          case VCall(name, args):
            call(s, name, args).sure();
          default: s;
        }))
    catch (e:Dynamic) switch error {
      case Some(e): Failure(e);
      case None: throw e;
    }
  }

  function singleValue(s)
    return reducedValue(s);

  function reducedValue(s:SingleValue):String {

    function rec(s)
      return reducedValue(s);

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
  InlineRule(pos:Position, localType:BaseType, localMethod:Null<String>);
  NamedRule(name:StringAt, localType:BaseType, localMethod:Null<String>);
  Field(name:StringAt, cls:BaseType);
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
#end