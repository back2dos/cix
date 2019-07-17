package cix.css;

import tink.domspec.ClassName;

class Runtime {
  static public function declare(className:ClassName, css:()->String) {
    return className;
  }
}