package cix.css;

#if macro
using tink.MacroApi;
class Macros {
  static function buildImport() {
    return tink.macro.BuildCache.getType('cix.Styles', null, null, function (ctx) {
      var name = ctx.name;

      var ret = macro class $name {};

      var decl = 
        switch ctx.type {
          case TInst(_.get().kind => KExpr(e), _):
            Parser.parseExpr(e).sure();
          default:
            throw 'assert';
        }

      for (v in decl.properties)
        v.name.pos.error('cannot have properties at top level');

      // for (v in decl.variables) {
        
      // }

      return ret;
    });
  }
}
#end