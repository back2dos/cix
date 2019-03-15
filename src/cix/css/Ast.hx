package cix.css;

import tink.csss.Selector;
import haxe.macro.Expr;
using tink.CoreApi;

typedef CompoundValue = ListOf<ListOf<Located<ValueKind>>>;

typedef Located<T> = tink.parse.Located<T, tink.parse.Position>;

enum ValueKind {
  Numeric(value:Float, ?unit:Unit);
  Ident(name:String);
  Code(c:CodeKind);
}

enum CodeKind {
  Var(name:String);

}

@:enum abstract Unit(String) {
  var Px = 'px';
}