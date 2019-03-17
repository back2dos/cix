package ;

import cix.css.Parser;

#if !macro
typedef Styles = cix.Styles<'
	$size: 3px;
	& {
		background: green;
		border: 1px solid red;
		font: $size "Courier New";
		transform: translate(5px, 10px);
	}
	div {
		margin-top: -5px;
		transition: all .25s;
		&:hover {

		}
	}
'>;
#end

class Run {
	#if !macro
  static function main() {
		// parse('

		// ');
	}	
	#end
	// macro static function parse(e:haxe.macro.Expr) {
	// 	switch e.expr {
	// 		case EConst(CString(s)):
	// 			var p = new cix.css.Parser(s, e.pos);
	// 			trace(@:privateAccess p.parseDeclaration());
	// 		default: throw 'assert';
	// 	}
	// 	return macro null;
	// }
}