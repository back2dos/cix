package cix.css;

import tink.domspec.ClassName;

class Declarations {
  static var declared:Map<String, Bool>;
  static public function add(className:ClassName, css:()->String) {
    if (declared == null)
      declared = new Map();
    if (!declared[className]) {
      Runtime.addRule(className, css());
      declared[className] = true;
    }
    return className;
  }
}