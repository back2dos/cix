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
  VAtom(name:String);
  VColor(color:tink.color.Color);
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

typedef DeclarationOf<Child:DeclarationOf<Child>> = {
  
  final properties:ListOf<Property>;

  final childRules:ListOf<{
    final selector:Located<Selector>;
    final declaration:Child;
  }>;
}

typedef PlainDeclaration = DeclarationOf<PlainDeclaration>;

typedef NormalizedDeclaration = PlainDeclaration & ExtrasOf<PlainDeclaration>;

typedef Variable = {
  final name:StringAt;
  final value:CompoundValue;
}

typedef State = {
  final name:StringAt;
  final cond:StateCondition;
}

typedef Declaration = DeclarationOf<Declaration> & ExtrasOf<Declaration> & {
  final variables:ListOf<Variable>;
  final states:ListOf<State & {
    final declaration:Declaration;
  }>;
}

typedef ExtrasOf<Child:DeclarationOf<Child>> = {
  final fonts:ListOf<FontFace>;
  final keyframes:ListOf<Keyframes>;
  final mediaQueries:ListOf<MediaQueryOf<Child>>;
}

typedef MediaQuery = MediaQueryOf<Declaration>;

typedef MediaQueryOf<Child:DeclarationOf<Child>> = {
  final conditions:ListOf<FullMediaCondition>;
  final declaration:Child;
}

typedef FullMediaCondition = Located<MediaCondition> & {
  final negated:Bool;
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

typedef FontFace = Located<ListOf<Property>>;

typedef AnimationName = StringAt & { final quoted:Bool; };

typedef Keyframes = {
  final name:AnimationName;
  final frames:ListOf<{
    final pos:Int;
    final properties:ListOf<Property>;
  }>;
}

enum StateCondition {
  IsSet;
  IsNotSet;
  Eq(value:StringAt);
}