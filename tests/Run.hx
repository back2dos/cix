package ;

import A;

class Run {
  static function main() {
		cix.Style.rule('
			$margin: 10px;
			margin-top: ${margin + 2em + 10vh};
			transition: all .25s;
			&:hover {
				background: red;
			}
			foo, bar {
				beep, boop {
					&+& {
						margin: 2em;
					}
				}
			}
		');
	}	
}