package cix.css;

#if macro
import cix.css.Ast;
import tink.csss.Selector;
import haxe.macro.Expr;
import tink.parse.*;

using tink.MacroApi;
using tink.CoreApi;

class Generator<Error> {
  
  var reporter:Reporter<Position, Error>;
  
  function compoundValue(v:CompoundValue, resolve) 
    return [
      for (v in v) 
        [for (single in v) singleValue(single, resolve)].join(' ')
    ].join(', ');

  static var calls:Map<String, (orig:SingleValue, args:ListOf<SingleValue>)->Outcome<SingleValue, String>> = [
    'calc' => (o, _) -> Success(o),
    'saturate' => (orig, args) -> switch args {
      case [{ value: VColor(h, s, l, o) }, { value: VNumeric(v, null) }]: 
        Success({ pos: orig.pos, value: VColor(h, Math.max(0, Math.min(1, s * v)), l, o)});
      default: Failure('invalid arguments');
    },

  ];

  public function new(reporter) {
    this.reporter = reporter;
  }

  function fail(message, pos):Dynamic
    return throw reporter.makeError(message, pos);

  public function declaration(d:Declaration) {
    return generateDeclaration(null, d, new Map());
  }

  function generateDeclaration(path:String, d:Declaration, vars:Map<String, SingleValue>) {
    
    vars = vars.copy();

    for (v in d.variables)
      switch v.value {
        case [[s]]: vars.set(v.name.value, s);
        default: fail('variables must be initialized with a single value', v.name.pos);
      }

    var ret = 
      switch [path, d.properties] {
        case [null, []]: '';
        case [null, v]: fail('no properties allowed at top level', v[0].name.pos);
        case [_, v]: '';
      }

    return rules;
  }

  function map(s:SingleValue, f:SingleValue->SingleValue)
    return f(switch s.value {
      case VBinOp(op, lh, rh):
        { pos: s.pos, value: VBinOp(op, f(lh), f(rh)) };
      case VCall(name, args):
        { pos: s.pos, value: VCall(name, args.map(f)) };
      default: s;
    });

  function call(s, name:StringAt, args)
    return switch calls[name.value] {
      case null: Failure(reporter.makeError('Unknown method ${name.value}', name.pos));
      case f: switch f(s, args) {
        case Success(v): Success(v);
        case Failure(m): Failure(reporter.makeError(m, s.pos));
      }
    }

  function reduce(s:SingleValue, resolve:String->Option<SingleValue>) {
    
    var error = None;

    function fail(e):Dynamic {
      error = Some(e);
      throw error;
    }

    return 
      try 
        Success(map(s, s -> switch s.value {
          case VVar(name):
            switch resolve(name) {
              case Some(v): v;
              case None: fail(reporter.makeError('unknown identifier $name', s.pos));
            }
          case VBinOp(_):
            fail(reporter.makeError('bin ops not implemented yet', s.pos));
          case VCall(name, args):
            call(s, name, args).sure();
          default: s;
        }))
    catch (e:Dynamic) switch error {
      case Some(e): Failure(e);
      case None: throw e;
    }
  }

  function singleValue(s, resolve)
    return reduce(s, resolve);

  function reducedValue(s:SingleValue):String {

    function rec(s)
      return reducedValue(s);

    return switch s.value {
      case VNumeric(value, unit): 
        value + switch unit {
          case null: '';
          case v: v;
        }
      case VString(value):
        value;
      case VBinOp(op, rec(_) => lh, rec(_) => rh):
        '$lh $op $rh';
      case VCall(name, _.map(rec).join(', ') => args):
        '${name.value}($args)';
      default: 
        throw 'assert';
    }
  }
}
#end