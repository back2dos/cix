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

  static function val(value:Expr):CompoundValue
    return switch value {
      case { expr: EConst(CString(s)) }: Parser.parseVal(value).sure();
      case { expr: EConst(CIdent(s)) }: { importance: 0, components: [[{ pos: value.pos, value: VVar(s) }]] };
      default: value.reject('invalid expression');
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

  static public function parse(e:Expr):Declaration {
    var variables = [],
        properties = [],
        mediaQueries = [],
        keyframes = [],
        fonts = [],
        childRules = [];

    var ret:Declaration = {
      variables: variables,
      properties: properties,
      mediaQueries: mediaQueries,
      keyframes: keyframes,
      fonts: fonts,
      childRules: childRules,
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

            case macro @media($a{args}) $rules:
              e.reject('media queries not supported yet');

            case macro $s => $rules:
              childRules.push({
                selector: {
                  pos: s.pos,
                  value: selector(s)
                },
                declaration: switch rules.expr {
                  case EConst(CString(_)): Parser.parseDecl(rules).sure();
                  default: parse(rules);
                }
              });
            case tryProp(_) => Success(p): properties.push(p);
            default: e.reject('invalid syntax');
          }

      default: e.reject('invalid rule');
    }

    return ret;
  }

  static function selector(e:Expr)
    return switch e.expr {
      case EConst(CString(s)):
        @:privateAccess // TODO: this should not be necessary
          new SelectorParser(
            s,
            tink.parse.Reporter.expr((e.pos:tink.parse.Position).file)
          )
            .parseFullSelector();
      case EConst(CIdent(s)):
        [[({
          tag: s,
        }:SelectorPart)]];
      default:
        e.reject('string expected');
    }
}
#end