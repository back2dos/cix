package ;

import cix.Style.rule as css;

class States {
	static final HUGE = css('
		@state(!stretch) {
			width: auto;
		}
		@state(stretch) {
			width: 100%;
		}
	');


	static function main() {
		trace(HUGE);
	}
}