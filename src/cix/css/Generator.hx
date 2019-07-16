package cix.css;

#if macro
import cix.css.Ast;
import tink.csss.Selector;
import haxe.macro.Expr;
import haxe.macro.Type;
import tink.parse.*;

using StringTools;
using tink.MacroApi;
using tink.CoreApi;

class Generator<Error> {
  
  static var counter = 0;
  static dynamic public function generateName(src:DeclarationSource, decl:Declaration):String
    return 'cix_${counter++}';

  var reporter:Reporter<Position, Error>;
  
  function compoundValue(v:CompoundValue, resolve) 
    return [
      for (v in v) 
        [for (single in v) singleValue(single, resolve)].join(' ')
    ].join(', ');

  var getCall:(name:StringAt, reporter:Reporter<Position, Error>)->((orig:SingleValue, args:ListOf<SingleValue>)->Outcome<SingleValue, Error>);

  public function new(reporter, getCall) {
    this.reporter = reporter;
    this.getCall = getCall;
  }

  function fail(message, pos):Dynamic
    return throw reporter.makeError(message, pos);

  public function rule(src:DeclarationSource, d:Declaration) 
    return generateDeclaration(generateName(src, d), d, new Map());

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
        case [_, props]: 
          var all = '$path {';
          for (p in props)
            all += '\n\t${p.name.value}: ${compoundValue(p.value, vars.get)}${if (p.isImportant) ' !important' else ''};';
          all +'\n}';
      }

    for (c in d.childRules) {
      ret += '\n\n' + generateDeclaration(c.selector.raw.trim().replace('&', path), c.declaration, vars);
    }

    return ret;
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
    return getCall(name, reporter)(s, args);

  function reduce(s:SingleValue, resolve:String->Null<SingleValue>) {
    
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
              case null: fail(reporter.makeError('unknown identifier $name', s.pos));
              case v: v;
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
    return reducedValue(reduce(s, resolve).sure());

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

enum DeclarationSource {
  InlineRule(pos:Position, localType:BaseType, localMethod:Null<String>);
  NamedRule(name:StringAt, localType:BaseType, localMethod:Null<String>);
  Field(name:StringAt, cls:BaseType);
}
#end