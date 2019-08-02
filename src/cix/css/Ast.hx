package cix.css;

import tink.csss.Selector;
using tink.CoreApi;

typedef CompoundValue = {
  final components:ListOf<ListOf<SingleValue>>;
  final importance:Int;
}

typedef Located<T> = tink.parse.Located<T, tink.parse.Position>;

typedef SingleValue = Located<ValueKind>;

enum ValueKind {
  VNumeric(value:Float, ?unit:Unit);
  VVar(name:String);
  VColor(h:Float, v:Float, l:Float, o:Float);
  VString(value:String);
  VBinOp(op:BinOp, lh:SingleValue, rh:SingleValue);
  VCall(name:StringAt, args:ListOf<SingleValue>);
}

typedef StringAt = Located<String>;

enum abstract BinOp(String) to String {
  var OpAdd = '+';
  var OpSubt = '-';
  var OpMult = '*';
  var OpDiv = '/';

  static public final all:Iterable<BinOp> = [OpAdd, OpSubt, OpMult, OpDiv];
  
  public function getPrio():Int 
    return switch this {
      case OpAdd | OpSubt: 0;
      default: 1;
    }
}

enum abstract Unit(String) to String {

  var None = null;
  var Px = 'px';
  var Pct = '%';
  var Em = 'em';
  var Rem = 'rem';
  var VH = 'vh';
  var VW = 'vw';
  var VMin = 'vmin';
  var VMax = 'vmax';
  var Deg = 'deg';
  var Sec = 's';
  var MS = 'ms';

  var MixedLength = 'calc(length)';

  // public var kind(get, never):UnitKind;
  public function getKind():UnitKind
    return switch this {
      case Deg: KAngle;
      case Sec | MS: KDuration;
      case None: KScalar;
      default: KLength;
    }
}

enum abstract UnitKind(String) to String {
  var KScalar = 'scalar';
  var KLength = 'length';
  var KDuration = 'duration';
  var KAngle = 'angle';
}

typedef Property = {
  final name:StringAt;
  final value:CompoundValue;
}

typedef Declaration = {
  
  final variables:ListOf<{
    final name:StringAt;
    final value:CompoundValue;
  }>;

  final fonts:ListOf<FontFace>;
  final keyframes:ListOf<Keyframes>;
  
  final properties:ListOf<Property>;

  final childRules:ListOf<{
    final selector:Selector;
    final pos:tink.parse.Position;
    final declaration:Declaration;
  }>;

  final mediaQueries:ListOf<MediaQuery>;
}

typedef MediaQuery = {
  final conditions:ListOf<{
    final negated:Bool;
    final condition:MediaCondition;
  }>;
  final declaration:Declaration;
}

enum MediaCondition {
  And(a:MediaCondition, b:MediaCondition);
  Feature(name:StringAt, val:SingleValue);
  Type(t:MediaType);
}

enum abstract MediaType(String) to String {
  var All = 'all';
  var Print = 'print';
  var Screen = 'screen';
  var Speech = 'speech';
}

typedef FontFace = ListOf<Property>;

typedef Keyframes = {
  final name:StringAt;
  final frames:ListOf<{
    final pos:Int;
    final properties:ListOf<Property>;
  }>;
}