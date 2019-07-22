package cix.css;

import tink.domspec.ClassName;

class Declarations {
  static var declared = new Map();
  static public function add(className:ClassName, css:()->String) {
    if (!declared[className]) {
      Runtime.addRule(className, css());// if you get a compilation error here, consult the manual on CSS generation
      declared[className] = true;
    }
    return className;
  }
}