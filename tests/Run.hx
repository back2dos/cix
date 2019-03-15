package ;

import cix.css.Parser;

class Run {
	#if !macro
  static function main() {
		parse('
			background: green;
			border: 1px solid red;
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
				var p = new cix.css.Parser(s, e.pos);
				trace(@:privateAccess p.parseDeclaration());
			default: throw 'assert';
		}
		return macro null;
	}
}