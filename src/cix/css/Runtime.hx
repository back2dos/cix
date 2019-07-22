package cix.css;

class Runtime {
  #if js
    static var indices = new Map();
    static var sheet:js.html.CSSStyleSheet = {
      var style = js.Browser.document.createStyleElement();
      js.Browser.document.head.appendChild(style);
      cast style.sheet;
    }
  #end
  @:require(js && !nodejs)
  static public function addRule(id:String, css:String) {
    #if js        
      sheet.insertRule(
        css, 
        switch indices[id] {
          case null: indices[id] = sheet.cssRules.length;
          case v: v;
        }
      );
    #end
  }
}