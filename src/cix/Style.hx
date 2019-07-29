package cix;

#if macro
import haxe.macro.Type;
import haxe.macro.Context.*;

import cix.css.Generator;
using tink.CoreApi;
#end

class Style {
  #if macro 
  static function localType():BaseType
    return switch follow(getLocalType()) {
      case TInst(_.get() => t, _): t;
      case TAbstract(_.get() => t, _): t;
      default: throw 'assert';
    }
  #end
  macro static public function rule(e) {
    var rule = cix.css.Parser.parseDecl(e).sure(),
        t = localType();

    var gen = new Generator(
      tink.parse.Reporter.expr(getPosInfos(e.pos).file),
      (name, reporter) -> (_, _) -> Failure(reporter.makeError('unknown method ${name.value}', name.pos)),
      Generator.resultExpr.bind(t)
    );

    return gen.rule(InlineRule(e.pos, t, getLocalMethod()), rule);
  }

  macro static public function sheet(e) {
    var rule = cix.css.Parser.parseDecl(e).sure(),
        t = localType();

    var gen = new Generator(
      tink.parse.Reporter.expr(getPosInfos(e.pos).file),
      (name, reporter) -> (_, _) -> Failure(reporter.makeError('unknown method ${name.value}', name.pos)),
      Generator.resultExpr.bind(t)
    );

    return gen.rule(InlineRule(e.pos, t, getLocalMethod()), rule);
  }  
}