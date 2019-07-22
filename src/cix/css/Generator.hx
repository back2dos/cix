package cix.css;

#if macro
import cix.css.Ast;
import tink.csss.Selector;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import tink.parse.*;

using StringTools;
using tink.MacroApi;
using tink.CoreApi;

class Generator<Error, Result> {
  
  #if macro 
  static public function resultExpr(pos:Position, className:String, css:String) 
    return
      #if cix_output
        #error
      #else
        macro @:pos(pos) cix.css.Declarations.add($v{className}, () -> $v{css});
      #end
  #end

  @:persistent static var counter = 0;

  static public var namespace = 
    switch Context.definedValue('cix-namespace') {
      case null | '': 'cix';
      case v: v; 
    }

  static function typeName(b:BaseType)
    return b.pack.concat([b.name]).join('.');

  static dynamic public function showSource(src:DeclarationSource)
    return
      #if debug
        switch src {
          case InlineRule(_, t, m): join([typeName(t), m]);
          case NamedRule(n, t, m): join([typeName(t), m, n.value]);
          case Field(n, t): join([typeName(t), n.value]);
        }
      #else
        '';
      #end

  static public dynamic function join(parts:Array<String>)
    return [for (p in parts) if (p != null) switch p.trim() {
      case '': continue;
      case v: v;
    }].join('﹕');

  static public dynamic function generateClass(src:DeclarationSource, decl:Declaration):String
    return join([namespace, showSource(src), '${counter++}']);

  var reporter:Reporter<Position, Error>;
  
  function compoundValue(v:CompoundValue, resolve) 
    return [
      for (v in v) 
        [for (single in v) singleValue(single, resolve)].join(' ')
    ].join(', ');

  var getCall:(name:StringAt, reporter:Reporter<Position, Error>)->((orig:SingleValue, args:ListOf<SingleValue>)->Outcome<SingleValue, Error>);
  var generateResult:(pos:Position, className:String, css:String)->Result;
  var makeClass:(src:DeclarationSource, decl:Declaration)->String;

  public function new(reporter, getCall, generateResult, ?makeClass) {
    this.reporter = reporter;
    this.getCall = getCall;
    this.generateResult = generateResult;
    this.makeClass = switch makeClass {
      case null: generateClass;
      case v: v;
    }
  }

  function fail(message, pos):Dynamic
    return throw reporter.makeError(message, pos);

  public function rule(src:DeclarationSource, d:Declaration) {
    var className = generateClass(src, d);
    return generateResult(
      switch src {
        case InlineRule(pos, _): pos;
        case NamedRule(n, _) | Field(n, _): n.pos;
      },
      className, 
      generateDeclaration('.$className', d, new Map())
    );
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