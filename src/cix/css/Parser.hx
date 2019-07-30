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
  static final BR_CLOSE = Char('}'.code);

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

  function parseProperty() 
    return ident(true).flatMap(function (s) 
      return 
        if (allow(':')) Success(s);
        else Failure(makeError('expected `:`', makePos(this.pos)))
    );

  function parseUnit() 
    return switch ident(true) {
      case Success(n):
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
        else if (is('"\'')) VString(parseString());
        else if (allowHere('-')) 
          tryParseNumber(-1, die.bind('number expected'));
        else tryParseNumber(1, function () {
          var val = ident(true).sure();
          return 
            if (allowHere('('))
              VCall(strAt(val), parseList(parseSingleValue.bind(), { sep: ',', end: ')' }));
            else 
              if (interpolated) VVar(val);
              else VString(val);
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
        die('no support for @ rules yet');
      else if (allowHere('$')) {
        var v = namedVal();
        variables.push({ name: v.name, value: v.value });    
      }
      else 
        switch attempt(located.bind(parseFullSelector).catchExceptions.bind()) {
          case Success({ value: selector, pos: pos }):
            if (error != null)
              throw error;
            childRules.push({
              selector: selector,
              pos: pos,
              declaration: expect('{') + parseDeclaration() + expect('}'),
            });    
          default: 
            var v = namedVal();
            properties.push({ name: v.name, value: v.value, isImportant: false });    
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