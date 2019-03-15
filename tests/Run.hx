package ;

import cix.css.Parser;

class Run {
	#if !macro
  static function main() {
		parse('
			background: green;
			div {
				margin: 5px;
				$foo: 3px;
				& {

				}
			}
		');
	}	
	#end
	macro static function parse(e:haxe.macro.Expr) {
		switch e.expr {
			case EConst(CString(s)):
				var pos = haxe.macro.Context.getPosInfos(e.pos);
				var p = new cix.css.Parser(s, tink.parse.Reporter.expr(pos.file), pos.min + 1);
				trace(@:privateAccess p.parseDeclaration());
			default: throw 'assert';
		}
		return macro null;
	}
}