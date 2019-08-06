package cix;

#if macro
import haxe.macro.Type;
import haxe.macro.Context.*;

import cix.css.*;
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
    var rule = Parser.parseDecl(e).sure(),
        t = localType(),
        reporter = tink.parse.Reporter.expr(getPosInfos(e.pos).file);

    return 
      new Generator(Generator.resultExpr.bind(t))
      .rule(
        InlineRule(e.pos, t, getLocalMethod()), 
        new Normalizer(
          reporter,
          (name, reporter) -> (_, _) -> Failure(reporter.makeError('unknown method ${name.value}', name.pos))
        ).normalize(rule)
      );
  }

  // macro static public function sheet(e) {
  //   var rule = cix.css.Parser.parseDecl(e).sure(),
  //       t = localType();

  //   var gen = new Generator(
  //     tink.parse.Reporter.expr(getPosInfos(e.pos).file),
  //     (name, reporter) -> (_, _) -> Failure(reporter.makeError('unknown method ${name.value}', name.pos)),
  //     Generator.resultExpr.bind(t)
  //   );

  //   return gen.rule(InlineRule(e.pos, t, getLocalMethod()), rule);
  // }  
}