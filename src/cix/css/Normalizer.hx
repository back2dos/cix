package cix.css;

import tink.parse.*;
import tink.csss.Selector;
import cix.css.Ast;

using tink.CoreApi;

class Normalizer<Error> {

  var reporter:Reporter<Position, Error>;
  var resolver:StringAt->Null<SingleValue>;
  var callResolver:CallResolver;

  function fail(message, pos):Dynamic
    return throw reporter.makeError(message, pos);

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

      'rgb', 'rgba', 'hsl', 'hsla',

      'blur', 'brightness', 'contrast', 'hue-rotate', 'grayscale',

      'translate', 'translateX', 'translateY', 'translateZ', 'translate3d',
      'rotate', 'rotateX', 'rotateY', 'rotateZ', 'rotate3d',
      'scale', 'scaleX', 'scaleY', 'scale3d',
      'skew', 'skewX', 'skewY', 'skew3d',
      'perspective', 'matrix', 'matrix3d',
    ];

    [for (l in list) l => true];
  }

  public function new(reporter, callResolver, resolver) {
    this.reporter = reporter;
    this.callResolver = callResolver;
    this.resolver = resolver;
  }

  var resolvedCalls = new Map();

  function call(s, name:StringAt, args)
    return switch name.value {
      case CSS_BUILTINS[_] => true: Success(s);
      case call: 
        var fn = switch resolvedCalls[call] {
          case null: resolvedCalls[call] = callResolver.resolve(call);
          case fn: fn;
        }
        
        switch fn {
          case Some(fn): 
            switch fn(s, args) {
              case Success(v): Success(v);
              case Failure(e): Failure(reporter.makeError('${e.value} for function $call', e.pos));
            }
          case None: Failure(reporter.makeError('unknown method $call', name.pos));
        }
    }

  function reduce(s:SingleValue, resolve:String->Null<SingleValue>):Outcome<SingleValue, Error> {

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
        default: fail('expected numeric value but got ${Printer.singleValue(v)}', v.pos);
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
              case null: 
                switch resolver({ value: name, pos: s.pos }) {
                  case null: fail('unknown identifier $name', s.pos);
                  case v: v;
                }
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
            call(s, name, [for (a in args) reduce(a, resolve).sure()]).sure();
          default: s;
        }))
    catch (e:Dynamic) switch error {
      case Some(e): Failure(e);
      case None: throw e;
    }
  }

  function mediaAnd(c1:FullMediaCondition, c2:FullMediaCondition):FullMediaCondition {
    if (c1.negated != c2.negated)
      fail('cannot nest negated and non-negated queries', c2.pos);//probably should try to translate the query to its negative

    return {
      pos: c2.pos,
      value: And(c1.value, c2.value),
      negated: c2.negated
    }
  }

  function mapMedia(m:MediaCondition, f)
    return switch m {
      case And(a, b): f(And(mapMedia(a, f), mapMedia(b, f)));
      default: f(m);
    }

  static var ANIM_PROPS = [
    for (name in [
      'none',
      'linear', 'ease', 'ease-in', 'ease-out', 'ease-in-out',
      'infinite',
      'normal', 'reverse', 'alternate', 'alternate-reverse',
      'inherit', // not sure this makes sense
      'forwards', 'backwards', 'both',
      'paused', 'running'
    ]) name => true
  ];

  public function normalizeSheet(sheet:Declaration) {
    if (sheet.properties.length > 0)
      fail('no properties allowed on top level', sheet.properties[0].name.pos);

    if (sheet.mediaQueries.length > 0) // TODO: flip order, i.e. move media-queries "into" selectors
      fail('top level media queries not supported', sheet.mediaQueries[0].conditions[0].pos);

    if (sheet.keyframes.length > 0)
      fail('top level keyframes not supported', sheet.keyframes[0].name.pos);

    if (sheet.fonts.length > 0)
      fail('top level fonts not supported', sheet.fonts[0].pos);

    return [
      for (c in sheet.childRules)
        switch c.selector.value {
          case [[
              { tag: name, id: null, classes: [] | null } 
            | { tag: '' | '*' | null, classes: [name], id: null }
            | { classes: [] | null, tag: '' | '*' | null, id: name }
            ]]: 
              var d = c.declaration;
              {
                name: { value: name, pos: c.selector.pos },
                decl: normalizeRule({
                  variables: sheet.variables.concat(d.variables),
                  properties: sheet.properties,
                  keyframes: sheet.keyframes,
                  fonts: sheet.fonts,
                  mediaQueries: sheet.mediaQueries,
                  childRules: sheet.childRules,
                  states: sheet.states,
                }),
              }
          default: 
            fail('only simple selectors allowed here', c.selector.pos);
        }
    ];
  }
  public function normalizeRule(d:Declaration):NormalizedDeclaration {
    //TODO: this will also have to perform variable substitution
    var fonts:Array<FontFace> = [],
        keyframes:Array<Keyframes> = [],
        mediaQueries:Array<MediaQueryOf<PlainDeclaration>> = [];

    function sweep(
        d:Declaration,
        selectors:ListOf<Located<Selector>>,
        queries:ListOf<FullMediaCondition>,
        vars:Map<String, SingleValue>,
        animations:Map<String, String>
      ):PlainDeclaration {

      vars = vars.copy();
      animations = animations.copy();

      var resolve = id -> vars.get(id);

      function reduce(v)
        return this.reduce(v, resolve).sure();

      function getAnimation(name, pos)
        return
          switch animations[name] {
            case null: fail('unknown animation $name', pos);
            case v: { pos: pos, value: VAtom(v) };
          }

      function props(raw:ListOf<Property>):ListOf<Property>
        return [for (p in raw) {
          name: p.name,
          value: {
            var c = p.value;
            {
              importance: c.importance,
              components:
                if (p.name.value == 'animation-name') switch c.components {
                  case [[{ pos: pos, value: VAtom(name) }]] if (name != 'none'):
                    [[getAnimation(name, pos)]];
                  case [[_]]: c.components;
                  default: fail('animation-name must have exactly one value', p.name.pos);
                }
                else {
                  var reduce =
                    if (p.name.value == 'animation')
                      s -> switch reduce(s) {
                        case v = { value: VAtom(name) } if (!ANIM_PROPS.exists(name)):
                          getAnimation(name, v.pos);
                        case v: v;
                      }
                    else reduce;
                  [for (values in c.components) [for (v in values) reduce(v)]];
                }
            }
          }
        }];

      for (v in d.variables)
        switch v.value.components {//TODO: probably also forbid !important
          case [[s]]: vars.set(v.name.value, reduce(s));
          default: fail('variables must be initialized with a single value', v.name.pos);
        }

      function animation(a:AnimationName):AnimationName
        return
          if (a.quoted) a;
          else {
            quoted: false,
            pos: a.pos,
            value: animations[a.value] = a.value + Std.random(1 << 20) // TODO: make customizable
          }

      for (k in d.keyframes)
        keyframes.push({
          name: animation(k.name),
          frames: [for (f in k.frames) {
            pos: f.pos,
            properties: props(f.properties)
          }]
        });

      for (f in d.fonts)
        fonts.push({
          pos: f.pos,
          value: props(f.value)
        });

      for (q in d.mediaQueries) {

        var resolved:ListOf<FullMediaCondition> = [for (c in q.conditions) {
          negated: c.negated,
          pos: c.pos,
          value: mapMedia(c.value, m -> switch m {
            case Feature(n, v): Feature(n, reduce(v));
            default: m;
          })
        }];

        var queries = switch queries {
          case []: resolved;
          default: [for (outer in queries) for (inner in resolved) mediaAnd(outer, inner)];
        }

        mediaQueries.push({
          conditions: queries,
          declaration: sweep(q.declaration, selectors, queries, vars, animations)
        });
      }

      return {
        properties: props(d.properties),
        childRules: [for (c in d.childRules) {
          selector: c.selector,
          declaration: sweep(c.declaration, selectors.concat([c.selector]), queries, vars, animations)
        }]
      }
    }

    var ret = sweep(d, [], [], new Map(), new Map());

    return {
      fonts: fonts,
      keyframes: keyframes,
      mediaQueries: mediaQueries,
      properties: ret.properties,
      childRules: ret.childRules,
    }
  }
}