package ;

// import A;

class Run {
	
	static final DURATION = '25s';

  static final bar = cix.Style.sheet({
		var color = 'red';
		table => {
			border = 'none !important';
			div => {
				padding = '2em';
				background = color;
				transition = 'all $DURATION';
			}
			'&:hover' => {
				background = color;
				div => {
					background = 'blue';
				}
			}			
		}
		div => {
			background = color;
		}
	});
  static final foo = cix.Style.rule('
		$margin: 10px;
		margin-top: ${margin + 2em + 10vh};
		transition: all .25s;
		$color: yellow;
		&:hover {
			background: mix(blue, mix(red, $color));
			@media (max-width: 500px) {
				font-size: 2em;
			}
		}
		@font-face {
			src: url("/fonts/OpenSans-Regular-webfont.woff2") format("woff2"),
					 url("/fonts/OpenSans-Regular-webfont.woff") format("woff");				
			font-family: "Open Sans";
		}
		foo, bar {
			beep, boop {
				@keyframes foo {
					0%: {
						transform: none;
					}
					100%: {
						transform: scale(1.25);
					}
				}
				&+& {
					margin: 2em;
					animation: foo .5s linear 1s infinite alternate;
				}
			}
		}
	');

	static function main() {
		trace(bar.table);
		trace(bar.div);
		trace(foo);
	}	
}