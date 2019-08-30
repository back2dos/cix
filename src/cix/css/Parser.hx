package cix.css;

import tink.color.Color;
import tink.parse.Char.*;
import tink.parse.StringSlice;
import tink.csss.Selector;
import cix.css.Ast;
using tink.CoreApi;
import haxe.macro.Expr;
import tink.parse.Position;

class Parser extends SelectorParser {

  static final NOBREAK = !LINEBREAK;
  static final BR_CLOSE = Char('}');
  static final QUOTE = Char('"\'');

  override function doSkipIgnored() {
    super.doSkipIgnored();

    if (allowHere('/*'))
      upto('*/');
    else if (allowHere('//'))
      doReadWhile(NOBREAK);
  }

  function parseUnit()
    return 
      if (allowHere('%')) Pct;
      else switch ident(true) {
        case Success(n):// this is not very safe
          cast n.toString();
        default: null;
      }

  function parseNumber(num, sign) {
    if (allowHere('.'))
      num += Std.parseFloat('0.' + parseInt(true).sure());
    return VNumeric(num * sign, parseUnit());
  }

  function tryParseNumber(sign, fallback)
    return
      if (is(DIGIT))
        parseNumber(parseInt(true).sure(), sign);
      else if (is('.'.code))
        parseNumber(0, sign);
      else
        fallback();

  static final HEX = DIGIT || 'abcdefABCDEF';
  
  function parseColor() {
    var slice = readWhile(HEX);

    var s = slice.toString();
    switch s.length {
      case 3: 
        s = [for (i in 0...s.length) s.charAt(i) + s.charAt(i)].join('');
      case 6:
      default: reject(slice, 'hex literal must have 3 or 6 digits');
    }
    var i = Std.parseInt('0x$s');
    return VColor(Color.rgb(i >> 16, i >> 8, i));
  }

  function parseSingleValue(?interpolated):SingleValue
    return located(
      function () return
        if (allow("${"))
          if (interpolated) die('recursive interpolation not allowed');
          else parseComplex(true).value + expect('}');
        else if (allowHere('('))
          parseComplex(interpolated).value + expect(')');
        else if (allowHere('$'))
          if (interpolated) die('recursive interpolation not allowed');
          else VVar(ident(true).sure());
        else if (allowHere('#')) parseColor();
        else if (is(QUOTE)) VString(parseString());
        else if (allowHere('-'))
          tryParseNumber(-1, () -> switch ident(true) {
            case Success(v): VAtom('-' + v.toString());
            default: die('expected identifier or number');
          });
        else tryParseNumber(1, function () {
          var val = ident(true).sure();
          return
            if (allowHere('('))
              VCall(strAt(val), parseList(parseSingleValue.bind(), { sep: ',', end: ')' }));
            else
              if (interpolated) VVar(val);//TODO: implement https://github.com/back2dos/cix/issues/4 here
              else switch COLOR_CONSTANTS[val] {
                case null: VAtom(val);
                case c: VColor(c);
              }
        })
    );

  function parseComplex(interpolated):SingleValue
    return
      parseExprNext(parseSingleValue(interpolated), interpolated);

  function parseExprNext(initial:SingleValue, interpolated):SingleValue {
    for (op in BinOp.all)
      if (allow(op))
        return { pos: initial.pos, value: VBinOp(op, initial, parseComplex(interpolated)) };
    return initial;
  }

  function strAt(s:StringSlice):StringAt
    return { pos: makePos(s.start, s.end), value: s };

  function parseValue():CompoundValue {
    var cur = [];
    var components = [cur],
        importance = 0;

    function isDone()
      return upNext(Char(';}')) || pos >= max;

    while (true) {

      if (isDone())
        switch cur {
          case []: die('empty value');
          default: break;
        }

      if (allow('!'))
        switch cur {
          case []: die('empty value');
          default:
            importance++;
            expect('important');
            while (allow('!'))
              importance++ + expect('important');

            break;
        }


      if (allow(','))
        switch cur {
          case []: die('empty value');
          default:
            components.push(cur = []);
        }

      cur.push(parseSingleValue());
    }

    return {
      components: components,
      importance: importance,
    };
  }

  static var PROP_START = tink.csss.Parser.IDENT_START || '-';

  function propName()
    return 
      if (is(PROP_START)) 
        switch strAt(readWhile(tink.csss.Parser.IDENT_CONTD)) {
          case { value : '-'}: die('- is not a valid property name');
          case v: v;
        }
      else die('property name expected');

  function parseProperty():Property
    return {
      name: propName() + expect(':'),
      value: parseValue(),
    };

  function parseProperties():ListOf<Property>
    return
      parseList(
        parseProperty,
        { start: '{', end: '}', sep: ';' }
      );

  function getMediaType(?s:StringSlice):MediaCondition
    return 
      if (s == null) getMediaType(ident().sure());
      else Type(switch s.toString() {
        case v = All | Print | Screen | Speech: cast v;
        default: reject(s, 'invalid media type');
      });

  function getMediaFeature():MediaCondition
    return Feature(strAt(ident().sure()) + expect(':'), parseSingleValue()) + expect(')');

  function parseMediaQuery():MediaQuery {

    function parseNext(c:MediaCondition)
      return
        switch ident() {
          case Success(_.toString() => 'and'):
            parseNext(And(c, if (allow('(')) getMediaFeature() else getMediaType()));
          default: c;
        }

    function make(negated, condition) {
      var cond = located(() -> parseNext(condition()));
      return { 
        negated: negated, 
        value: cond.value,
        pos: cond.pos
      };
    }
      

    return {
      conditions: parseList(
        () -> switch ident() {
          case Success(_.toString() => 'not'): 
            make(true, getMediaType.bind());
          case Success(id): 
            make(false, getMediaType.bind(id));
          default: 
            make(false, () -> expect('(') + getMediaFeature());
        }, 
        { end: '{', sep: ',', trailing: Never }
      ),
      declaration: parseDeclaration() + expect('}')
    }
  }

  function parseKeyFrames():Keyframes
    return {
      name: {
        function quoted(isQuoted, s):AnimationName
          return {
            value: s.value,
            pos: s.pos,
            quoted: isQuoted
          }
        if (upNext(QUOTE)) quoted(true, located(parseString))
        else quoted(false, strAt(ident(true).sure()));
      },
      frames:
        parseList(
          () -> {
            pos: switch ident() {
              case Success(_.toString() => v = 'from' | 'to' ):
                if (v == 'from') 100;
                else 0;
              case Success(id): reject(id, 'only `from`, `to` or percentage allowed');
              default:
                parseInt().sure() + expect('%');
            },
            properties: expect(':') + parseProperties()
          },
          { start: '{', end: '}' }
        )
  }

  function parseDeclaration():Declaration {
    var properties = [],
        childRules = [],
        variables = [],
        keyframes = [],
        fonts = [],
        mediaQueries = [],
        states = [];

    var ret:Declaration = {
      mediaQueries: mediaQueries,
      fonts: fonts,
      variables: variables,
      properties: properties,
      childRules: childRules,
      keyframes: keyframes,
      states: states,
    }

    function parsePart()
      return
        if (allowHere('@')) {
          var kw = ident(true).sure();
          switch kw.toString() {
            case known = 'charset' | 'import' | 'namespace' | 'supports' | 'document' | 'page' | 'viewport' | 'counter-style' | 'font-feature-values':
              die('no support for $known yet');
            case 'media':
              mediaQueries.push(parseMediaQuery());
            case 'font-face':
              fonts.push({ pos: makePos(kw.start, kw.end), value: parseProperties() });
            case 'keyframes':
              keyframes.push(parseKeyFrames());
            case 'state':
              
              expect('(');
              
              function add(name, cond)
                states.push({
                  name: name,
                  cond: cond,
                  declaration: expect(')') + expect('{') + parseDeclaration() + expect('}'),
                });

              function name()
                return strAt(ident().sure());

              if (allow('!'))
                add(name(), IsNotSet);
              else
                add(name(), if (allow('=')) Eq(name()) else IsSet);
            case unknown: reject(unknown, 'unknown at-rule $unknown');
          }
          true;
        }
        else if (allowHere('$')) {
          variables.push({
            name: strAt(ident(true).sure()) + expect(':'),
            value: parseValue()
          });
          false;
        }
        else
          switch attempt(() -> tink.core.Error.catchExceptions(() -> propName() + expect(':'))) {
            case Failure(e):
              childRules.push({
                selector: located(parseFullSelector),
                declaration: expect('{') + parseDeclaration() + expect('}'),
              });
              true;
            case Success(name):
              properties.push({
                name: name,
                value: parseValue(),
              });
              false;
          }

    function isDone()
      return upNext(BR_CLOSE) || pos >= max;

    while (true) {
      if (isDone()) break;
      var isBlock = parsePart();
      if (!isBlock) {
        var semi = allow(';');
        if (isDone()) break;
        else if (!semi) die('expected ; or }');
      }
    }

    return ret;
  }

  #if macro
  static function withParser<T>(e:Expr, f:Parser->T):Outcome<T, Error>
    return switch e.expr {
      case EConst(CString(s)):
        var pos:Position = e.pos;
        var p = new Parser(s, tink.parse.Reporter.expr(pos.file), pos.min + 1);
        try Success(f(p))
        catch (e:Error) Failure(e)
        catch (e:Dynamic) Failure(new Error(Std.string(e), pos));
      default:
        Failure(new Error('string constant expected', e.pos));
    }

  static public function parseDecl(e:Expr):Outcome<Declaration, Error>
    return withParser(e, p -> p.parseDeclaration());

  static public function parseVal(e:Expr):Outcome<CompoundValue, Error>
    return withParser(e, p -> p.parseValue());
  #end

  static final COLOR_CONSTANTS:haxe.DynamicAccess<Color> = @:privateAccess {
    /*
      TODO: this should probably be elsewhere
      Generated from https://drafts.csswg.org/css-color/ using 
      
      ```js
      Array.prototype.map.call(document.querySelectorAll('table.named-color-table tbody tr th'), c => ({ name: c.textContent.trim(), value: c.nextElementSibling.textContent.trim() }))
      ````
     */
    aliceblue: new Color(0xfff0f8ff),
    antiquewhite: new Color(0xfffaebd7),
    aqua: new Color(0xff00ffff),
    aquamarine: new Color(0xff7fffd4),
    azure: new Color(0xfff0ffff),
    beige: new Color(0xfff5f5dc),
    bisque: new Color(0xffffe4c4),
    black: new Color(0xff000000),
    blanchedalmond: new Color(0xffffebcd),
    blue: new Color(0xff0000ff),
    blueviolet: new Color(0xff8a2be2),
    brown: new Color(0xffa52a2a),
    burlywood: new Color(0xffdeb887),
    cadetblue: new Color(0xff5f9ea0),
    chartreuse: new Color(0xff7fff00),
    chocolate: new Color(0xffd2691e),
    coral: new Color(0xffff7f50),
    cornflowerblue: new Color(0xff6495ed),
    cornsilk: new Color(0xfffff8dc),
    crimson: new Color(0xffdc143c),
    cyan: new Color(0xff00ffff),
    darkblue: new Color(0xff00008b),
    darkcyan: new Color(0xff008b8b),
    darkgoldenrod: new Color(0xffb8860b),
    darkgray: new Color(0xffa9a9a9),
    darkgreen: new Color(0xff006400),
    darkgrey: new Color(0xffa9a9a9),
    darkkhaki: new Color(0xffbdb76b),
    darkmagenta: new Color(0xff8b008b),
    darkolivegreen: new Color(0xff556b2f),
    darkorange: new Color(0xffff8c00),
    darkorchid: new Color(0xff9932cc),
    darkred: new Color(0xff8b0000),
    darksalmon: new Color(0xffe9967a),
    darkseagreen: new Color(0xff8fbc8f),
    darkslateblue: new Color(0xff483d8b),
    darkslategray: new Color(0xff2f4f4f),
    darkslategrey: new Color(0xff2f4f4f),
    darkturquoise: new Color(0xff00ced1),
    darkviolet: new Color(0xff9400d3),
    deeppink: new Color(0xffff1493),
    deepskyblue: new Color(0xff00bfff),
    dimgray: new Color(0xff696969),
    dimgrey: new Color(0xff696969),
    dodgerblue: new Color(0xff1e90ff),
    firebrick: new Color(0xffb22222),
    floralwhite: new Color(0xfffffaf0),
    forestgreen: new Color(0xff228b22),
    fuchsia: new Color(0xffff00ff),
    gainsboro: new Color(0xffdcdcdc),
    ghostwhite: new Color(0xfff8f8ff),
    gold: new Color(0xffffd700),
    goldenrod: new Color(0xffdaa520),
    gray: new Color(0xff808080),
    green: new Color(0xff008000),
    greenyellow: new Color(0xffadff2f),
    grey: new Color(0xff808080),
    honeydew: new Color(0xfff0fff0),
    hotpink: new Color(0xffff69b4),
    indianred: new Color(0xffcd5c5c),
    indigo: new Color(0xff4b0082),
    ivory: new Color(0xfffffff0),
    khaki: new Color(0xfff0e68c),
    lavender: new Color(0xffe6e6fa),
    lavenderblush: new Color(0xfffff0f5),
    lawngreen: new Color(0xff7cfc00),
    lemonchiffon: new Color(0xfffffacd),
    lightblue: new Color(0xffadd8e6),
    lightcoral: new Color(0xfff08080),
    lightcyan: new Color(0xffe0ffff),
    lightgoldenrodyellow: new Color(0xfffafad2),
    lightgray: new Color(0xffd3d3d3),
    lightgreen: new Color(0xff90ee90),
    lightgrey: new Color(0xffd3d3d3),
    lightpink: new Color(0xffffb6c1),
    lightsalmon: new Color(0xffffa07a),
    lightseagreen: new Color(0xff20b2aa),
    lightskyblue: new Color(0xff87cefa),
    lightslategray: new Color(0xff778899),
    lightslategrey: new Color(0xff778899),
    lightsteelblue: new Color(0xffb0c4de),
    lightyellow: new Color(0xffffffe0),
    lime: new Color(0xff00ff00),
    limegreen: new Color(0xff32cd32),
    linen: new Color(0xfffaf0e6),
    magenta: new Color(0xffff00ff),
    maroon: new Color(0xff800000),
    mediumaquamarine: new Color(0xff66cdaa),
    mediumblue: new Color(0xff0000cd),
    mediumorchid: new Color(0xffba55d3),
    mediumpurple: new Color(0xff9370db),
    mediumseagreen: new Color(0xff3cb371),
    mediumslateblue: new Color(0xff7b68ee),
    mediumspringgreen: new Color(0xff00fa9a),
    mediumturquoise: new Color(0xff48d1cc),
    mediumvioletred: new Color(0xffc71585),
    midnightblue: new Color(0xff191970),
    mintcream: new Color(0xfff5fffa),
    mistyrose: new Color(0xffffe4e1),
    moccasin: new Color(0xffffe4b5),
    navajowhite: new Color(0xffffdead),
    navy: new Color(0xff000080),
    oldlace: new Color(0xfffdf5e6),
    olive: new Color(0xff808000),
    olivedrab: new Color(0xff6b8e23),
    orange: new Color(0xffffa500),
    orangered: new Color(0xffff4500),
    orchid: new Color(0xffda70d6),
    palegoldenrod: new Color(0xffeee8aa),
    palegreen: new Color(0xff98fb98),
    paleturquoise: new Color(0xffafeeee),
    palevioletred: new Color(0xffdb7093),
    papayawhip: new Color(0xffffefd5),
    peachpuff: new Color(0xffffdab9),
    peru: new Color(0xffcd853f),
    pink: new Color(0xffffc0cb),
    plum: new Color(0xffdda0dd),
    powderblue: new Color(0xffb0e0e6),
    purple: new Color(0xff800080),
    rebeccapurple: new Color(0xff663399),
    red: new Color(0xffff0000),
    rosybrown: new Color(0xffbc8f8f),
    royalblue: new Color(0xff4169e1),
    saddlebrown: new Color(0xff8b4513),
    salmon: new Color(0xfffa8072),
    sandybrown: new Color(0xfff4a460),
    seagreen: new Color(0xff2e8b57),
    seashell: new Color(0xfffff5ee),
    sienna: new Color(0xffa0522d),
    silver: new Color(0xffc0c0c0),
    skyblue: new Color(0xff87ceeb),
    slateblue: new Color(0xff6a5acd),
    slategray: new Color(0xff708090),
    slategrey: new Color(0xff708090),
    snow: new Color(0xfffffafa),
    springgreen: new Color(0xff00ff7f),
    steelblue: new Color(0xff4682b4),
    tan: new Color(0xffd2b48c),
    teal: new Color(0xff008080),
    thistle: new Color(0xffd8bfd8),
    tomato: new Color(0xffff6347),
    turquoise: new Color(0xff40e0d0),
    violet: new Color(0xffee82ee),
    wheat: new Color(0xfff5deb3),
    white: new Color(0xffffffff),
    whitesmoke: new Color(0xfff5f5f5),
    yellow: new Color(0xffffff00),
    yellowgreen: new Color(0xff9acd32),
    transparent: new Color(0),
  }
}