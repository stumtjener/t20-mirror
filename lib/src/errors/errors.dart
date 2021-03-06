// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library t20.errors;

import '../location.dart';
import '../unicode.dart' as unicode;
import '../utils.dart' show ListUtils;

abstract class T20Error {}

abstract class LocatedError implements T20Error {
  final Location location;

  LocatedError(this.location);
}

abstract class HasLength {
  int get length;
}

// Internal errors.
class InternalError {
  final String componentName;
  final Object unhandled;
  InternalError(this.componentName, this.unhandled);

  String toString() {
    return "internal error [$componentName]: $unhandled";
  }
}

void unhandled(String componentName, Object unhandled) {
  throw InternalError(componentName, unhandled);
}

// Syntax errors.
abstract class SyntaxError implements LocatedError, T20Error {}

class UnmatchedBracketError extends LocatedError implements SyntaxError {
  final int _unmatched;

  UnmatchedBracketError(this._unmatched, Location location) : super(location);

  String get unmatchedBracket => String.fromCharCode(_unmatched);

  String toString() {
    switch (_unmatched) {
      case unicode.LPAREN:
        return "Unmatched parenthesis";
      case unicode.LBRACE:
        return "Unmatched curly brace";
      case unicode.LBRACKET:
        return "Unmatched square bracket";
      default:
        throw ArgumentError(_unmatched.toString());
    }
  }
}

// Lexical errors.
abstract class LexicalError implements SyntaxError {}

class InvalidCharacterError extends LocatedError implements LexicalError {
  final int char;
  InvalidCharacterError(this.char, Location location) : super(location);

  String get character => String.fromCharCode(char);

  String toString() {
    return "Invalid character";
  }
}

class UnterminatedStringError extends LocatedError implements LexicalError {
  final List<int> _partialString;

  UnterminatedStringError(this._partialString, Location location)
      : super(location);

  String get unterminatedString => String.fromCharCodes(_partialString);

  String toString() {
    return "Unterminated string";
  }
}

class BadCharacterEscapeError extends LocatedError implements LexicalError {
  final List<int> _badEscape;

  BadCharacterEscapeError(this._badEscape, Location location) : super(location);

  String get badEscape => String.fromCharCodes(_badEscape);

  String toString() {
    return "Bad character escape";
  }
}

class InvalidUTF16SequenceError extends LocatedError implements LexicalError {
  final List<int> _invalid;

  InvalidUTF16SequenceError(this._invalid, Location location) : super(location);

  String get invalidSequence => String.fromCharCodes(_invalid);

  String toString() {
    return "Invalid UTF-16 character";
  }
}

// Elaboration errors.
abstract class ElaborationError implements T20Error {}

// This error is *never* suppose to occur.
class UnsupportedElaborationMethodError implements ElaborationError {
  final String elaboratorName;
  final String methodName;
  UnsupportedElaborationMethodError(this.elaboratorName, this.methodName);

  String toString() {
    return "Unsupported invocation of method '$methodName' elaborator '$elaboratorName'.";
  }
}

class InvalidTypeError extends LocatedError
    implements ElaborationError, HasLength {
  final String name;
  int get length => name.length;

  InvalidTypeError(this.name, Location location) : super(location);

  String toString() {
    return "Invalid type";
  }
}

class InvalidQuantifierError extends LocatedError
    implements ElaborationError, SyntaxError, HasLength {
  final String name;
  int get length => name.length;

  InvalidQuantifierError(this.name, Location location) : super(location);

  String toString() {
    return "Invalid quantifier";
  }
}

class EmptyQuantifierList extends LocatedError
    implements ElaborationError, SyntaxError {
  EmptyQuantifierList(Location location) : super(location);

  String toString() {
    return "Empty quantifier list";
  }
}

class ExpectedQuantifiersError extends LocatedError
    implements ElaborationError, SyntaxError {
  ExpectedQuantifiersError(Location location) : super(location);
  String toString() {
    return "Expected a single quantifier or a quantifier list.";
  }
}

class ExpectedQuantifierError extends LocatedError
    implements ElaborationError, SyntaxError {
  ExpectedQuantifierError(Location location) : super(location);
  String toString() {
    return "Expected a single quantifier.";
  }
}

class ExpectedValidTypeError extends LocatedError
    implements ElaborationError, SyntaxError {
  ExpectedValidTypeError(Location location) : super(location);

  String toString() {
    return "Expected a valid type name";
  }
}

class InvalidForallTypeError extends LocatedError
    implements ElaborationError, SyntaxError {
  InvalidForallTypeError(Location location) : super(location);

  String toString() {
    return "'forall' must be followed by a non-empty list of quantifiers and a type.";
  }
}

class InvalidFunctionTypeError extends LocatedError
    implements ElaborationError, SyntaxError {
  InvalidFunctionTypeError(Location location) : super(location);

  String toString() {
    return "A function type constructor '->' must be followed by a non-empty sequence of types.";
  }
}

class NakedExpressionAtToplevelError extends LocatedError
    implements ElaborationError, SyntaxError {
  NakedExpressionAtToplevelError(Location location) : super(location);

  String toString() {
    return "Naked expression at top level";
  }
}

class EmptyListAtToplevelError extends LocatedError
    implements ElaborationError, SyntaxError {
  EmptyListAtToplevelError(Location location) : super(location);

  String toString() {
    return "Empty list expression at top level";
  }
}

class BadSyntaxError extends LocatedError
    implements ElaborationError, SyntaxError {
  final List<String> expectations;

  BadSyntaxError(Location location, [this.expectations = null])
      : super(location);

  String toString() {
    if (expectations == null || expectations.length == 0) {
      return "Bad syntax";
    } else if (expectations.length > 1) {
      String expectedSyntax = ListUtils.insertBeforeLast<String>(
              "or ", ListUtils.intersperse<String>(", ", expectations))
          .join();
      return "Bad syntax. Expected $expectedSyntax";
    } else {
      return "Bad syntax. Expected ${expectations[0]}";
    }
  }
}

class DuplicateTypeSignatureError extends LocatedError
    implements ElaborationError, HasLength {
  final String name;
  int get length => name.length;

  DuplicateTypeSignatureError(this.name, Location location) : super(location);

  String toString() {
    return "Duplicate type signature for '$name'";
  }
}

class MultipleDeclarationsError extends LocatedError
    implements ElaborationError, HasLength {
  final String name;
  int get length => name.length;

  MultipleDeclarationsError(this.name, Location location) : super(location);

  String toString() {
    return "Multiple declarations of '$name'";
  }
}

class MultipleDefinitionsError extends LocatedError
    implements ElaborationError, HasLength {
  final String name;
  int get length => name.length;

  MultipleDefinitionsError(this.name, Location location) : super(location);

  String toString() {
    return "Multiple definitions of '$name'";
  }
}

class InvalidIdentifierError extends LocatedError
    implements SyntaxError, ElaborationError, HasLength {
  final String name;

  int get length => name.length;

  InvalidIdentifierError(this.name, Location location) : super(location);

  String toString() {
    return "Invalid identifier '$name'";
  }
}

class MissingAccompanyingSignatureError extends LocatedError
    implements ElaborationError, HasLength {
  final String name;
  int get length => name.length;

  MissingAccompanyingSignatureError(this.name, Location location)
      : super(location);

  String toString() {
    return "The top level definition '$name' is missing an accompanying signature";
  }
}

class MissingAccompanyingDefinitionError extends LocatedError
    implements ElaborationError, HasLength {
  final String name;
  int get length => name.length;

  MissingAccompanyingDefinitionError(this.name, Location location)
      : super(location);

  String toString() {
    return "The signature '$name' is missing an accompanying definition";
  }
}

class MultipleDerivingError extends LocatedError
    implements ElaborationError, HasLength {
  int get length => "derive!".length;
  MultipleDerivingError(Location location) : super(location);

  String toString() {
    return "Multiple deriving clauses";
  }
}

class UnboundNameError extends LocatedError
    implements ElaborationError, HasLength {
  final String name;
  int get length => name.length;

  UnboundNameError(this.name, Location location) : super(location);

  String toString() {
    return "Unbound value '$name'";
  }
}

class UnboundConstructorError extends UnboundNameError {
  UnboundConstructorError(String name, Location location)
      : super(name, location);
  String toString() {
    return "Unbound constructor '$name'";
  }
}

class UnboundModuleError extends UnboundNameError {
  UnboundModuleError(String name, Location location) : super(name, location);

  String toString() => "Unbound module '$name'";
}

class UnsupportedDerivableError extends UnboundNameError {
  UnsupportedDerivableError(String name, Location location)
      : super(name, location);

  String toString() => "Cannot derive '$name'";
}

class StubInNonVirtualModuleError extends UnboundNameError {
  StubInNonVirtualModuleError(String name, Location location)
      : super(name, location);

  String toString() => "Stubs cannot occur in non-virtual modules";
}

// Type errors.
abstract class TypeError implements T20Error {}

class InstantiationError extends TypeError {
  final int numQuantifiers;
  final int numArguments;

  InstantiationError(this.numQuantifiers, this.numArguments);

  String toString() {
    return "Instantiation error: arity mismatch: expected $numQuantifiers type argument(s), but got $numArguments";
  }
}

class UnificationError extends TypeError {}

class SkolemEscapeError extends UnificationError {
  final String name;
  SkolemEscapeError(this.name);

  String toString() {
    return "The existential $name escapes its scope";
  }
}

class OccursError extends UnificationError {
  final String variable;
  final String type;

  OccursError(this.variable, this.type) : super();

  String toString() {
    return "Occurs check: the existential $variable occurs in $type";
  }
}

class ConstructorMismatchError extends UnificationError {
  final String left;
  final String right;

  ConstructorMismatchError(this.left, this.right) : super();

  String toString() {
    return "The constructor '$left' does not subsume '$right'";
  }
}

class TypeSignatureMismatchError extends LocatedError implements TypeError {
  final int expected;
  final int actual;

  TypeSignatureMismatchError(this.expected, this.actual, Location location)
      : super(location);

  String toString() {
    return "The declaration declares $expected parameters, whilst the implementation takes $actual parameters";
  }
}

class TypeExpectationError extends LocatedError implements TypeError {
  // TODO include expectation and actual.
  TypeExpectationError(Location location) : super(location);

  String toString() {
    return "Type error";
  }
}

class ArityMismatchError extends LocatedError implements TypeError {
  final int expected;
  final int actual;
  ArityMismatchError(this.expected, this.actual, Location location)
      : super(location);

  String toString() {
    if (actual > expected) {
      return "Arity mismatch: too many arguments";
    } else {
      return "Arity mismatch: too few arguments";
    }
  }
}

class CheckTupleError extends LocatedError implements TypeError {
  final String type;

  CheckTupleError(this.type, Location location) : super(location);

  String toString() {
    return "The expression is expected to have type '$type'";
  }
}

class CheckTuplePatternError extends CheckTupleError {
  CheckTuplePatternError(String type, Location location)
      : super(type, location);

  String toString() {
    return "The pattern is expected to have type '$type'";
  }
}

class SubsumptionError extends TypeError {
  final String lhs;
  final String rhs;

  SubsumptionError(this.lhs, this.rhs);

  String toString() => "$lhs is not a subtype of $rhs";
}

class LocatedSubsumptionError extends LocatedError implements TypeError {
  final TypeError error;

  LocatedSubsumptionError(this.error, Location location) : super(location);

  String toString() => error.toString();
}

class KernelModuleNotLoadedError extends LocatedError implements TypeError {
  KernelModuleNotLoadedError(Location location) : super(location);

  String toString() =>
      "Cannot type the main function as the Kernel module has not been loaded yet.";
}

class ObviousPatternError extends LocatedError implements TypeError {
  final String scrutineeType;

  ObviousPatternError(this.scrutineeType, Location location) : super(location);

  String toString() => "It is non-obvious what to do about $scrutineeType";
}

class CodeGenerationError extends T20Error {
  String toString() => "Code generation failed";
}

class CannotLocateForeignFunctionError extends LocatedError
    implements CodeGenerationError {
  final String uri;

  CannotLocateForeignFunctionError(this.uri, Location location)
      : super(location);

  String toString() =>
      "Failed to locate the foreign function using path `$uri'";
}

class InvalidForeignUriError extends LocatedError implements CodeGenerationError {
  final String uri;

  InvalidForeignUriError(this.uri, Location location)
      : super(location);

  String toString() =>
      "A foreign uri must at least specify a library and a (procedure) target.";
}
