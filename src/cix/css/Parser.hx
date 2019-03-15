package cix.css;

import tink.parse.Char.*;
import tink.parse.StringSlice;
import tink.csss.Selector;
using tink.CoreApi;

class Parser<P, E> extends tink.csss.Parser<P, E> {

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

  function parseValue()
    return upto(';').sure().toString();

  function parseDeclaration():Declaration {
    var properties = [],
        childRules = [],
        variables = [];

    function parseParts() 
      if (allowHere('@')) 
        die('no support for at rules yet');
      else if (allowHere('$')) 
        variables.push(new NamedWith(ident().sure(), parseValue()));    
      else switch attempt(parseFullSelector.catchExceptions.bind()) {
        case Success(selector):
          if (error != null)
            throw error;
          childRules.push({
            selector: selector,
            declaration: expect('{') + parseDeclaration() + expect('}'),
          });    
        default: 
          
          properties.push(new NamedWith(ident().sure(), parseValue()));    
      }

    while (!upNext(BR_CLOSE) && pos < max) 
      parseParts();
    
    return {
      variables: variables,
      properties: properties,
      childRules: childRules,
    }
  }

  var error:E;

  override function unknownPseudo(name:StringSlice) {
    if (error == null)
      error = makeError('Unknown pseudo selector $name', makePos(name.start, name.end));
    return Vendored('invalid');
  }

}

typedef Declaration = {
  var properties(default, null):ListOf<NamedWith<StringSlice, String>>;
  var variables(default, null):ListOf<NamedWith<StringSlice, String>>;
  var childRules(default, null):ListOf<{
    var selector(default, null):Selector;
    var declaration(default, null):Declaration;
  }>;
}
