package cix.css;

#if (cix.embed || (js && !nodejs))
class Runtime {
  static var indices:Map<String, Int>;
  
  static var sheet:js.html.CSSStyleSheet;
  static public function addRule(id:String, css:String) {
    if (indices == null) {
      indices = new Map();
      
      var style = js.Browser.document.createStyleElement();
      js.Browser.document.head.appendChild(style);
      sheet = cast style.sheet;
    }

    sheet.insertRule(
      '@media all { $css }', 
      switch indices[id] {
        case null: indices[id] = sheet.cssRules.length;
        case v: v;
      }
    );
  }
}
#else
@:notSupported class Runtime {

}
#end