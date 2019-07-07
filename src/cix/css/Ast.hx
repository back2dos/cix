package cix.css;

import tink.csss.Selector;
using tink.CoreApi;

typedef CompoundValue = ListOf<ListOf<SingleValue>>;

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

enum BinOp {
  OpAdd;
}

enum abstract Unit(String) to String {
  var Px = 'px';
}

typedef Declaration = {
  final properties:ListOf<{
    final name:StringAt;
    final value:CompoundValue;
    final isImportant:Bool;
  }>;
  final variables:ListOf<{
    final name:StringAt;
    final value:CompoundValue;
    // final var isDefault:Bool;
  }>;
  final childRules:ListOf<{
    final selector:Selector;
    final pos:tink.parse.Position;
    final declaration:Declaration;
  }>;
}