package cix.css;

#if (js && !nodejs)
class Runtime {
  static var indices = new Map();
  static var sheet:js.html.CSSStyleSheet = {
    var style = js.Browser.document.createStyleElement();
    js.Browser.document.head.appendChild(style);
    cast style.sheet;
  }
  static public function addRule(id:String, css:String) 
    sheet.insertRule(
      css, 
      switch indices[id] {
        case null: indices[id] = sheet.cssRules.length;
        case v: v;
      }
    );
}
#else
@:notSupported class Runtime {

}
#end