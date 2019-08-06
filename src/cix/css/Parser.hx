package cix.css;

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

  static var binOps = {
    var groups = [
      ['+' => OpAdd]
    ];

    [for (prio in 0...groups.length) for (tk => op in groups[prio]) tk => { prio: prio, op: op }];
  }

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

  function parseSingleValue(?interpolated):SingleValue
    return located(
      function () return
        if (allow("${"))
          if (interpolated) die('recursive interpolation not allowed');
          else parseComplex().value + expect('}');
        else if (allowHere('$'))
          if (interpolated) die('recursive interpolation not allowed');
          else VVar(ident(true).sure());
        else if (is(QUOTE)) VString(parseString());
        else if (allowHere('-'))
          tryParseNumber(-1, die.bind('number expected'));
        else tryParseNumber(1, function () {
          var val = ident(true).sure();
          return
            if (allowHere('('))
              VCall(strAt(val), parseList(parseSingleValue.bind(), { sep: ',', end: ')' }));
            else
              if (interpolated) VVar(val);
              else VAtom(val);
        })
    );

  function parseComplex():SingleValue
    return
      if (allow('(')) die('parens not supported yet');
      else parseExprNext(parseSingleValue(true));

  function parseExprNext(initial:SingleValue):SingleValue {
    for (op in BinOp.all)
      if (allow(op))
        return { pos: initial.pos, value: VBinOp(op, initial, parseComplex()) };
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

            expect(';');
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

  function parseProperty():Property
    return {
      name: strAt(ident().sure()) + expect(':'),
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

  function namedVal()
    return {
      name: strAt(ident().sure()) + expect(':'),
      value: parseValue()
    };

  function parseDeclaration():Declaration {
    var properties = [],
        childRules = [],
        variables = [],
        keyframes = [],
        fonts = [],
        mediaQueries = [];

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
              fonts.push(parseProperties());
            case 'keyframes':
              keyframes.push(parseKeyFrames());
            case 'state':
              die('no support for states yet');
            case unknown: reject(unknown, 'unknown at-rule $unknown');
          }
          true;
        }
        else if (allowHere('$')) {
          variables.push(namedVal());
          false;
        }
        else
          switch attempt(located.bind(parseFullSelector).catchExceptions.bind()) {
            case Success(s):
              if (error != null)
                throw error;
              childRules.push({
                selector: s,
                declaration: expect('{') + parseDeclaration() + expect('}'),
              });
              true;
            default:
              properties.push(parseProperty());
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

    return {
      mediaQueries: mediaQueries,
      fonts: fonts,
      variables: variables,
      properties: properties,
      childRules: childRules,
      keyframes: keyframes,
    }
  }

  var error:Error;

  override function unknownPseudo(name:StringSlice) {
    if (error == null)
      error = makeError('Unknown pseudo selector $name', makePos(name.start, name.end));
    return Vendored('invalid');
  }

  static public function parseDecl(e:Expr):Outcome<Declaration, Error>
    return switch e.expr {
      case EConst(CString(s)):
        var pos:Position = e.pos;
        var p = new Parser(s, tink.parse.Reporter.expr(pos.file), pos.min + 1);
        try Success(p.parseDeclaration())
        catch (e:Error) Failure(e)
        catch (e:Dynamic) Failure(new Error(Std.string(e), pos));
      default:
        Failure(new Error('string constant expected', e.pos));
    }

}