package cix.css;

import tink.csss.Selector;
using tink.CoreApi;

typedef CompoundValue = ListOf<ListOf<SingleValue>>;

typedef Located<T> = tink.parse.Located<T, tink.parse.Position>;

typedef SingleValue = Located<ValueKind>;

enum ValueKind {
  VNumeric(value:Float, ?unit:Unit);
  VIdent(name:String);
  VString(value:String);
  VExpr(c:ExprKind);
  VCall(name:StringAt, args:ListOf<SingleValue>);
}

typedef StringAt = Located<String>;

enum ExprKind {
  XVar(name:String);
}

@:enum abstract Unit(String) {
  var Px = 'px';
}

typedef Declaration = {
  var properties(default, null):ListOf<NamedWith<StringAt, CompoundValue>>;
  var variables(default, null):ListOf<NamedWith<StringAt, CompoundValue>>;
  var childRules(default, null):ListOf<{
    var selector(default, null):Selector;
    var declaration(default, null):Declaration;
  }>;
}