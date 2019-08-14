package cix.css;

using StringTools;

class Casing {
  static var k2c = new Map();
  
  static public function kebabToCamel(s:String) 
    return switch k2c[s] {
      case null:
        var parts = s.split('-');
        k2c[s] = [for (i in 0...parts.length) {
          var part = parts[i];
          if (i == 0) part;
          else part.charAt(0).toUpperCase() + part.substr(1);
        }].join('');
      case v: v;
    }

  static var c2k = new Map();

  static public function camelToKebab(s:String) 
    return switch c2k[s] {
      case null:
        var lower = s.toLowerCase();
        var ret = lower.charAt(0);

        function isLower(index)
          return s.charCodeAt(index) == lower.charCodeAt(index);

        for (i in 1...s.length) {
          switch [isLower(i - 1), isLower(i)] {
            case [true, false]: ret += '-';
            default:
          }
          ret += lower.charAt(i);
        }

        c2k[s] = ret;
      case v: v;
    }
}