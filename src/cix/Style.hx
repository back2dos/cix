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

  static public var printer = new Printer();

  static function exec(e, process) {
    var rule = Parser.parseDecl(e).sure(),
        reporter = tink.parse.Reporter.expr(getPosInfos(e.pos).file);

    return process( 
      new Normalizer(
        reporter,
        (name, reporter) -> (_, _) -> Failure(reporter.makeError('unknown method ${name.value}', name.pos))
      ).normalize(rule)
    );
  }
  #end
  macro static public function rule(e) 
    return exec(e, decl -> Generator.rule(localType(), e.pos, decl, getLocalMethod(), printer));

  // macro static public function sheet(e) 
  //   return exec(e, (t, decl) -> Generator.sheet(localType(), e.pos, decl, getLocalMethod(), printer));
}