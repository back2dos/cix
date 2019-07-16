package cix.css;

import tink.parse.Char.*;
import haxe.macro.Expr;
import tink.parse.Position;

class SelectorParser extends tink.csss.Parser<Position, Error> {

  static final AMP = Char('&'.code);

  override function shouldContinue()
    return super.shouldContinue() || is(AMP);

  override function parseSelectorPart() 
    return
      if (allow('&')) parseSelectorNext('&');
      else super.parseSelectorPart();
}