package cix.css;

import tink.domspec.ClassName;

class Declarations {
  static var declared = new Map();
  static public function add(className:ClassName, css:()->String) {
    if (!declared[className]) {
      Runtime.addRule(className, css());
      declared[className] = true;
    }
    return className;
  }
}