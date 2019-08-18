package cix.css;

import tink.parse.*;
import tink.csss.Selector;
import cix.css.Ast;

using tink.CoreApi;


abstract Failure(Position->StringAt) from Position->StringAt {

  public inline function at(pos)
    return this(pos);

  @:from static function ofString(s:String):Failure
    return pos -> { pos: pos, value: s };

  @:from static function ofStringAt(s:StringAt):Failure
    return _ -> s;

}

abstract CallResolver(CallResolverFunc) from CallResolverFunc to CallResolverFunc {//TODO: this whole thing is perhaps a bit too over-engineered
  public inline function resolve(name)
    return
      if (this == null) None;
      else this(name); 

  @:op(a || b) public function or(that:CallResolver):CallResolver
    return 
      if (this == null) that;
      else name -> switch this(name) {
        case None: that.resolve(name);
        case v: v;
      }

  @:from static function ofCalls(calls:haxe.DynamicAccess<Call>):CallResolver 
    return name -> switch calls[Casing.kebabToCamel(name)] {//TODO: the normalization should probably be smarter
      case null: None;
      case fn: Some(fn);
    }

  static public function makeCall1<T1>(parse1, fn:T1->Outcome<ValueKind, Failure>, ?default1:T1):Call 
    return makeCallN([
      new Param(parse1, default1)
    ], fn);

  static public function makeCall2<T1, T2>(parse1, parse2, fn:T1->T2->Outcome<ValueKind, Failure>, ?default2:T2, ?default1:T1):Call 
    return makeCallN([
      new Param(parse1, default1),
      new Param(parse2, default2),
    ], fn);

  static public function makeCall3<T1, T2, T3>(parse1, parse2, parse3, fn:T1->T2->T3->Outcome<ValueKind, Failure>, ?default3:T3, ?default2:T2, ?default1:T1):Call 
    return makeCallN([
      new Param(parse1, default1),
      new Param(parse2, default2),
      new Param(parse3, default3),
    ], fn);

  static public function makeCall4<T1, T2, T3, T4>(parse1, parse2, parse3, parse4, fn:T1->T2->T3->T4->Outcome<ValueKind, Failure>, ?default4:T4, ?default3:T3, ?default2:T2, ?default1:T1):Call 
    return makeCallN([
      new Param(parse1, default1),
      new Param(parse2, default2),
      new Param(parse3, default3),
      new Param(parse4, default4),
    ], fn);

  static function makeCallN(params:Array<Param>, fn:haxe.Constraints.Function):Call {
    var required = 0;
    
    for (i in 0...params.length) 
      if (params[i].fallback == null) {
        required++;
        if (required <= i) throw 'no support for argument skipping';
      }

    return 
      (orig, args) -> 
        if (args.length < required) Failure({ value: 'Required $required arguments, found ${args.length}', pos: orig.pos });
        else {
          var args = [
            for (i in 0...params.length) 
              switch args[i] {
                case null: params[i].fallback;
                case v: switch params[i].parse(v) {
                  case Success(a): a;
                  case Failure(e): return Failure({ value: e, pos: v.pos });
                }
              }
          ];

          var ret:Outcome<ValueKind, Failure> = Reflect.callMethod(null, fn, args);
          switch ret {
            case Success(v): Success({ value: v, pos: orig.pos });
            case Failure(e): Failure(e.at(orig.pos));
          }
        }
  }

}

typedef Exception = StringAt;

typedef Call = (orig:SingleValue, args:ListOf<SingleValue>)->Outcome<SingleValue, Exception>;

typedef CallResolverFunc = (name:String)->Option<Call>;

private class Param {
  public final parse:SingleValue->Outcome<Any, String>;
  public final fallback:Null<Any>;
  public function new<T>(parse:SingleValue->Outcome<T, String>, ?fallback:T) {
    this.parse = cast parse;
    this.fallback = fallback;
  }
}