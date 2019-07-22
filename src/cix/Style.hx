package cix;

#if macro
import haxe.macro.Type;
import haxe.macro.Context.*;

import cix.css.Generator;
using tink.CoreApi;
#end

class Style {
  macro static public function rule(e) {
    var rule = cix.css.Parser.parseDecl(e).sure();
    
    var gen = new Generator(
      tink.parse.Reporter.expr(getPosInfos(e.pos).file),
      (name, reporter) -> (_, _) -> Failure(reporter.makeError('unknown method ${name.value}', name.pos)),
      Generator.resultExpr
    );

    var localType:BaseType = switch follow(getLocalType()) {
      case TInst(_.get() => t, _): t;
      case TAbstract(_.get() => t, _): t;
      default: throw 'assert';
    }

    return gen.rule(InlineRule(e.pos, localType, getLocalMethod()), rule);
  }
}