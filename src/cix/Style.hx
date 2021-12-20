package cix;

class Style {

  macro static public function rule(e)
    return cix.css.Generator.makeRule(e);

  macro static public function sheet(e)
    return cix.css.Generator.makeSheet(e);

  macro static public function styled(target, e)
    return macro ${cix.css.Generator.makeRule(e)}.applyTo($target);

}