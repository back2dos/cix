package cix.css;

import tink.parse.Char.*;
import tink.parse.StringSlice;
import tink.csss.Selector;
import cix.css.Ast;
using tink.CoreApi;
import haxe.macro.Expr;
import tink.parse.Position;

class Parser extends tink.csss.Parser<Position, Error> {

  static var NOBREAK = !LINEBREAK;
  static var BR_CLOSE = Char('}'.code);
  static var AMP = Char('&'.code);
  
  override function doSkipIgnored() {
    super.doSkipIgnored();
    
    if (allowHere('/*'))
      upto('*/');
    else if (allowHere('//')) 
      doReadWhile(NOBREAK);
  }

  override function shouldContinue()
    return super.shouldContinue() || is(AMP);

  override function parseSelectorPart() 
    return
      if (allow('&')) parseSelectorNext('&');
      else super.parseSelectorPart();

  function parseProperty() 
    return ident(true).flatMap(function (s) 
      return 
        if (allow(':')) Success(s);
        else Failure(makeError('expected `:`', makePos(this.pos)))
    );

  function parseNumber(num, sign) {
    if (allowHere('.'))
      num += Std.parseFloat('0.' + parseInt(true).sure());
    return VNumeric(num * sign, switch ident(true) {
      case Success(n):
        cast n.toString();
      default: null;
    });    
  }

  function tryParseNumber(sign, fallback) 
    return 
      if (is(DIGIT)) 
        parseNumber(parseInt(true).sure(), sign);
      else if (is('.'.code)) 
        parseNumber(0, sign);
      else
        fallback();

  function parseSingleValue():Located<ValueKind>
    return located(
      function () return 
        if (allow("${")) 
          die('complex interpolation not supported yet');
        else if (allowHere('$')) VExpr(XVar(ident(true).sure()));
        else if (is('"\'')) VString(parseString());
        else if (allowHere('-')) 
          tryParseNumber(-1, die.bind('number expected'));
        else tryParseNumber(1, function () {
          var val = ident(true).sure();
          return 
            if (allowHere('('))
              VCall(strAt(val), parseList(parseSingleValue, { sep: ',', end: ')' }));
            else VIdent(val);
        })
    );

  function strAt(s:StringSlice):StringAt
    return { pos: makePos(s.start, s.end), value: s };

  function parseValue():CompoundValue {
    var cur = [];
    var ret = [cur];
    while (true) {

      if (allow(';')) 
        switch cur {
          case []: die('empty value');
          default: break;
        }

      if (allow(',')) 
        switch cur {
          case []: die('empty value');
          default:
            ret.push(cur = []);
        }

      cur.push(parseSingleValue());
    }

    return ret;
  }

  function namedVal()
    return new NamedWith(strAt(ident().sure()) + expect(':'), parseValue());

  function parseDeclaration():Declaration {
    var properties = [],
        childRules = [],
        variables = [];

    function parseParts() 
      if (allowHere('@')) 
        die('no support for at rules yet');
      else if (allowHere('$')) 
        variables.push(namedVal());    
      else switch attempt(parseFullSelector.catchExceptions.bind()) {
        case Success(selector):
          if (error != null)
            throw error;
          childRules.push({
            selector: selector,
            declaration: expect('{') + parseDeclaration() + expect('}'),
          });    
        default: 
          properties.push(namedVal());    
      }

    while (!upNext(BR_CLOSE) && pos < max) 
      parseParts();
    
    return {
      variables: variables,
      properties: properties,
      childRules: childRules,
    }
  }

  var error:Error;

  override function unknownPseudo(name:StringSlice) {
    if (error == null)
      error = makeError('Unknown pseudo selector $name', makePos(name.start, name.end));
    return Vendored('invalid');
  }

  static public function parseExpr(e:Expr):Outcome<Declaration, Error>
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