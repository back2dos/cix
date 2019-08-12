package cix;

class Style {

  macro static public function rule(e) 
    return cix.css.Generator.makeRule(e);

  macro static public function sheet(e) 
    return cix.css.Generator.makeSheet(e);

}