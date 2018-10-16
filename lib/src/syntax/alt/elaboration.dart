// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../ast/ast_common.dart' show Name;
import '../../ast/algebra.dart';
import '../../errors/errors.dart';
import '../../fp.dart';
import '../../location.dart';
import '../../unicode.dart' as unicode;

import '../sexp.dart';

typedef Elab<S extends Sexp, T> = T Function(S);

abstract class BaseElaborator<Result, Name, Mod, Exp, Pat, Typ> {
  final NameAlgebra<Name> name;
  final ModuleAlgebra<Name, Mod, Exp, Pat, Typ> mod;
  final ExpAlgebra<Name, Exp, Pat, Typ> exp;
  final PatternAlgebra<Name, Pat, Typ> pat;
  final TypeAlgebra<Name, Typ> typ;

  BaseElaborator(this.name, this.mod, this.exp, this.pat, this.typ);

  Result elaborate(Sexp sexp);

  // Combinators.
  T expect<S extends Sexp, T>(Elab<S, T> elab, S sexp, {int index = -1}) {
    assert(elab != null && sexp != null);
    if (sexp is SList && index >= 0) {
      return elab((sexp as SList)[index]);
    } else {
      return elab(sexp);
    }
  }

  // Result expectSelf<S extends Sexp>(S sexp, {int index = -1}) {
  //   assert(sexp != null);
  //   if (sexp is SList && index >= 0) {
  //     return elaborate((sexp as SList)[index]);
  //   } else {
  //     return elaborate(sexp);
  //   }
  // }

  List<T> expectMany<S extends Sexp, T>(Elab<S, T> elab, SList list,
      {int start = 0, int end = -1}) {
    assert(elab != null && list != null && start >= 0);
    if (end < 0) end = list.length;
    int len = end - start;
    List<T> results = new List<T>(len >= 0 ? len : 0);
    for (int i = start; i < end; i++) {
      results[len - i] = elab(list[i]);
    }
    return results;
  }

  List<Result> expectManySelf<S extends Sexp>(SList list,
      {int start = 0, int end = -1}) {
    assert(list != null && start >= 0);
    if (end < 0) end = list.length;
    int len = end - start;
    List<Result> results = new List<Result>(len >= 0 ? len : 0);
    for (int i = start; i < end; i++) {
      results[len - i] = elaborate(list[i]);
    }
    return results;
  }

  List<T> expectManyOne<S extends Sexp, T>(Elab<S, T> elab, SList list,
      {int start = 0, int end = -1, ErrorNode<T> error}) {
    assert(elab != null && list != null && start >= 0);
    List<T> results = expectMany<S, T>(elab, list, start: start, end: end);
    if (results.length == 0) {
      return <T>[
        error != null ? error.make(BadSyntaxError(list.location.end)) : null
      ];
    } else {
      return results;
    }
  }

  // Atom validators.
  final Set<int> allowedIdentSymbols = Set.of(const <int>[
    unicode.AT,
    unicode.LOW_LINE,
    unicode.HYPHEN_MINUS,
    unicode.PLUS_SIGN,
    unicode.ASTERISK,
    unicode.SLASH,
    unicode.DOLLAR_SIGN,
    unicode.BANG,
    unicode.QUESTION_MARK,
    unicode.EQUALS_SIGN,
    unicode.LESS_THAN_SIGN,
    unicode.GREATER_THAN_SIGN,
    unicode.COLON,
    unicode.AMPERSAND,
    unicode.VERTICAL_LINE,
    unicode.APOSTROPHE,
  ]);

  bool isValidNumber(String text) {
    assert(text != null);
    // TODO: Support hexadecimal digits.
    return isValidInteger(text);
  }

  bool isValidInteger(String text) {
    assert(text != null);
    if (text.length == 0) return false;

    int c = text.codeUnitAt(0);
    int lowerBound = 0;
    if (c == unicode.HYPHEN_MINUS || c == unicode.PLUS) {
      if (text.length == 1) return false;
      lowerBound = 1;
    }

    for (int i = lowerBound; i < text.length; i++) {
      c = text.codeUnitAt(i);
      if (!unicode.isDigit(c)) return false;
    }
    return true;
  }

  bool isValidTermName(String name) {
    assert(name != null);
    if (name.length == 0) return false;

    // An identifier is not allowed to start with an underscore (_), colon (:),
    // or apostrophe (').
    int c = name.codeUnitAt(0);
    if (!unicode.isAsciiLetter(c) &&
        !(allowedIdentSymbols.contains(c) &&
            c != unicode.LOW_LINE &&
            c != unicode.COLON &&
            c != unicode.APOSTROPHE)) {
      return false;
    }

    for (int i = 1; i < name.length; i++) {
      c = name.codeUnitAt(i);
      if (!unicode.isAsciiLetter(c) &&
          !unicode.isDigit(c) &&
          !allowedIdentSymbols.contains(c)) {
        return false;
      }
    }
    return true;
  }

  bool isValidTypeVariableName(String name) {
    assert(name != null);

    if (name.length < 2) return false;
    int c = name.codeUnitAt(0);
    int k = name.codeUnitAt(1);
    if (c != unicode.APOSTROPHE) return false;
    if (!unicode.isAsciiLetter(k)) return false;

    for (int i = 1; i < name.length; i++) {
      c = name.codeUnitAt(i);
      if (!unicode.isAsciiLetter(c) && !unicode.isDigit(c)) return false;
    }

    return true;
  }

  bool isValidDataConstructorName(String name) {
    assert(name != null);
    return isValidTermName(name);
  }

  bool isValidTypeConstructorName(String name) {
    assert(name != null);
    if (name.length == 0) return false;
    int c = name.codeUnitAt(0);
    if (!unicode.isAsciiUpper(c)) return false;

    for (int i = 1; i < name.length; i++) {
      c = name.codeUnitAt(i);
      if (!unicode.isAsciiLetter(c)) return false;
    }
    return true;
  }

  bool isValidBoolean(String literal) {
    assert(literal != null);
    if (literal.length != 2) return false;

    int c = literal.codeUnitAt(1);
    return literal.codeUnitAt(0) == unicode.HASH &&
        (c == unicode.t || c == unicode.f);
  }

  bool isWildcard(String w) {
    assert(w != null);
    if (w.length != 1) return false;
    return w.codeUnitAt(0) == unicode.LOW_LINE;
  }

  bool denoteBool(String literal) {
    bool denotation;
    switch (literal) {
      case "#t":
        denotation = true;
        break;
      case "#f":
        denotation = false;
        break;
      default:
        assert(false);
        // TODO: use a proper exception.
        throw "fatal error: not a (surface syntax) boolean literal.";
    }
    return denotation;
  }

  // Atom parsers.
  Name termName(Atom sexp) {
    assert(sexp != null);
    if (isValidTermName(sexp.value)) {
      return name.termName(sexp.value, location: sexp.location);
    } else {
      return name.error(BadSyntaxError(sexp.location));
    }
  }

  Name typeName(Atom sexp) {
    assert(sexp != null);
    if (isValidTypeConstructorName(sexp.value)) {
      return name.typeName(sexp.value, location: sexp.location);
    } else {
      return name.error(BadSyntaxError(sexp.location));
    }
  }

  Name dataConstructorName(Atom sexp) {
    return termName(sexp);
  }

  Name typeVariableName(Atom sexp) {
    assert(sexp != null);
    if (isValidTypeVariableName(sexp.value)) {
      return name.typeName(sexp.value);
    } else {
      return name.error(BadSyntaxError(sexp.location));
    }
  }

  Exp expression(Sexp sexp) {
    assert(sexp != null);
    return null;
  }

  Pat pattern(Sexp sexp) {
    assert(sexp != null);
    return null;
  }

  // Typ signatureDatatype(Sexp sexp) {
  //   assert(sexp != null);
  //   return null;
  // }

  Typ datatype(Sexp sexp) {
    assert(sexp != null);
    return new TypeElaborator(name, typ).elaborate(sexp);
  }

  Name quantifier(Sexp sexp) {
    assert(sexp != null);
    return null;
  }

  Pair<Name, List<Name>> parameterisedTypeName(Sexp sexp) {
    assert(sexp != null);
    if (sexp is SList) {
      SList list = sexp;
      Name name = expect<Sexp, Name>(typeName, list[0]);
      List<Name> qs = expectMany<SList, Name>(quantifier, list, start: 1);
      return Pair<Name, List<Name>>(name, qs);
    } else {
      return Pair<Name, List<Name>>(
          name.error(BadSyntaxError(
              sexp.location, const <String>["identifier and quantifiers"])),
          <Name>[]);
    }
  }
}

class ModuleElaborator<Name, Mod, Exp, Pat, Typ>
    extends BaseElaborator<List<Mod>, Name, Mod, Exp, Pat, Typ> {
  ModuleElaborator(
      NameAlgebra<Name> name,
      ModuleAlgebra<Name, Mod, Exp, Pat, Typ> mod,
      ExpAlgebra<Name, Exp, Pat, Typ> exp,
      PatternAlgebra<Name, Pat, Typ> pat,
      TypeAlgebra<Name, Typ> typ)
      : super(name, mod, exp, pat, typ);

  List<Mod> elaborate(Sexp program) {
    if (program is Toplevel) {
      Toplevel toplevel = program;
      List<Mod> results = new List<Mod>(toplevel.sexps.length);
      for (int i = 0; i < toplevel.sexps.length; i++) {
        results[i] = expect<Sexp, Mod>(moduleMember, toplevel.sexps[i]);
      }
      return results;
    } else {
      throw "unhandled."; // TODO use a proper exception.
    }
  }

  // Module language.
  Mod moduleMember(Sexp sexp) {
    if (sexp is SList) {
      SList list = sexp;
      if (list.length > 0) {
        if (list[0] is Atom) {
          Atom atom = list[0];
          switch (atom.value) {
            case "define":
              return valueDefinition(atom, list);
            case "define-datatype":
              return datatypeDefinition(atom, list);
            case "define-typename":
              return typename(atom, list);
            case "open":
              return inclusion(atom, list);
            case ":":
              return signature(atom, list);
            default:
              return mod.error(BadSyntaxError(atom.location, <String>[
                "define",
                "define-datatype",
                "define-typename",
                "open",
                ": (signature)"
              ]));
          }
        }
      }
    }
    return mod.error(NakedExpressionAtToplevelError(sexp.location));
  }

  Mod valueDefinition(Atom head, SList list) {
    assert(head.value == "define");

    if (list.length < 3) {
      return mod.error(BadSyntaxError(list.location.end,
          <String>["value definition", "function definition"]));
    }

    if (list[1] is Atom) {
      // (define name E).
      if (list.length > 3) {
        return mod.error(
            BadSyntaxError(list[3].location, <String>[list.closingBracket()]));
      }
      Atom atom = list[1];
      Name ident = expect<Atom, Name>(termName, atom);
      Exp body = expect<Sexp, Exp>(expression, list[2]);
      return mod.value(ident, body);
    } else if (list[1] is SList) {
      // (define (name P*) E).
      SList list0 = list[1]; // TODO find a better name than 'list0'.
      if (list0.length > 0 && list0[0] is Atom) {
        Atom atom = list0[0] as Atom;
        Name ident = expect<Atom, Name>(termName, atom);
        List<Pat> parameters = expectMany<SList, Pat>(pattern, list0, start: 1);
        Exp body = expect<SList, Exp>(expression, list, index: 2);
        return mod.function(ident, parameters, body, location: list.location);
      } else {
        return mod.error(BadSyntaxError(
            list0.location, <String>["identifier and parameter list"]));
      }
    } else {
      return mod.error(BadSyntaxError(list[1].location,
          <String>["identifier", "identifier and parameter list"]));
    }
  }

  Mod datatypeDefinition(Atom head, SList list) {
    assert(head.value == "define-datatype");
    // (define-datatype name (K T*)* or (define-datatype (name q+) (K T*)*
    if (list.length < 2) {
      return mod.error(BadSyntaxError(
          list.location.end, const <String>["data type definition"]));
    }

    Pair<Name, List<Name>> name =
        expect<Sexp, Pair<Name, List<Name>>>(parameterisedTypeName, list[1]);

    // Parse any constructors and the potential deriving clause.
    List<Pair<Name, List<Typ>>> constructors =
        new List<Pair<Name, List<Typ>>>();
    List<Name> deriving;
    for (int i = 2; i < list.length; i++) {
      if (list[i] is SList) {
        SList clause = list[i];
        if (clause.length > 0 && clause[0] is Atom) {
          Atom atom = clause[0] as Atom;
          if (atom.value == "derive!") {
            if (deriving == null) {
              deriving = expectMany(typeName, clause, start: 1);
            } else {
              return mod.error(MultipleDerivingError(atom.location));
            }
          } else {
            // Data constructor.
            Name name = expect<Atom, Name>(dataConstructorName, atom);
            List<Typ> types =
                expectMany<SList, Typ>(datatype, clause, start: 1);
            constructors.add(Pair<Name, List<Typ>>(name, types));
          }
        } else {
          return mod.error(BadSyntaxError(list.location, const <String>[
            "data constructor definition",
            "deriving clause"
          ]));
        }
      } else {
        return mod.error(BadSyntaxError(list.location,
            const <String>["data constructor definition", "deriving clause"]));
      }
    }
    deriving ??= <Name>[];
    return mod.datatype(name, constructors, deriving, location: list.location);
  }

  Mod typename(Atom head, SList list) {
    assert(head.value == "define-typename");
    // (define-typename name T)
    // or (define-typename (name q+) T
    if (list.length < 3 || list.length > 3) {
      if (list.length < 3) {
        return mod.error(BadSyntaxError(list.location.end));
      } else {
        return mod.error(BadSyntaxError(list[3].location));
      }
    } else {
      Pair<Name, List<Name>> name =
          expect<Sexp, Pair<Name, List<Name>>>(parameterisedTypeName, list[1]);
      Typ type = expect<Sexp, Typ>(datatype, list[2]);
      return mod.typename(name, type, location: list.location);
    }
  }

  Mod inclusion(Atom head, SList list) {
    assert(head.value == "open");
    throw "module inclusion is not yet implemented.";
    return null;
  }

  Mod signature(Atom colon, SList list) {
    assert(colon.value == ":");
    if (list.length < 3 || list.length > 3) {
      if (list.length < 3) {
        return mod.error(
            BadSyntaxError(list.location.end, const <String>["signature"]));
      } else {
        return mod.error(
            BadSyntaxError(list[3].location, <String>[list.closingBracket()]));
      }
    }

    // (: name T)
    if (list[1] is Atom) {
      Atom atom = list[1];
      Name name = expect<Atom, Name>(termName, atom);
      Typ type = expect<Sexp, Typ>(datatype, list[2]);
      return mod.signature(name, type, location: list.location);
    } else {
      return mod
          .error(BadSyntaxError(list[1].location, const <String>["signature"]));
    }
  }
}

class Typenames {
  static const String arrow = "->";
  static const String boolean = "Bool";
  static const String integer = "Int";
  static const String string = "String";
  static const String forall = "forall";
  static const String tuple = "*";

  static bool isBaseTypename(String typeName) {
    switch (typeName) {
      case Typenames.boolean:
      case Typenames.integer:
      case Typenames.string:
        return true;
      default:
        return false;
    }
  }
}

class TypeElaborator<Name, Typ>
    extends BaseElaborator<Typ, Name, Null, Null, Null, Typ> {
  TypeElaborator(NameAlgebra<Name> name, TypeAlgebra<Name, Typ> typ)
      : super(name, null, null, null, typ);

  Typ elaborate(Sexp sexp) {
    if (sexp is Atom) {
      Atom atom = sexp;
      return basicType(atom);
    } else if (sexp is SList) {
      SList list = sexp;
      return higherType(list);
    } else {
      return typ.error(BadSyntaxError(sexp.location, const <String>["type"]));
    }
  }

  Typ basicType(Atom atom) {
    assert(atom != null);
    Location loc = atom.location;
    String value = atom.value;
    switch (value) {
      case Typenames.boolean:
        return typ.boolean(location: loc);
      case Typenames.integer:
        return typ.integer(location: loc);
      case Typenames.string:
        return typ.string(location: loc);
      default:
        if (isValidTypeVariableName(value)) {
          Name name = expect<Atom, Name>(typeVariableName, atom);
          return typ.var_(name, location: loc);
        } else {
          // Must be a user-defined type (i.e. nullary type application).
          if (isValidTypeConstructorName(value)) {
            Name name = expect<Atom, Name>(typeName, atom);
            return typ.constr(name, <Typ>[], location: loc);
          } else {
            // Error: invalid type.
            return typ.error(BadSyntaxError(loc, const <String>["type"]));
          }
        }
    }
  }

  Typ higherType(SList list) {
    assert(list != null);
    if (list.length > 0 && list[0] is Atom) {
      Atom head = list[0];
      // Function type: (-> T* T).
      if (head.value == Typenames.arrow) {
        return functionType(head, list);
      }

      // Forall type: (forall id+ T).
      if (head.value == Typenames.forall) {
        return forallType(head, list);
      }

      // Tuple type: (* T*).
      if (head.value == Typenames.tuple) {
        return tupleType(head, list);
      }

      // Otherwise assume we got our hands on a type constructor.
      // Type constructor: (K T*).
      return typeConstructor(head, list);
    } else {
      // Error empty.
      return typ
          .error(BadSyntaxError(list.location.end, const <String>["type"]));
    }
  }

  Typ functionType(Atom arrow, SList list) {
    assert(arrow.value == Typenames.arrow);
    if (list.length < 2) {
      // Error: -> requires at least one argument.
      return typ.error(BadSyntaxError(list.location, const <String>["type"]));
    }

    if (list.length == 2) {
      // Nullary function.
      Typ codomain = elaborate(list[1]);
      return typ.arrow(<Typ>[], codomain, location: list.location);
    } else {
      // N-ary function.
      List<Typ> domain = new List<Typ>(list.length - 2);
      for (int i = 1; i < list.length - 1; i++) {
        domain.add(elaborate(list[i]));
      }
      Typ codomain = elaborate(list.last);
      return typ.arrow(domain, codomain, location: list.location);
    }
  }

  Typ forallType(Atom forall, SList list) {
    assert(forall.value == Typenames.forall);
    if (list.length < 3 || list.length > 3) {
      if (list.length < 3) {
        return typ.error(BadSyntaxError(list.location.end));
      } else {
        return typ.error(BadSyntaxError(list[3].location));
      }
    }

    if (list[1] is SList) {
      List<Name> qs = expectMany<SList, Name>(quantifier, list[1]);
      Typ type = elaborate(list[2]);
      return typ.forall(qs, type, location: list.location);
    } else {
      return typ.error(BadSyntaxError(
          list[1].location, const <String>["list of quantifiers"]));
    }
  }

  Typ typeConstructor(Atom head, SList list) {
    assert(list != null);
    Name constructorName = expect<Atom, Name>(typeName, head);
    List<Typ> typeArguments = expectManySelf<Sexp>(list, start: 1);

    return typ.constr(constructorName, typeArguments, location: list.location);
  }

  Typ tupleType(Atom head, SList list) {
    assert(head.value == Typenames.tuple);
    List<Typ> components = new List<Typ>(list.length - 1);
    for (int i = 1; i < list.length; i++) {
      components.add(elaborate(list[i]));
    }
    return typ.tuple(components, location: list.location);
  }
}

class SpecialForm {
  static const String ifthenelse = "if";
  static const String lambda = "lambda";
  static const String let = "let";
  static const String letstar = "let*";
  static const String match = "match";
  static const String tuple = ",";
  static const String typeAscription = ":";
  static Set<String> forms = Set.of(<String>[
    SpecialForm.lambda,
    SpecialForm.let,
    SpecialForm.letstar,
    SpecialForm.ifthenelse,
    SpecialForm.match,
    SpecialForm.tuple,
    SpecialForm.typeAscription
  ]);

  bool isSpecialForm(String name) {
    return SpecialForm.forms.contains(name);
  }
}

class ExpressionElaborator<Name, Exp, Pat, Typ>
    extends BaseElaborator<Exp, Name, Null, Exp, Pat, Typ> {
  ExpressionElaborator(
      NameAlgebra<Name> name,
      ExpAlgebra<Name, Exp, Pat, Typ> exp,
      PatternAlgebra<Name, Pat, Typ> pat,
      TypeAlgebra<Name, Typ> typ)
      : super(name, null, exp, pat, typ);

  Exp elaborate(Sexp sexp) {
    assert(sexp != null);
    if (sexp is Atom) {
      return basicExp(sexp);
    } else if (sexp is SList) {
      return compoundExp(sexp);
    } else if (sexp is StringLiteral) {
      return stringlit(sexp);
    } else {
      return exp
          .error(BadSyntaxError(sexp.location, const <String>["expression"]));
    }
  }

  Exp basicExp(Atom atom) {
    assert(atom != null);
    String value = atom.value;
    Location location = atom.location;

    // Might be an integer.
    if (isValidNumber(value)) {
      int denotation = int.parse(value);
      return exp.integer(denotation, location: location);
    }

    // Might be a boolean.
    if (isValidBoolean(value)) {
      return exp.boolean(denoteBool(value), location: location);
    }

    // Otherwise it is a variable.
    Name name = expect<Atom, Name>(termName, atom);
    return exp.var_(name, location: location);
  }

  Exp compoundExp(SList list) {
    assert(list != null);

    if (list.length == 0) {
      return exp.error(BadSyntaxError(
          list.location, const <String>["a special form", "an application"]));
    }

    // Might be a special form.
    if (list[0] is Atom) {
      Atom atom = list[0];
      switch (atom.value) {
        case SpecialForm.ifthenelse:
          return ifthenelse(atom, list);
        case SpecialForm.lambda:
          return lambda(atom, list);
        case SpecialForm.let:
        case SpecialForm.letstar:
          return let(atom, list);
        case SpecialForm.match:
          return match(atom, list);
        case SpecialForm.tuple:
          return tuple(atom, list);
        case SpecialForm.typeAscription:
          return typeAscription(atom, list);
        default:
          // Application.
          return application(list);
      }
    }
    return application(list);
  }

  Exp stringlit(StringLiteral lit) {
    assert(lit != null);
    // TODO: parse `lit.value'.
    return exp.string(lit.value, location: lit.location);
  }

  Exp ifthenelse(Atom head, SList list) {
    assert(head.value == SpecialForm.ifthenelse);
    // An if expression consists of exactly 3 constituents.
    if (list.length < 4) {
      return exp.error(BadSyntaxError(list.location.end,
          const <String>["a then-clause and an else-clause"]));
    }

    Exp condition = elaborate(list[1]);
    Exp thenBranch = elaborate(list[2]);
    Exp elseBranch = elaborate(list[3]);
    return exp.ifthenelse(condition, thenBranch, elseBranch,
        location: list.location);
  }

  Exp lambda(Atom lam, SList list) {
    assert(lam.value == SpecialForm.lambda);
    if (list.length < 3 || list.length > 3) {
      if (list.length < 3) {
        return exp.error(BadSyntaxError(list.location.end));
      } else {
        return exp.error(BadSyntaxError(list[3].location));
      }
    }

    if (list[1] is SList) {
      List<Pat> parameters = expectMany<Sexp, Pat>(pattern, list[1], start: 0);
      Exp body = elaborate(list[2]);
      return exp.lambda(parameters, body, location: list.location);
    } else {
      return exp.error(
          BadSyntaxError(list[1].location, const <String>["pattern list"]));
    }
  }

  Exp let(Atom head, SList list) {
    assert(head.value == SpecialForm.let || head.value == SpecialForm.letstar);

    if (list.length < 3) {
      return exp.error(BadSyntaxError(list.location.end, const <String>[
        "a non-empty sequence of bindings followed by a non-empty sequence of expressions"
      ]));
    }

    // The bindings in a let expression can either be bound in parallel or sequentially.
    BindingMethod method;
    switch (head.value) {
      case SpecialForm.let:
        method = BindingMethod.Parallel;
        break;
      case SpecialForm.letstar:
        method = BindingMethod.Sequential;
        break;
    }

    if (list[1] is SList) {
      SList bindings = list[1];
      List<Pair<Pat, Exp>> bindingPairs =
          new List<Pair<Pat, Exp>>(bindings.length);
      for (int i = 0; i < bindings.length; i++) {
        if (bindings[i] is SList) {
          SList binding = bindings[i];
          if (binding.length != 2) {
            return exp.error(
                BadSyntaxError(binding.location, const <String>["binding"]));
          } else {
            Pat binder = expect<Sexp, Pat>(pattern, binding[0]);
            Exp body = elaborate(binding[1]);
            bindingPairs.add(Pair<Pat, Exp>(binder, body));
          }
        } else {
          return exp.error(
              BadSyntaxError(bindings.location, const <String>["bindings"]));
        }
      }
      Exp body = elaborate(list[2]);
      return exp.let(bindingPairs, body,
          bindingMethod: method, location: list.location);
    } else {
      return exp.error(
          BadSyntaxError(list[1].location, const <String>["binding list"]));
    }
  }

  Exp match(Atom head, SList list) {
    assert(head.value == SpecialForm.match);
    if (list.length < 2) {
      return exp.error(BadSyntaxError(list.location.end, const <String>[
        "an expression followed by a sequence of match clauses"
      ]));
    }

    Exp scrutinee = elaborate(list[1]);
    // Parse any cases.
    List<Pair<Pat, Exp>> cases = new List<Pair<Pat, Exp>>(list.length - 2);
    for (int i = 2; i < list.length; i++) {
      // TODO.
    }
    return exp.match(scrutinee, cases, location: list.location);
  }

  Exp tuple(Atom head, SList list) {
    assert(head.value == SpecialForm.tuple);
    List<Exp> components = expectManySelf<Sexp>(list, start: 1);
    return exp.tuple(components, location: list.location);
  }

  Exp typeAscription(Atom head, SList list) {
    assert(head.value == SpecialForm.typeAscription);
    return null;
  }

  Exp application(SList list) {
    assert(list != null);
    Exp abstractor = elaborate(list[0]);
    List<Exp> arguments = expectManySelf<Sexp>(list, start: 1);
    return exp.apply(abstractor, arguments, location: list.location);
  }
}

class ErrorNode<T> {
  final T Function(LocatedError, {Location location}) _error;
  ErrorNode(this._error);

  T make(LocatedError err) {
    return _error(err, location: err.location);
  }
}

// class NameErrorNode implements ErrorNode<Name> {
//   static NameErrorNode _instance;

//   NameErrorNode._();
//   factory NameErrorNode() {
//     if (_instance == null) _instance = NameErrorNode._();
//     return _instance;
//   }

//   Name make(LocatedError err) {

//   }
// }