package cix.css;

import tink.parse.Char.*;
import tink.parse.StringSlice;
import tink.csss.Selector;
import cix.css.Ast;
using tink.CoreApi;
import haxe.macro.Expr;

class Parser extends tink.csss.Parser<Position, Error> {

  static var NOBREAK = !LINEBREAK;
  static var BR_CLOSE = Char('}'.code);
  static var AMP = Char('&'.code);

  public function new(source:String, pos:Position) {
    #if macro
      var pos = haxe.macro.Context.getPosInfos(pos);
    #end
    super(source, tink.parse.Reporter.expr(pos.file), pos.min);
  }
  
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

  function parseSingleValue():Located<ValueKind>
    return located(
      function () return 
        if (allow("${")) {
          throw 'not implemented';
        }
        else if (is(DIGIT)) {
          var num:Float = parseInt(true).sure();
          if (allowHere('.'))
            num += Std.parseFloat('0.' + parseInt(true).sure());
          Numeric(num, switch ident(true) {
            case Success(n):
              cast n.toString();
            default: null;
          });
        }
        else if (is('.'.code)) {
          throw 'float';
        }
        else {
          var val = ident(true).sure();
          Ident(val);
        }
    );

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

  function parseDeclaration():Declaration {
    var properties = [],
        childRules = [],
        variables = [];

    function parseParts() 
      if (allowHere('@')) 
        die('no support for at rules yet');
      else if (allowHere('$')) 
        variables.push(new NamedWith(ident().sure() + expect(':'), parseValue()));    
      else switch attempt(parseFullSelector.catchExceptions.bind()) {
        case Success(selector):
          if (error != null)
            throw error;
          childRules.push({
            selector: selector,
            declaration: expect('{') + parseDeclaration() + expect('}'),
          });    
        default: 
          
          properties.push(new NamedWith(ident().sure() + expect(':'), parseValue()));    
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

}

typedef Declaration = {
  var properties(default, null):ListOf<NamedWith<StringSlice, CompoundValue>>;
  var variables(default, null):ListOf<NamedWith<StringSlice, CompoundValue>>;
  var childRules(default, null):ListOf<{
    var selector(default, null):Selector;
    var declaration(default, null):Declaration;
  }>;
}
