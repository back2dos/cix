package ;

// import A;

class Run {
	
	static final DURATION = '25s';

  static final bar = cix.Style.sheet({
		var color = 'red';
		table => {
			border = 'none !important';
			div.hoho[foo=bar] > zrt >> bar ... haha + flump => {
				padding = '2em';
				background = mix(color, invert('blue'), .5);
				$.hoho => {
					color = 'yellow';
				}
				transition = 'all $DURATION';
				var faded = fade(fade(color, '40%'), .5);
				color= faded;
				border = '1px solid opacity($faded, 80%)';
			}
			'&:hover' => {
				background = color;
				div => {
					background = 'blue';
				}
			}
			$(focus) => {
				outline = '1px solid red';
				background = dataUri('"android.svg"');
			}		
		}
		div => {
			background = color;
		}
	});
  static final foo = cix.Style.rule('
		$margin: 10px;
		margin-top: ${margin + 2em + 10vh};
		margin-right: ($margin + 2em + 10vh);
		transition: all .25s;
		$color: yellow;
		display: -webkit-box;
		-webkit-blub: boink;
		&:hover {
			background: mix(blue, mix(red, $color));
			@media (max-width: 500px) {
				font-size: ${A.FONTSIZE};
			}
		}
		@state(foo=bar) {
			margin-top: ${margin + 2em};
		}
		@font-face {
			src: url("/fonts/OpenSans-Regular-webfont.woff2") format("woff2"),
					 url("/fonts/OpenSans-Regular-webfont.woff") format("woff");				
			font-family: "Open Sans";
		}
		html {
			background: #eee;
		}
		html button {
			border: 2px solid pink;
		}
		div {
			$color: red;
			$thickness: 10px;
			div {
				padding: ${2 * thickness};
				margin: $thickness (2 * $thickness);
				background: $color;
			}  			
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