package cix.css;

#if macro
import tink.csss.Selector;
import cix.css.Ast;
import haxe.macro.Expr;

using tink.CoreApi;
using tink.MacroApi;

class HxParser {

  static public function parses(e:Expr):Bool
    return e.expr.match(EBlock(_) | EObjectDecl(_));

  static function tryProp(e:Expr):Outcome<Property, Error>
    return switch e {
      case macro $name = $value: 
        if (value.expr.match(EBlock(_) | EObjectDecl(_)))
          name.reject('Did you mean `${name.toString()} => { ... }`?');
        Success(prop(name, value));
      default: e.pos.makeFailure('property expected');
    }

  static function props(e:Expr):ListOf<Property>
    return switch e.expr {
      case EBlock(exprs):
        [for (e in exprs) tryProp(e).sure()];
      default: e.reject('block expected');
    }

  static function singleVal(value:Expr):SingleValue
    return {
      pos: value.pos,
      value: switch value {
        case { expr: EConst(CIdent(s)) }: VVar(s);
        case { expr: EConst(CString(s)) }: VString(s);
        case { expr: EConst(CFloat(s) )}: VNumeric(Std.parseFloat(s)); 
        case { expr: EConst(CInt(s) )}: VNumeric(Std.parseInt(s)); 
        case macro $fn($a{args}): 
          VCall(
            { pos: fn.pos, value: fn.getIdent().sure() }, 
            [for (a in args) switch val(a) {
              case { importance: 0, components: [[v]] }: v;
              default: a.reject('single css value expected');
            }]
          );
        default: value.reject('invalid expression');
      }
    }
      

  static function val(value:Expr):CompoundValue
    return switch value {
      case { expr: EConst(CString(s)) }: 
        Parser.parseVal(value).sure();
      default: 
        { importance: 0, components: [[singleVal(value)]] };
    }

  static function prop(name:Expr, value:Expr):Property
    return {
      name: {
        pos: name.pos,
        value: switch name.expr {
          case EConst(CString(s)): s;
          case EConst(CIdent(s)): Casing.camelToKebab(s);
          default: name.reject('property name should be string or identifier');
        }
      },
      value: val(value),
    }

  static function parseDecl(e:Expr):Declaration 
    return
      switch e.expr {
        case EConst(CString(_)): Parser.parseDecl(e).sure(); //TODO: this duplicates the switch in Generator
        default: parse(e);
      }  

  static public function parse(e:Expr):Declaration {

    var variables = [],
        properties = [],
        mediaQueries = [],
        keyframes = [],
        fonts = [],
        states = [],
        childRules = [];

    var ret:Declaration = {
      variables: variables,
      properties: properties,
      mediaQueries: mediaQueries,
      keyframes: keyframes,
      fonts: fonts,
      childRules: childRules,
      states: states,
    }

    switch e.expr {
      case EObjectDecl(fields):
        throw 'assert';

      case EBlock(exprs):
        for (e in exprs)
          switch e {
            case macro var $name = $value:
              variables.push({
                name: { pos: e.pos, value: name },
                value: val(value)
              });
            case macro @keyframes($a{args}) $rules:

              keyframes.push({
                name: switch args {
                  case []: e.reject('@keyframes require name argument');
                  case [v]: { pos: v.pos, value: v.getName().sure(), quoted: v.expr.match(EConst(CString(_))) };
                  case v: v[1].reject('too many arguments');
                },
                frames: switch rules.expr {
                  case EBlock(exprs):
                    [for (e in exprs) switch e {
                      case macro $v{(pos:Int)} % $properties:
                        {
                          pos: Std.parseInt(pos),
                          properties: props(properties),
                        }
                      default: e.reject('keyframe expected');
                    }];
                  default: rules.reject('block expected');
                }
              });

            case macro @fontface($a{args}) $properties:
              switch args {
                case []:
                case v: v[1].reject('no arguments allowed here');
              }

            case macro @state($a{args}) $decl:
              function s(e:Expr)
                return {
                  pos: e.pos,
                  value: e.getIdent().sure()
                } 
                
              function add(name, cond)
                states.push({
                  name: s(name),
                  cond: cond,
                  declaration: parseDecl(decl),
                });

              switch args {
                case [macro !$name]: add(name, IsNotSet);
                case [macro $name = $value]: add(name, Eq(s(value)));
                case [macro $name]: add(name, IsSet);
                case []: e.reject('no arguments allowed here');
                case v: v[1].reject('exactly one arguments allowed here');
              }
            case macro @media($a{args}) $rules:
              e.reject('media queries not supported yet');

            case macro $s => $rules:
              childRules.push({
                selector: {
                  pos: s.pos,
                  value: selector(s)
                },
                declaration: parseDecl(rules)
              });
            case tryProp(_) => Success(p): properties.push(p);
            default: e.reject('invalid syntax');
          }

      default: e.reject('invalid rule');
    }

    return ret;
  }

  static function merge<T:{}>(objects:Array<T>):T {
    var ret:Dynamic = {};
    for (o in objects)
      for (field in Reflect.fields(o))
        Reflect.setField(ret, field, Reflect.field(o, field));
    return ret;
  }

  static function selector(e:Expr):Selector
    return 
      switch e {
        case macro $v{(s:String)}:
          @:privateAccess // TODO: this should not be necessary
            new SelectorParser(
              s,
              tink.parse.Reporter.expr((e.pos:tink.parse.Position).file)
            )
              .parseFullSelector();
        default:
          [selectorOption(e)];
      }

  static var PSEUDOS = @:privateAccess {
    var p = tink.csss.Parser;
    [for (m in [p.STRICT_ELEMENTS, p.ELEMENTS, p.SIMPLE])
      for (s => p in m) s => p
    ];
  }

  static function selectorOption(e:Expr):SelectorOption {
    
    function patch(s:SelectorOption, patch:SelectorPart->SelectorPart):SelectorOption
      return [for (i in 0...s.length) {
        var p = s[i];
        if (i < s.length - 1) p;
        else merge([p, patch(p)]);
      }];

    function name(e:Expr)
      return switch e.expr {
        case EConst(CString(s)): s;
        case EConst(CIdent(s)): Casing.camelToKebab(s);
        default: e.reject('name expected');
      }

    function pseudo(e:Expr)
      return switch e {
        case macro $i{Casing.camelToKebab(_) => s}: 
          switch PSEUDOS[s] {
            case null: e.reject('unknown pseudo class/element');
            case v: v;
          }
        case macro $i{_}($a{args}):
          e.reject('pseudo classes/elements with args are currently not supported');
        default: e.reject('invalid pseudo class/element');
      }

    function attr(a:Expr):AttrFilter
      return switch a {
        case { expr: EBinop(op, n, v)}:
          {
            name: name(n),
            value: name(v),
            op: switch op {
              case OpAssign: Exactly;
              case OpAssignOp(op): 
                switch op {
                  case OpXor: BeginsWith;
                  case OpOr: HyphenSeparated;
                  case OpMult: Contains;
                  default: a.reject('unsupported attribute operator');
                }
              default: a.reject('unsupported attribute operator');
            }
          }
        default:
          {
            name: name(a)
          }
      }

    return switch e {
      case macro $i{s}:
        [{
          tag: switch s {
            case '_': null;
            case '$': '&';
            case v: Casing.camelToKebab(v);
          },
        }];
      case macro $e.$cls:
        patch(selectorOption(e), o -> {
          classes: o.classes.concat([Casing.camelToKebab(cls)]),
        });
      case macro $e[$a]:
        patch(selectorOption(e), o -> {
          attrs: o.attrs.concat([attr(a)]),
        });
      case macro [$a]:
        [{
          attrs: [attr(a)]
        }];
      case macro $e($p):
        patch(selectorOption(e), o -> {
          pseudos: o.pseudos.concat([pseudo(p)]),
        });
      case macro ($p):
        [{
          pseudos: [pseudo(p)],
        }];
      case { expr: EBinop(op, parent, child )}:
        patch(selectorOption(parent), o -> {
          combinator: switch op {
            case OpGt: Child;
            case OpShr: Descendant;
            case OpAdd: AdjacentSibling;
            case OpInterval: GeneralSibling;
            default: e.reject('invalid combinator');
          },
        }).concat(selectorOption(child));
      default:
        e.reject('selector expected');
    }
  }
}
#end