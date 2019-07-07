package cix.css;

#if macro
import cix.css.Generator;
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

      for (v in decl.childRules)
        switch v.selector {
          case _[0][0] => { id: null, attrs: { length: 0 }, classes: { length: 0 }, pseudos: { length: 0 }, tag: tag } if (tag != null && tag != '&'):
            ret.fields.push({
              access: [AStatic, APublic],
              pos: v.pos,
              name: tag,
              kind: FVar(macro : String),
            });
          default:
            v.pos.error('plain identifier expected');
        }

      return ret;
    });
  }
}
#end