// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library t20_runtime;

import 'dart:io' show exit, File, IOSink, stderr, stdout, Platform;
import 'package:kernel/ast.dart'
    show
        Arguments,
        AsExpression,
        AssertBlock,
        AssertInitializer,
        AssertStatement,
        AwaitExpression,
        BasicLiteral,
        Block,
        BoolConstant,
        BoolLiteral,
        BottomType,
        BreakStatement,
        Catch,
        CheckLibraryIsLoaded,
        Class,
        Combinator,
        Component,
        ConditionalExpression,
        Constant,
        ConstantExpression,
        Constructor,
        ConstructorInvocation,
        ContinueSwitchStatement,
        DartType,
        DirectMethodInvocation,
        DirectPropertyGet,
        DirectPropertySet,
        DoStatement,
        DoubleConstant,
        DoubleLiteral,
        DynamicType,
        EmptyStatement,
        Expression,
        ExpressionStatement,
        Field,
        FieldInitializer,
        ForInStatement,
        ForStatement,
        FunctionDeclaration,
        FunctionExpression,
        FunctionNode,
        FunctionType,
        IfStatement,
        Initializer,
        InstanceConstant,
        Instantiation,
        IntConstant,
        InterfaceType,
        IntLiteral,
        InvalidExpression,
        InvalidInitializer,
        InvalidType,
        IsExpression,
        LabeledStatement,
        Let,
        Library,
        LibraryDependency,
        LibraryPart,
        ListConstant,
        ListLiteral,
        LoadLibrary,
        LocalInitializer,
        LogicalExpression,
        MapConstant,
        MapEntry,
        MapLiteral,
        Member,
        MethodInvocation,
        Name,
        NamedExpression,
        NamedType,
        Node,
        Not,
        NullConstant,
        NullLiteral,
        PartialInstantiationConstant,
        Procedure,
        PropertyGet,
        PropertySet,
        RedirectingFactoryConstructor,
        RedirectingInitializer,
        Rethrow,
        ReturnStatement,
        SetLiteral,
        Statement,
        StaticGet,
        StaticInvocation,
        StaticSet,
        StringConcatenation,
        StringConstant,
        StringLiteral,
        SuperInitializer,
        SuperMethodInvocation,
        SuperPropertyGet,
        SuperPropertySet,
        Supertype,
        SwitchCase,
        SwitchStatement,
        SymbolConstant,
        SymbolLiteral,
        TearOffConstant,
        ThisExpression,
        Throw,
        TreeNode,
        TryCatch,
        TryFinally,
        Typedef,
        TypedefType,
        TypeLiteral,
        TypeLiteralConstant,
        TypeParameter,
        TypeParameterType,
        UnevaluatedConstant,
        VariableDeclaration,
        VariableGet,
        VariableSet,
        VoidType,
        WhileStatement,
        YieldStatement;
import 'package:kernel/binary/ast_from_binary.dart';
import 'package:kernel/binary/ast_to_binary.dart';
import 'package:kernel/visitor.dart'
    show ExpressionVisitor1, StatementVisitor1, DartTypeVisitor1, Visitor;

// Error classes.
class PatternMatchFailure extends Object {
  String message;
  PatternMatchFailure([this.message]) : super();

  String toString() => message ?? "Pattern match failure";
}

class T20Error extends Object {
  Object error;
  T20Error(this.error) : super();

  String toString() => error?.toString ?? "error";
}

class Obvious extends Object {
  final int id;
  Obvious([this.id = 2]) : super();

  String toString() => "Obvious($id)";
}

A error<A>(String message) => throw T20Error(message);

// Finite iteration / corecursion.
R iterate<R>(int m, R Function(R) f, R z) {
  int n = m;
  R result = z;
  for (int i = 0; i < n; i++) {
    result = f(result);
  }
  return result;
}

// Show.
String show(dynamic a) => a.toString();

// Dart list module.
void dart_list_add<A>(A x, List<A> xs) => xs.add(x);
void dart_list_set<A>(int i, A x, List<A> xs) => xs[i] = x;
A dart_list_nth<A>(int i, List<A> xs) => xs[i];
int dart_list_length<A>(List<A> xs) => xs.length;
List<B> dart_list_map<A, B>(B Function(A) f, List<A> xs) => xs.map(f).toList();
B dart_list_fold<A, B>(B Function(B, A) f, B z, List<A> xs) => xs.fold(z, f);

// String module.
int string_length(String str) => str.length;
String string_concat(String a, String b) => "$a$b";
bool string_equals(String a, String b) => a.compareTo(b) == 0;
bool string_less(String a, String b) => a.compareTo(b) < 0;
bool string_greater(String a, String b) => a.compareTo(b) > 0;

// Argument parser.
void _reportError(String message) {
  String compilerName = Platform.script.pathSegments.last;
  stderr.writeln("\x1B[1m${compilerName}: \x1B[31;1merror:\x1B[0m $message");
}

class Settings {
  final bool showHelp;
  final String target;
  final String source;
  Settings(this.showHelp, this.source, this.target);
}

Settings parseArgs(List<String> args) {
  bool error = false;
  bool showHelp = false;
  String target = "a.transformed.dill";
  String source;
  for (int i = 0; i < args.length; i++) {
    String arg = args[i];
    if (arg.startsWith("-")) {
      if (arg.compareTo("--help") == 0 || arg.compareTo("-h") == 0) {
        showHelp = true;
        break;
      } else if (arg.compareTo("-o") == 0) {
        if (i + 1 < args.length) {
          ++i;
          target = args[i];
          continue;
        } else {
          _reportError("missing filename after `\x1B[1m-o\x1B[0m'.");
          error = true;
          continue;
        }
      } else {
        _reportError("Unknown option `\x1B[1m$arg\x1B[0m'.");
        error = true;
        continue;
      }
    }

    if (source == null) {
      source = arg;
    } else {
      _reportError("multiple input files given.");
      error = true;
    }
  }

  if (!showHelp && source == null) {
    _reportError("no input file given.");
    error = true;
  }

  if (error) {
    stderr.writeln("compilation terminated.");
    exit(1);
  }

  return Settings(showHelp, source, target);
}

void showHelp(String t20Version, String sdkVersion, String buildDate) {
  String compilerName = Platform.script.pathSegments.last;
  stdout.writeln("usage: $compilerName [ -h  | -o <file> ] FILE");
  stdout.writeln("This program is a Kernel-to-Kernel transformation compiler.");
  stdout.writeln("");
  stdout.writeln("Options:");
  stdout.writeln("-h, --help                      Displays this help message.");
  stdout
      .writeln("-o <file>                       Place the output into <file>.");
  stdout.writeln(
      "                                (defaults to \"a.transformed.dill\")");
  stdout.writeln("");
  stdout.writeln(
      "This compiler was built by T20, version $t20Version,\nusing the Dart SDK $sdkVersion\non date $buildDate (UTC).");
}

// Main driver.
void t20main(Component Function(Component) main, List<String> args,
    String t20Version, String sdkVersion, String buildDate) async {
  Settings settings = parseArgs(args);
  if (settings.showHelp) {
    showHelp(t20Version, sdkVersion, buildDate);
  } else {
    String file = settings.source;

    // Read the source component.
    Component c = Component();
    BinaryBuilder(File(file).readAsBytesSync()).readSingleFileComponent(c);

    // Run the transformation.
    try {
      c = main(c);
    } on PatternMatchFailure catch (e) {
      _reportError(e.toString());
      exit(1);
    } on T20Error catch (e) {
      _reportError(e.toString());
      exit(1);
    } catch (e, s) {
      stderr.writeln("fatal error: $e");
      stderr.writeln(s.toString());
      exit(1);
    }

    // Write the resulting component.
    IOSink sink = File(settings.target).openWrite();
    BinaryPrinter(sink).writeComponentFile(c);
    await sink.flush();
    await sink.close();
  }
}

void t20mainDemo(dynamic Function() main) {
  try {
    main();
  } on PatternMatchFailure catch (e) {
    stderr.writeln(e.toString());
    exit(1);
  } on T20Error catch (e) {
    stderr.writeln(e.toString());
    exit(1);
  } catch (e, s) {
    stderr.writeln("fatal error: $e");
    stderr.writeln(s.toString());
    exit(1);
  }
}

// void main(List<String> args) => t20main(<main_from_source>, args);

//=== Kernel Eliminators, match closures, and recursors.
class KernelMatchClosure<R> implements Visitor<R> {
  final int id;

  const KernelMatchClosure([this.id = 2]);

  R defaultCase(Node node) => throw PatternMatchFailure();

  @override
  R defaultExpression(Expression node) {
    throw new UnsupportedError("defaultExpression");
  }

  @override
  R visitNamedType(NamedType node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitSupertype(Supertype node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitName(Name node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitRedirectingFactoryConstructorReference(
      RedirectingFactoryConstructor node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitProcedureReference(Procedure node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitConstructorReference(Constructor node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitFieldReference(Field node) {
    throw new PatternMatchFailure();
  }

  @override
  R defaultMemberReference(Member node) {
    throw new UnsupportedError("defaultMemberReference");
  }

  @override
  R visitUnevaluatedConstantReference(UnevaluatedConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitTypeLiteralConstantReference(TypeLiteralConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitTearOffConstantReference(TearOffConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitPartialInstantiationConstantReference(
      PartialInstantiationConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitInstanceConstantReference(InstanceConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitListConstantReference(ListConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitMapConstantReference(MapConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitSymbolConstantReference(SymbolConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitStringConstantReference(StringConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitDoubleConstantReference(DoubleConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitIntConstantReference(IntConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitBoolConstantReference(BoolConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitNullConstantReference(NullConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R defaultConstantReference(Constant node) {
    throw new UnsupportedError("defaultConstantReference");
  }

  @override
  R visitTypedefReference(Typedef node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitClassReference(Class node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitUnevaluatedConstant(UnevaluatedConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitTypeLiteralConstant(TypeLiteralConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitTearOffConstant(TearOffConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitPartialInstantiationConstant(PartialInstantiationConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitInstanceConstant(InstanceConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitListConstant(ListConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitMapConstant(MapConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitSymbolConstant(SymbolConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitStringConstant(StringConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitDoubleConstant(DoubleConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitIntConstant(IntConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitBoolConstant(BoolConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitNullConstant(NullConstant node) {
    throw new PatternMatchFailure();
  }

  @override
  R defaultConstant(Constant node) {
    throw new UnsupportedError("defaultConstant");
  }

  @override
  R visitTypedefType(TypedefType node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitTypeParameterType(TypeParameterType node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitFunctionType(FunctionType node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitInterfaceType(InterfaceType node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitBottomType(BottomType node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitVoidType(VoidType node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitDynamicType(DynamicType node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitInvalidType(InvalidType node) {
    throw new PatternMatchFailure();
  }

  @override
  R defaultDartType(DartType node) {
    throw new UnsupportedError("defaultDartType");
  }

  @override
  R defaultTreeNode(TreeNode node) {
    throw new UnsupportedError("defaultTreeNode");
  }

  @override
  R defaultNode(Node node) {
    throw new UnsupportedError("defaultNode");
  }

  @override
  R visitComponent(Component node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitMapEntry(MapEntry node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitCatch(Catch node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitSwitchCase(SwitchCase node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitNamedExpression(NamedExpression node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitArguments(Arguments node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitFunctionNode(FunctionNode node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitTypeParameter(TypeParameter node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitTypedef(Typedef node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitLibraryPart(LibraryPart node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitCombinator(Combinator node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitLibraryDependency(LibraryDependency node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitLibrary(Library node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitAssertInitializer(AssertInitializer node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitLocalInitializer(LocalInitializer node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitRedirectingInitializer(RedirectingInitializer node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitSuperInitializer(SuperInitializer node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitFieldInitializer(FieldInitializer node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitInvalidInitializer(InvalidInitializer node) {
    throw new PatternMatchFailure();
  }

  @override
  R defaultInitializer(Initializer node) {
    throw new UnsupportedError("defaultInitializer");
  }

  @override
  R visitClass(Class node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitRedirectingFactoryConstructor(RedirectingFactoryConstructor node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitField(Field node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitProcedure(Procedure node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitConstructor(Constructor node) {
    throw new PatternMatchFailure();
  }

  @override
  R defaultMember(Member node) {
    throw new UnsupportedError("defaultMember");
  }

  @override
  R visitFunctionDeclaration(FunctionDeclaration node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitVariableDeclaration(VariableDeclaration node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitYieldStatement(YieldStatement node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitTryFinally(TryFinally node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitTryCatch(TryCatch node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitReturnStatement(ReturnStatement node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitIfStatement(IfStatement node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitContinueSwitchStatement(ContinueSwitchStatement node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitSwitchStatement(SwitchStatement node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitForInStatement(ForInStatement node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitForStatement(ForStatement node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitDoStatement(DoStatement node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitWhileStatement(WhileStatement node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitBreakStatement(BreakStatement node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitLabeledStatement(LabeledStatement node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitAssertStatement(AssertStatement node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitEmptyStatement(EmptyStatement node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitAssertBlock(AssertBlock node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitBlock(Block node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitExpressionStatement(ExpressionStatement node) {
    throw new PatternMatchFailure();
  }

  @override
  R defaultStatement(Statement node) {
    throw new UnsupportedError("defaultStatement");
  }

  @override
  R visitCheckLibraryIsLoaded(CheckLibraryIsLoaded node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitLoadLibrary(LoadLibrary node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitInstantiation(Instantiation node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitLet(Let node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitNullLiteral(NullLiteral node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitBoolLiteral(BoolLiteral node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitDoubleLiteral(DoubleLiteral node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitIntLiteral(IntLiteral node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitStringLiteral(StringLiteral node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitConstantExpression(ConstantExpression node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitFunctionExpression(FunctionExpression node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitAwaitExpression(AwaitExpression node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitMapLiteral(MapLiteral node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitSetLiteral(SetLiteral node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitListLiteral(ListLiteral node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitThrow(Throw node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitRethrow(Rethrow node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitThisExpression(ThisExpression node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitTypeLiteral(TypeLiteral node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitSymbolLiteral(SymbolLiteral node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitAsExpression(AsExpression node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitIsExpression(IsExpression node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitStringConcatenation(StringConcatenation node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitConditionalExpression(ConditionalExpression node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitLogicalExpression(LogicalExpression node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitNot(Not node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitConstructorInvocation(ConstructorInvocation node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitStaticInvocation(StaticInvocation node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitSuperMethodInvocation(SuperMethodInvocation node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitDirectMethodInvocation(DirectMethodInvocation node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitMethodInvocation(MethodInvocation node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitStaticSet(StaticSet node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitStaticGet(StaticGet node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitSuperPropertySet(SuperPropertySet node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitSuperPropertyGet(SuperPropertyGet node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitDirectPropertySet(DirectPropertySet node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitDirectPropertyGet(DirectPropertyGet node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitPropertySet(PropertySet node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitPropertyGet(PropertyGet node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitVariableSet(VariableSet node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitVariableGet(VariableGet node) {
    throw new PatternMatchFailure();
  }

  @override
  R visitInvalidExpression(InvalidExpression node) {
    throw new PatternMatchFailure();
  }

  @override
  R defaultBasicLiteral(BasicLiteral node) {
    throw new UnsupportedError("defaultBasicLiteral");
  }
}

class KernelEliminator<R> implements Visitor<R> {
  final KernelMatchClosure<R> match;

  const KernelEliminator(this.match);

  R visit(Node node) {
    R result;
    try {
      result = node.accept(match);
    } on PatternMatchFailure catch (e) {
      try {
        result = match.defaultCase(node);
      } on PatternMatchFailure {
        throw T20Error(e);
      } on Obvious catch (e) {
        if (e.id == match.id) {
          rethrow;
        } else {
          throw T20Error(e);
        }
      } catch (e) {
        throw T20Error(e);
      }
    } catch (e) {
      throw T20Error(e);
    }

    if (result == null) {
      throw "fisk";
    }
    return result;
  }

  @override
  R defaultExpression(Expression node) {
    throw new UnsupportedError("defaultExpression");
  }

  @override
  R visitNamedType(NamedType node) {
    return visit(node);
  }

  @override
  R visitSupertype(Supertype node) {
    return visit(node);
  }

  @override
  R visitName(Name node) {
    return visit(node);
  }

  @override
  R visitRedirectingFactoryConstructorReference(
      RedirectingFactoryConstructor node) {
    return visit(node);
  }

  @override
  R visitProcedureReference(Procedure node) {
    return visit(node);
  }

  @override
  R visitConstructorReference(Constructor node) {
    return visit(node);
  }

  @override
  R visitFieldReference(Field node) {
    return visit(node);
  }

  @override
  R defaultMemberReference(Member node) {
    throw new UnsupportedError("defaultMemberReference");
  }

  @override
  R visitUnevaluatedConstantReference(UnevaluatedConstant node) {
    return visit(node);
  }

  @override
  R visitTypeLiteralConstantReference(TypeLiteralConstant node) {
    return visit(node);
  }

  @override
  R visitTearOffConstantReference(TearOffConstant node) {
    return visit(node);
  }

  @override
  R visitPartialInstantiationConstantReference(
      PartialInstantiationConstant node) {
    return visit(node);
  }

  @override
  R visitInstanceConstantReference(InstanceConstant node) {
    return visit(node);
  }

  @override
  R visitListConstantReference(ListConstant node) {
    return visit(node);
  }

  @override
  R visitMapConstantReference(MapConstant node) {
    return visit(node);
  }

  @override
  R visitSymbolConstantReference(SymbolConstant node) {
    return visit(node);
  }

  @override
  R visitStringConstantReference(StringConstant node) {
    return visit(node);
  }

  @override
  R visitDoubleConstantReference(DoubleConstant node) {
    return visit(node);
  }

  @override
  R visitIntConstantReference(IntConstant node) {
    return visit(node);
  }

  @override
  R visitBoolConstantReference(BoolConstant node) {
    return visit(node);
  }

  @override
  R visitNullConstantReference(NullConstant node) {
    return visit(node);
  }

  @override
  R defaultConstantReference(Constant node) {
    throw new UnsupportedError("defaultConstantReference");
  }

  @override
  R visitTypedefReference(Typedef node) {
    return visit(node);
  }

  @override
  R visitClassReference(Class node) {
    return visit(node);
  }

  @override
  R visitUnevaluatedConstant(UnevaluatedConstant node) {
    return visit(node);
  }

  @override
  R visitTypeLiteralConstant(TypeLiteralConstant node) {
    return visit(node);
  }

  @override
  R visitTearOffConstant(TearOffConstant node) {
    return visit(node);
  }

  @override
  R visitPartialInstantiationConstant(PartialInstantiationConstant node) {
    return visit(node);
  }

  @override
  R visitInstanceConstant(InstanceConstant node) {
    return visit(node);
  }

  @override
  R visitListConstant(ListConstant node) {
    return visit(node);
  }

  @override
  R visitMapConstant(MapConstant node) {
    return visit(node);
  }

  @override
  R visitSymbolConstant(SymbolConstant node) {
    return visit(node);
  }

  @override
  R visitStringConstant(StringConstant node) {
    return visit(node);
  }

  @override
  R visitDoubleConstant(DoubleConstant node) {
    return visit(node);
  }

  @override
  R visitIntConstant(IntConstant node) {
    return visit(node);
  }

  @override
  R visitBoolConstant(BoolConstant node) {
    return visit(node);
  }

  @override
  R visitNullConstant(NullConstant node) {
    return visit(node);
  }

  @override
  R defaultConstant(Constant node) {
    throw new UnsupportedError("defaultConstant");
  }

  @override
  R visitTypedefType(TypedefType node) {
    return visit(node);
  }

  @override
  R visitTypeParameterType(TypeParameterType node) {
    return visit(node);
  }

  @override
  R visitFunctionType(FunctionType node) {
    return visit(node);
  }

  @override
  R visitInterfaceType(InterfaceType node) {
    return visit(node);
  }

  @override
  R visitBottomType(BottomType node) {
    return visit(node);
  }

  @override
  R visitVoidType(VoidType node) {
    return visit(node);
  }

  @override
  R visitDynamicType(DynamicType node) {
    return visit(node);
  }

  @override
  R visitInvalidType(InvalidType node) {
    return visit(node);
  }

  @override
  R defaultDartType(DartType node) {
    throw new UnsupportedError("defaultDartType");
  }

  @override
  R defaultTreeNode(TreeNode node) {
    throw new UnsupportedError("defaultTreeNode");
  }

  @override
  R defaultNode(Node node) {
    throw new UnsupportedError("defaultNode");
  }

  @override
  R visitComponent(Component node) {
    return visit(node);
  }

  @override
  R visitMapEntry(MapEntry node) {
    return visit(node);
  }

  @override
  R visitCatch(Catch node) {
    return visit(node);
  }

  @override
  R visitSwitchCase(SwitchCase node) {
    return visit(node);
  }

  @override
  R visitNamedExpression(NamedExpression node) {
    return visit(node);
  }

  @override
  R visitArguments(Arguments node) {
    return visit(node);
  }

  @override
  R visitFunctionNode(FunctionNode node) {
    return visit(node);
  }

  @override
  R visitTypeParameter(TypeParameter node) {
    return visit(node);
  }

  @override
  R visitTypedef(Typedef node) {
    return visit(node);
  }

  @override
  R visitLibraryPart(LibraryPart node) {
    return visit(node);
  }

  @override
  R visitCombinator(Combinator node) {
    return visit(node);
  }

  @override
  R visitLibraryDependency(LibraryDependency node) {
    return visit(node);
  }

  @override
  R visitLibrary(Library node) {
    return visit(node);
  }

  @override
  R visitAssertInitializer(AssertInitializer node) {
    return visit(node);
  }

  @override
  R visitLocalInitializer(LocalInitializer node) {
    return visit(node);
  }

  @override
  R visitRedirectingInitializer(RedirectingInitializer node) {
    return visit(node);
  }

  @override
  R visitSuperInitializer(SuperInitializer node) {
    return visit(node);
  }

  @override
  R visitFieldInitializer(FieldInitializer node) {
    return visit(node);
  }

  @override
  R visitInvalidInitializer(InvalidInitializer node) {
    return visit(node);
  }

  @override
  R defaultInitializer(Initializer node) {
    throw new UnsupportedError("defaultInitializer");
  }

  @override
  R visitClass(Class node) {
    return visit(node);
  }

  @override
  R visitRedirectingFactoryConstructor(RedirectingFactoryConstructor node) {
    return visit(node);
  }

  @override
  R visitField(Field node) {
    return visit(node);
  }

  @override
  R visitProcedure(Procedure node) {
    return visit(node);
  }

  @override
  R visitConstructor(Constructor node) {
    return visit(node);
  }

  @override
  R defaultMember(Member node) {
    throw new UnsupportedError("defaultMember");
  }

  @override
  R visitFunctionDeclaration(FunctionDeclaration node) {
    return visit(node);
  }

  @override
  R visitVariableDeclaration(VariableDeclaration node) {
    return visit(node);
  }

  @override
  R visitYieldStatement(YieldStatement node) {
    return visit(node);
  }

  @override
  R visitTryFinally(TryFinally node) {
    return visit(node);
  }

  @override
  R visitTryCatch(TryCatch node) {
    return visit(node);
  }

  @override
  R visitReturnStatement(ReturnStatement node) {
    return visit(node);
  }

  @override
  R visitIfStatement(IfStatement node) {
    return visit(node);
  }

  @override
  R visitContinueSwitchStatement(ContinueSwitchStatement node) {
    return visit(node);
  }

  @override
  R visitSwitchStatement(SwitchStatement node) {
    return visit(node);
  }

  @override
  R visitForInStatement(ForInStatement node) {
    return visit(node);
  }

  @override
  R visitForStatement(ForStatement node) {
    return visit(node);
  }

  @override
  R visitDoStatement(DoStatement node) {
    return visit(node);
  }

  @override
  R visitWhileStatement(WhileStatement node) {
    return visit(node);
  }

  @override
  R visitBreakStatement(BreakStatement node) {
    return visit(node);
  }

  @override
  R visitLabeledStatement(LabeledStatement node) {
    return visit(node);
  }

  @override
  R visitAssertStatement(AssertStatement node) {
    return visit(node);
  }

  @override
  R visitEmptyStatement(EmptyStatement node) {
    return visit(node);
  }

  @override
  R visitAssertBlock(AssertBlock node) {
    return visit(node);
  }

  @override
  R visitBlock(Block node) {
    return visit(node);
  }

  @override
  R visitExpressionStatement(ExpressionStatement node) {
    return visit(node);
  }

  @override
  R defaultStatement(Statement node) {
    throw new UnsupportedError("defaultStatement");
  }

  @override
  R visitCheckLibraryIsLoaded(CheckLibraryIsLoaded node) {
    return visit(node);
  }

  @override
  R visitLoadLibrary(LoadLibrary node) {
    return visit(node);
  }

  @override
  R visitInstantiation(Instantiation node) {
    return visit(node);
  }

  @override
  R visitLet(Let node) {
    return visit(node);
  }

  @override
  R visitNullLiteral(NullLiteral node) {
    return visit(node);
  }

  @override
  R visitBoolLiteral(BoolLiteral node) {
    return visit(node);
  }

  @override
  R visitDoubleLiteral(DoubleLiteral node) {
    return visit(node);
  }

  @override
  R visitIntLiteral(IntLiteral node) {
    return visit(node);
  }

  @override
  R visitStringLiteral(StringLiteral node) {
    return visit(node);
  }

  @override
  R visitConstantExpression(ConstantExpression node) {
    return visit(node);
  }

  @override
  R visitFunctionExpression(FunctionExpression node) {
    return visit(node);
  }

  @override
  R visitAwaitExpression(AwaitExpression node) {
    return visit(node);
  }

  @override
  R visitMapLiteral(MapLiteral node) {
    return visit(node);
  }

  @override
  R visitSetLiteral(SetLiteral node) {
    return visit(node);
  }

  @override
  R visitListLiteral(ListLiteral node) {
    return visit(node);
  }

  @override
  R visitThrow(Throw node) {
    return visit(node);
  }

  @override
  R visitRethrow(Rethrow node) {
    return visit(node);
  }

  @override
  R visitThisExpression(ThisExpression node) {
    return visit(node);
  }

  @override
  R visitTypeLiteral(TypeLiteral node) {
    return visit(node);
  }

  @override
  R visitSymbolLiteral(SymbolLiteral node) {
    return visit(node);
  }

  @override
  R visitAsExpression(AsExpression node) {
    return visit(node);
  }

  @override
  R visitIsExpression(IsExpression node) {
    return visit(node);
  }

  @override
  R visitStringConcatenation(StringConcatenation node) {
    return visit(node);
  }

  @override
  R visitConditionalExpression(ConditionalExpression node) {
    return visit(node);
  }

  @override
  R visitLogicalExpression(LogicalExpression node) {
    return visit(node);
  }

  @override
  R visitNot(Not node) {
    return visit(node);
  }

  @override
  R visitConstructorInvocation(ConstructorInvocation node) {
    return visit(node);
  }

  @override
  R visitStaticInvocation(StaticInvocation node) {
    return visit(node);
  }

  @override
  R visitSuperMethodInvocation(SuperMethodInvocation node) {
    return visit(node);
  }

  @override
  R visitDirectMethodInvocation(DirectMethodInvocation node) {
    return visit(node);
  }

  @override
  R visitMethodInvocation(MethodInvocation node) {
    return visit(node);
  }

  @override
  R visitStaticSet(StaticSet node) {
    return visit(node);
  }

  @override
  R visitStaticGet(StaticGet node) {
    return visit(node);
  }

  @override
  R visitSuperPropertySet(SuperPropertySet node) {
    return visit(node);
  }

  @override
  R visitSuperPropertyGet(SuperPropertyGet node) {
    return visit(node);
  }

  @override
  R visitDirectPropertySet(DirectPropertySet node) {
    return visit(node);
  }

  @override
  R visitDirectPropertyGet(DirectPropertyGet node) {
    return visit(node);
  }

  @override
  R visitPropertySet(PropertySet node) {
    return visit(node);
  }

  @override
  R visitPropertyGet(PropertyGet node) {
    return visit(node);
  }

  @override
  R visitVariableSet(VariableSet node) {
    return visit(node);
  }

  @override
  R visitVariableGet(VariableGet node) {
    return visit(node);
  }

  @override
  R visitInvalidExpression(InvalidExpression node) {
    return visit(node);
  }

  @override
  R defaultBasicLiteral(BasicLiteral node) {
    throw new UnsupportedError("defaultBasicLiteral");
  }
}

abstract class MemberVisitor1<R, T> {
  const MemberVisitor1();

  R defaultMember(Member node, T arg) => null;

  R visitConstructor(Constructor node, T arg) => defaultMember(node, arg);
  R visitProcedure(Procedure node, T arg) => defaultMember(node, arg);
  R visitField(Field node, T arg) => defaultMember(node, arg);
  R visitRedirectingFactoryConstructor(
      RedirectingFactoryConstructor node, T arg) {
    return defaultMember(node, arg);
  }
}

abstract class InitializerVisitor1<R, T> {
  const InitializerVisitor1();

  R defaultInitializer(Initializer node, T arg) => null;

  R visitInvalidInitializer(InvalidInitializer node, T arg) =>
      defaultInitializer(node, arg);
  R visitFieldInitializer(FieldInitializer node, T arg) =>
      defaultInitializer(node, arg);
  R visitSuperInitializer(SuperInitializer node, T arg) =>
      defaultInitializer(node, arg);
  R visitRedirectingInitializer(RedirectingInitializer node, T arg) =>
      defaultInitializer(node, arg);
  R visitLocalInitializer(LocalInitializer node, T arg) =>
      defaultInitializer(node, arg);
  R visitAssertInitializer(AssertInitializer node, T arg) =>
      defaultInitializer(node, arg);
}

class TreeVisitor1<R, T>
    implements
        ExpressionVisitor1<R, T>,
        StatementVisitor1<R, T>,
        MemberVisitor1<R, T>,
        InitializerVisitor1<R, T> {
  const TreeVisitor1();

  R defaultTreeNode(TreeNode node, T arg) => null;

  // Expressions
  R defaultExpression(Expression node, T arg) => defaultTreeNode(node, arg);
  R defaultBasicLiteral(BasicLiteral node, T arg) =>
      defaultExpression(node, arg);
  R visitInvalidExpression(InvalidExpression node, T arg) =>
      defaultExpression(node, arg);
  R visitVariableGet(VariableGet node, T arg) => defaultExpression(node, arg);
  R visitVariableSet(VariableSet node, T arg) => defaultExpression(node, arg);
  R visitPropertyGet(PropertyGet node, T arg) => defaultExpression(node, arg);
  R visitPropertySet(PropertySet node, T arg) => defaultExpression(node, arg);
  R visitDirectPropertyGet(DirectPropertyGet node, T arg) =>
      defaultExpression(node, arg);
  R visitDirectPropertySet(DirectPropertySet node, T arg) =>
      defaultExpression(node, arg);
  R visitSuperPropertyGet(SuperPropertyGet node, T arg) =>
      defaultExpression(node, arg);
  R visitSuperPropertySet(SuperPropertySet node, T arg) =>
      defaultExpression(node, arg);
  R visitStaticGet(StaticGet node, T arg) => defaultExpression(node, arg);
  R visitStaticSet(StaticSet node, T arg) => defaultExpression(node, arg);
  R visitMethodInvocation(MethodInvocation node, T arg) =>
      defaultExpression(node, arg);
  R visitDirectMethodInvocation(DirectMethodInvocation node, T arg) =>
      defaultExpression(node, arg);
  R visitSuperMethodInvocation(SuperMethodInvocation node, T arg) =>
      defaultExpression(node, arg);
  R visitStaticInvocation(StaticInvocation node, T arg) =>
      defaultExpression(node, arg);
  R visitConstructorInvocation(ConstructorInvocation node, T arg) =>
      defaultExpression(node, arg);
  R visitNot(Not node, T arg) => defaultExpression(node, arg);
  R visitLogicalExpression(LogicalExpression node, T arg) =>
      defaultExpression(node, arg);
  R visitConditionalExpression(ConditionalExpression node, T arg) =>
      defaultExpression(node, arg);
  R visitStringConcatenation(StringConcatenation node, T arg) =>
      defaultExpression(node, arg);
  R visitIsExpression(IsExpression node, T arg) => defaultExpression(node, arg);
  R visitAsExpression(AsExpression node, T arg) => defaultExpression(node, arg);
  R visitSymbolLiteral(SymbolLiteral node, T arg) =>
      defaultExpression(node, arg);
  R visitTypeLiteral(TypeLiteral node, T arg) => defaultExpression(node, arg);
  R visitThisExpression(ThisExpression node, T arg) =>
      defaultExpression(node, arg);
  R visitRethrow(Rethrow node, T arg) => defaultExpression(node, arg);
  R visitThrow(Throw node, T arg) => defaultExpression(node, arg);
  R visitListLiteral(ListLiteral node, T arg) => defaultExpression(node, arg);
  R visitSetLiteral(SetLiteral node, T arg) => defaultExpression(node, arg);
  R visitMapLiteral(MapLiteral node, T arg) => defaultExpression(node, arg);
  R visitAwaitExpression(AwaitExpression node, T arg) =>
      defaultExpression(node, arg);
  R visitFunctionExpression(FunctionExpression node, T arg) =>
      defaultExpression(node, arg);
  R visitConstantExpression(ConstantExpression node, arg) =>
      defaultExpression(node, arg);
  R visitStringLiteral(StringLiteral node, T arg) =>
      defaultBasicLiteral(node, arg);
  R visitIntLiteral(IntLiteral node, T arg) => defaultBasicLiteral(node, arg);
  R visitDoubleLiteral(DoubleLiteral node, T arg) =>
      defaultBasicLiteral(node, arg);
  R visitBoolLiteral(BoolLiteral node, T arg) => defaultBasicLiteral(node, arg);
  R visitNullLiteral(NullLiteral node, T arg) => defaultBasicLiteral(node, arg);
  R visitLet(Let node, T arg) => defaultExpression(node, arg);
  R visitInstantiation(Instantiation node, T arg) =>
      defaultExpression(node, arg);
  R visitLoadLibrary(LoadLibrary node, T arg) => defaultExpression(node, arg);
  R visitCheckLibraryIsLoaded(CheckLibraryIsLoaded node, T arg) =>
      defaultExpression(node, arg);

  // Statements
  R defaultStatement(Statement node, T arg) => defaultTreeNode(node, arg);
  R visitExpressionStatement(ExpressionStatement node, T arg) =>
      defaultStatement(node, arg);
  R visitBlock(Block node, T arg) => defaultStatement(node, arg);
  R visitAssertBlock(AssertBlock node, T arg) => defaultStatement(node, arg);
  R visitEmptyStatement(EmptyStatement node, T arg) =>
      defaultStatement(node, arg);
  R visitAssertStatement(AssertStatement node, T arg) =>
      defaultStatement(node, arg);
  R visitLabeledStatement(LabeledStatement node, T arg) =>
      defaultStatement(node, arg);
  R visitBreakStatement(BreakStatement node, T arg) =>
      defaultStatement(node, arg);
  R visitWhileStatement(WhileStatement node, T arg) =>
      defaultStatement(node, arg);
  R visitDoStatement(DoStatement node, T arg) => defaultStatement(node, arg);
  R visitForStatement(ForStatement node, T arg) => defaultStatement(node, arg);
  R visitForInStatement(ForInStatement node, T arg) =>
      defaultStatement(node, arg);
  R visitSwitchStatement(SwitchStatement node, T arg) =>
      defaultStatement(node, arg);
  R visitContinueSwitchStatement(ContinueSwitchStatement node, T arg) =>
      defaultStatement(node, arg);
  R visitIfStatement(IfStatement node, T arg) => defaultStatement(node, arg);
  R visitReturnStatement(ReturnStatement node, T arg) =>
      defaultStatement(node, arg);
  R visitTryCatch(TryCatch node, T arg) => defaultStatement(node, arg);
  R visitTryFinally(TryFinally node, T arg) => defaultStatement(node, arg);
  R visitYieldStatement(YieldStatement node, T arg) =>
      defaultStatement(node, arg);
  R visitVariableDeclaration(VariableDeclaration node, T arg) =>
      defaultStatement(node, arg);
  R visitFunctionDeclaration(FunctionDeclaration node, T arg) =>
      defaultStatement(node, arg);

  // Members
  R defaultMember(Member node, T arg) => defaultTreeNode(node, arg);
  R visitConstructor(Constructor node, T arg) => defaultMember(node, arg);
  R visitProcedure(Procedure node, T arg) => defaultMember(node, arg);
  R visitField(Field node, T arg) => defaultMember(node, arg);
  R visitRedirectingFactoryConstructor(
      RedirectingFactoryConstructor node, T arg) {
    return defaultMember(node, arg);
  }

  // Classes
  R visitClass(Class node, T arg) => defaultTreeNode(node, arg);

  // Initializers
  R defaultInitializer(Initializer node, T arg) => defaultTreeNode(node, arg);
  R visitInvalidInitializer(InvalidInitializer node, T arg) =>
      defaultInitializer(node, arg);
  R visitFieldInitializer(FieldInitializer node, T arg) =>
      defaultInitializer(node, arg);
  R visitSuperInitializer(SuperInitializer node, T arg) =>
      defaultInitializer(node, arg);
  R visitRedirectingInitializer(RedirectingInitializer node, T arg) =>
      defaultInitializer(node, arg);
  R visitLocalInitializer(LocalInitializer node, T arg) =>
      defaultInitializer(node, arg);
  R visitAssertInitializer(AssertInitializer node, T arg) =>
      defaultInitializer(node, arg);

  // Other tree nodes
  R visitLibrary(Library node, T arg) => defaultTreeNode(node, arg);
  R visitLibraryDependency(LibraryDependency node, T arg) =>
      defaultTreeNode(node, arg);
  R visitCombinator(Combinator node, T arg) => defaultTreeNode(node, arg);
  R visitLibraryPart(LibraryPart node, T arg) => defaultTreeNode(node, arg);
  R visitTypedef(Typedef node, T arg) => defaultTreeNode(node, arg);
  R visitTypeParameter(TypeParameter node, T arg) => defaultTreeNode(node, arg);
  R visitFunctionNode(FunctionNode node, T arg) => defaultTreeNode(node, arg);
  R visitArguments(Arguments node, T arg) => defaultTreeNode(node, arg);
  R visitNamedExpression(NamedExpression node, T arg) =>
      defaultTreeNode(node, arg);
  R visitSwitchCase(SwitchCase node, T arg) => defaultTreeNode(node, arg);
  R visitCatch(Catch node, T arg) => defaultTreeNode(node, arg);
  R visitMapEntry(MapEntry node, T arg) => defaultTreeNode(node, arg);
  R visitComponent(Component node, T arg) => defaultTreeNode(node, arg);
}

class ConstantVisitor1<R, T> {
  R defaultConstant(Constant node, T arg) => null;

  R visitNullConstant(NullConstant node, T arg) => defaultConstant(node, arg);
  R visitBoolConstant(BoolConstant node, T arg) => defaultConstant(node, arg);
  R visitIntConstant(IntConstant node, T arg) => defaultConstant(node, arg);
  R visitDoubleConstant(DoubleConstant node, T arg) =>
      defaultConstant(node, arg);
  R visitStringConstant(StringConstant node, T arg) =>
      defaultConstant(node, arg);
  R visitSymbolConstant(SymbolConstant node, T arg) =>
      defaultConstant(node, arg);
  R visitMapConstant(MapConstant node, T arg) => defaultConstant(node, arg);
  R visitListConstant(ListConstant node, T arg) => defaultConstant(node, arg);
  R visitInstanceConstant(InstanceConstant node, T arg) =>
      defaultConstant(node, arg);
  R visitPartialInstantiationConstant(
          PartialInstantiationConstant node, T arg) =>
      defaultConstant(node, arg);
  R visitTearOffConstant(TearOffConstant node, T arg) =>
      defaultConstant(node, arg);
  R visitTypeLiteralConstant(TypeLiteralConstant node, T arg) =>
      defaultConstant(node, arg);
  R visitUnevaluatedConstant(UnevaluatedConstant node, T arg) =>
      defaultConstant(node, arg);
}

class MemberReferenceVisitor1<R, T> {
  const MemberReferenceVisitor1();

  R defaultMemberReference(Member node, T arg) => null;

  R visitFieldReference(Field node, T arg) => defaultMemberReference(node, arg);
  R visitConstructorReference(Constructor node, T arg) =>
      defaultMemberReference(node, arg);
  R visitProcedureReference(Procedure node, T arg) =>
      defaultMemberReference(node, arg);
  R visitRedirectingFactoryConstructorReference(
      RedirectingFactoryConstructor node, T arg) {
    return defaultMemberReference(node, arg);
  }
}

class Visitor1<R, T> extends TreeVisitor1<R, T>
    implements
        DartTypeVisitor1<R, T>,
        ConstantVisitor1<R, T>,
        MemberReferenceVisitor1<R, T> {
  const Visitor1();

  /// The catch-all case, except for references.
  R defaultNode(Node node, T arg) => null;
  R defaultTreeNode(TreeNode node, T arg) => defaultNode(node, arg);

  // DartTypes
  R defaultDartType(DartType node, T arg) => defaultNode(node, arg);
  R visitInvalidType(InvalidType node, T arg) => defaultDartType(node, arg);
  R visitDynamicType(DynamicType node, T arg) => defaultDartType(node, arg);
  R visitVoidType(VoidType node, T arg) => defaultDartType(node, arg);
  R visitBottomType(BottomType node, T arg) => defaultDartType(node, arg);
  R visitInterfaceType(InterfaceType node, T arg) => defaultDartType(node, arg);
  R visitFunctionType(FunctionType node, T arg) => defaultDartType(node, arg);
  R visitTypeParameterType(TypeParameterType node, T arg) =>
      defaultDartType(node, arg);
  R visitTypedefType(TypedefType node, T arg) => defaultDartType(node, arg);

  // Constants
  R defaultConstant(Constant node, T arg) => defaultNode(node, arg);
  R visitNullConstant(NullConstant node, T arg) => defaultConstant(node, arg);
  R visitBoolConstant(BoolConstant node, T arg) => defaultConstant(node, arg);
  R visitIntConstant(IntConstant node, T arg) => defaultConstant(node, arg);
  R visitDoubleConstant(DoubleConstant node, T arg) =>
      defaultConstant(node, arg);
  R visitStringConstant(StringConstant node, T arg) =>
      defaultConstant(node, arg);
  R visitSymbolConstant(SymbolConstant node, T arg) =>
      defaultConstant(node, arg);
  R visitMapConstant(MapConstant node, T arg) => defaultConstant(node, arg);
  R visitListConstant(ListConstant node, T arg) => defaultConstant(node, arg);
  R visitInstanceConstant(InstanceConstant node, T arg) =>
      defaultConstant(node, arg);
  R visitPartialInstantiationConstant(
          PartialInstantiationConstant node, T arg) =>
      defaultConstant(node, arg);
  R visitTearOffConstant(TearOffConstant node, T arg) =>
      defaultConstant(node, arg);
  R visitTypeLiteralConstant(TypeLiteralConstant node, T arg) =>
      defaultConstant(node, arg);
  R visitUnevaluatedConstant(UnevaluatedConstant node, T arg) =>
      defaultConstant(node, arg);

  // Class references
  R visitClassReference(Class node, T arg) => null;
  R visitTypedefReference(Typedef node, T arg) => null;

  // Constant references
  R defaultConstantReference(Constant node, T arg) => null;
  R visitNullConstantReference(NullConstant node, T arg) =>
      defaultConstantReference(node, arg);
  R visitBoolConstantReference(BoolConstant node, T arg) =>
      defaultConstantReference(node, arg);
  R visitIntConstantReference(IntConstant node, T arg) =>
      defaultConstantReference(node, arg);
  R visitDoubleConstantReference(DoubleConstant node, T arg) =>
      defaultConstantReference(node, arg);
  R visitStringConstantReference(StringConstant node, T arg) =>
      defaultConstantReference(node, arg);
  R visitSymbolConstantReference(SymbolConstant node, T arg) =>
      defaultConstantReference(node, arg);
  R visitMapConstantReference(MapConstant node, T arg) =>
      defaultConstantReference(node, arg);
  R visitListConstantReference(ListConstant node, T arg) =>
      defaultConstantReference(node, arg);
  R visitInstanceConstantReference(InstanceConstant node, T arg) =>
      defaultConstantReference(node, arg);
  R visitPartialInstantiationConstantReference(
          PartialInstantiationConstant node, T arg) =>
      defaultConstantReference(node, arg);
  R visitTearOffConstantReference(TearOffConstant node, T arg) =>
      defaultConstantReference(node, arg);
  R visitTypeLiteralConstantReference(TypeLiteralConstant node, T arg) =>
      defaultConstantReference(node, arg);
  R visitUnevaluatedConstantReference(UnevaluatedConstant node, T arg) =>
      defaultConstantReference(node, arg);

  // Member references
  R defaultMemberReference(Member node, T arg) => null;
  R visitFieldReference(Field node, T arg) => defaultMemberReference(node, arg);
  R visitConstructorReference(Constructor node, T arg) =>
      defaultMemberReference(node, arg);
  R visitProcedureReference(Procedure node, T arg) =>
      defaultMemberReference(node, arg);
  R visitRedirectingFactoryConstructorReference(
      RedirectingFactoryConstructor node, T arg) {
    return defaultMemberReference(node, arg);
  }

  R visitName(Name node, T arg) => defaultNode(node, arg);
  R visitSupertype(Supertype node, T arg) => defaultNode(node, arg);
  R visitNamedType(NamedType node, T arg) => defaultNode(node, arg);
}

class KernelBottomupFolder<R, A> implements Visitor<R> {
  final Visitor1<R, A> function;

  final A Function(A, R) compose;

  final A unit;

  final List<R> results = <R>[];

  KernelBottomupFolder(this.function, this.compose, this.unit);

  R visit(Node node, R Function(A) functionOnNode) {
    int resultsCount = results.length;
    node.visitChildren(this);

    A composed = unit;
    for (int i = resultsCount; i < results.length; ++i) {
      composed = compose(composed, results[i]);
    }
    results.length = resultsCount;

    R result = functionOnNode(composed);
    results.add(result);
    return result;
  }

  @override
  R defaultExpression(Expression node) {
    throw new UnsupportedError("defaultExpression");
  }

  @override
  R visitNamedType(NamedType node) {
    return visit(node, (A arg) {
      return function.visitNamedType(node, arg);
    });
  }

  @override
  R visitSupertype(Supertype node) {
    return visit(node, (A arg) {
      return function.visitSupertype(node, arg);
    });
  }

  @override
  R visitName(Name node) {
    return visit(node, (A arg) {
      return function.visitName(node, arg);
    });
  }

  @override
  R visitRedirectingFactoryConstructorReference(
      RedirectingFactoryConstructor node) {
    return null;
  }

  @override
  R visitProcedureReference(Procedure node) {
    return null;
  }

  @override
  R visitConstructorReference(Constructor node) {
    return null;
  }

  @override
  R visitFieldReference(Field node) {
    return null;
  }

  @override
  R defaultMemberReference(Member node) {
    throw new UnsupportedError("defaultMemberReference");
  }

  @override
  R visitUnevaluatedConstantReference(UnevaluatedConstant node) {
    return null;
  }

  @override
  R visitTypeLiteralConstantReference(TypeLiteralConstant node) {
    return null;
  }

  @override
  R visitTearOffConstantReference(TearOffConstant node) {
    return null;
  }

  @override
  R visitPartialInstantiationConstantReference(
      PartialInstantiationConstant node) {
    return null;
  }

  @override
  R visitInstanceConstantReference(InstanceConstant node) {
    return null;
  }

  @override
  R visitListConstantReference(ListConstant node) {
    return null;
  }

  @override
  R visitMapConstantReference(MapConstant node) {
    return null;
  }

  @override
  R visitSymbolConstantReference(SymbolConstant node) {
    return null;
  }

  @override
  R visitStringConstantReference(StringConstant node) {
    return null;
  }

  @override
  R visitDoubleConstantReference(DoubleConstant node) {
    return null;
  }

  @override
  R visitIntConstantReference(IntConstant node) {
    return null;
  }

  @override
  R visitBoolConstantReference(BoolConstant node) {
    return null;
  }

  @override
  R visitNullConstantReference(NullConstant node) {
    return null;
  }

  @override
  R defaultConstantReference(Constant node) {
    throw new UnsupportedError("defaultConstantReference");
  }

  @override
  R visitTypedefReference(Typedef node) {
    return null;
  }

  @override
  R visitClassReference(Class node) {
    return null;
  }

  @override
  R visitUnevaluatedConstant(UnevaluatedConstant node) {
    return visit(node, (A arg) {
      return function.visitUnevaluatedConstant(node, arg);
    });
  }

  @override
  R visitTypeLiteralConstant(TypeLiteralConstant node) {
    return visit(node, (A arg) {
      return function.visitTypeLiteralConstant(node, arg);
    });
  }

  @override
  R visitTearOffConstant(TearOffConstant node) {
    return visit(node, (A arg) {
      return function.visitTearOffConstant(node, arg);
    });
  }

  @override
  R visitPartialInstantiationConstant(PartialInstantiationConstant node) {
    return visit(node, (A arg) {
      return function.visitPartialInstantiationConstant(node, arg);
    });
  }

  @override
  R visitInstanceConstant(InstanceConstant node) {
    return visit(node, (A arg) {
      return function.visitInstanceConstant(node, arg);
    });
  }

  @override
  R visitListConstant(ListConstant node) {
    return visit(node, (A arg) {
      return function.visitListConstant(node, arg);
    });
  }

  @override
  R visitMapConstant(MapConstant node) {
    return visit(node, (A arg) {
      return function.visitMapConstant(node, arg);
    });
  }

  @override
  R visitSymbolConstant(SymbolConstant node) {
    return visit(node, (A arg) {
      return function.visitSymbolConstant(node, arg);
    });
  }

  @override
  R visitStringConstant(StringConstant node) {
    return visit(node, (A arg) {
      return function.visitStringConstant(node, arg);
    });
  }

  @override
  R visitDoubleConstant(DoubleConstant node) {
    return visit(node, (A arg) {
      return function.visitDoubleConstant(node, arg);
    });
  }

  @override
  R visitIntConstant(IntConstant node) {
    return visit(node, (A arg) {
      return function.visitIntConstant(node, arg);
    });
  }

  @override
  R visitBoolConstant(BoolConstant node) {
    return visit(node, (A arg) {
      return function.visitBoolConstant(node, arg);
    });
  }

  @override
  R visitNullConstant(NullConstant node) {
    return visit(node, (A arg) {
      return function.visitNullConstant(node, arg);
    });
  }

  @override
  R defaultConstant(Constant node) {
    throw new UnsupportedError("defaultConstant");
  }

  @override
  R visitTypedefType(TypedefType node) {
    return visit(node, (A arg) {
      return function.visitTypedefType(node, arg);
    });
  }

  @override
  R visitTypeParameterType(TypeParameterType node) {
    return visit(node, (A arg) {
      return function.visitTypeParameterType(node, arg);
    });
  }

  @override
  R visitFunctionType(FunctionType node) {
    return visit(node, (A arg) {
      return function.visitFunctionType(node, arg);
    });
  }

  @override
  R visitInterfaceType(InterfaceType node) {
    return visit(node, (A arg) {
      return function.visitInterfaceType(node, arg);
    });
  }

  @override
  R visitBottomType(BottomType node) {
    return visit(node, (A arg) {
      return function.visitBottomType(node, arg);
    });
  }

  @override
  R visitVoidType(VoidType node) {
    return visit(node, (A arg) {
      return function.visitVoidType(node, arg);
    });
  }

  @override
  R visitDynamicType(DynamicType node) {
    return visit(node, (A arg) {
      return function.visitDynamicType(node, arg);
    });
  }

  @override
  R visitInvalidType(InvalidType node) {
    return visit(node, (A arg) {
      return function.visitInvalidType(node, arg);
    });
  }

  @override
  R defaultDartType(DartType node) {
    throw new UnsupportedError("defaultDartType");
  }

  @override
  R defaultTreeNode(TreeNode node) {
    throw new UnsupportedError("defaultTreeNode");
  }

  @override
  R defaultNode(Node node) {
    throw new UnsupportedError("defaultNode");
  }

  @override
  R visitComponent(Component node) {
    return visit(node, (A arg) {
      return function.visitComponent(node, arg);
    });
  }

  @override
  R visitMapEntry(MapEntry node) {
    return visit(node, (A arg) {
      return function.visitMapEntry(node, arg);
    });
  }

  @override
  R visitCatch(Catch node) {
    return visit(node, (A arg) {
      return function.visitCatch(node, arg);
    });
  }

  @override
  R visitSwitchCase(SwitchCase node) {
    return visit(node, (A arg) {
      return function.visitSwitchCase(node, arg);
    });
  }

  @override
  R visitNamedExpression(NamedExpression node) {
    return visit(node, (A arg) {
      return function.visitNamedExpression(node, arg);
    });
  }

  @override
  R visitArguments(Arguments node) {
    return visit(node, (A arg) {
      return function.visitArguments(node, arg);
    });
  }

  @override
  R visitFunctionNode(FunctionNode node) {
    return visit(node, (A arg) {
      return function.visitFunctionNode(node, arg);
    });
  }

  @override
  R visitTypeParameter(TypeParameter node) {
    return visit(node, (A arg) {
      return function.visitTypeParameter(node, arg);
    });
  }

  @override
  R visitTypedef(Typedef node) {
    return visit(node, (A arg) {
      return function.visitTypedef(node, arg);
    });
  }

  @override
  R visitLibraryPart(LibraryPart node) {
    return visit(node, (A arg) {
      return function.visitLibraryPart(node, arg);
    });
  }

  @override
  R visitCombinator(Combinator node) {
    return visit(node, (A arg) {
      return function.visitCombinator(node, arg);
    });
  }

  @override
  R visitLibraryDependency(LibraryDependency node) {
    return visit(node, (A arg) {
      return function.visitLibraryDependency(node, arg);
    });
  }

  @override
  R visitLibrary(Library node) {
    return visit(node, (A arg) {
      return function.visitLibrary(node, arg);
    });
  }

  @override
  R visitAssertInitializer(AssertInitializer node) {
    return visit(node, (A arg) {
      return function.visitAssertInitializer(node, arg);
    });
  }

  @override
  R visitLocalInitializer(LocalInitializer node) {
    return visit(node, (A arg) {
      return function.visitLocalInitializer(node, arg);
    });
  }

  @override
  R visitRedirectingInitializer(RedirectingInitializer node) {
    return visit(node, (A arg) {
      return function.visitRedirectingInitializer(node, arg);
    });
  }

  @override
  R visitSuperInitializer(SuperInitializer node) {
    return visit(node, (A arg) {
      return function.visitSuperInitializer(node, arg);
    });
  }

  @override
  R visitFieldInitializer(FieldInitializer node) {
    return visit(node, (A arg) {
      return function.visitFieldInitializer(node, arg);
    });
  }

  @override
  R visitInvalidInitializer(InvalidInitializer node) {
    return visit(node, (A arg) {
      return function.visitInvalidInitializer(node, arg);
    });
  }

  @override
  R defaultInitializer(Initializer node) {
    throw new UnsupportedError("defaultInitializer");
  }

  @override
  R visitClass(Class node) {
    return visit(node, (A arg) {
      return function.visitClass(node, arg);
    });
  }

  @override
  R visitRedirectingFactoryConstructor(RedirectingFactoryConstructor node) {
    return visit(node, (A arg) {
      return function.visitRedirectingFactoryConstructor(node, arg);
    });
  }

  @override
  R visitField(Field node) {
    return visit(node, (A arg) {
      return function.visitField(node, arg);
    });
  }

  @override
  R visitProcedure(Procedure node) {
    return visit(node, (A arg) {
      return function.visitProcedure(node, arg);
    });
  }

  @override
  R visitConstructor(Constructor node) {
    return visit(node, (A arg) {
      return function.visitConstructor(node, arg);
    });
  }

  @override
  R defaultMember(Member node) {
    throw new UnsupportedError("defaultMember");
  }

  @override
  R visitFunctionDeclaration(FunctionDeclaration node) {
    return visit(node, (A arg) {
      return function.visitFunctionDeclaration(node, arg);
    });
  }

  @override
  R visitVariableDeclaration(VariableDeclaration node) {
    return visit(node, (A arg) {
      return function.visitVariableDeclaration(node, arg);
    });
  }

  @override
  R visitYieldStatement(YieldStatement node) {
    return visit(node, (A arg) {
      return function.visitYieldStatement(node, arg);
    });
  }

  @override
  R visitTryFinally(TryFinally node) {
    return visit(node, (A arg) {
      return function.visitTryFinally(node, arg);
    });
  }

  @override
  R visitTryCatch(TryCatch node) {
    return visit(node, (A arg) {
      return function.visitTryCatch(node, arg);
    });
  }

  @override
  R visitReturnStatement(ReturnStatement node) {
    return visit(node, (A arg) {
      return function.visitReturnStatement(node, arg);
    });
  }

  @override
  R visitIfStatement(IfStatement node) {
    return visit(node, (A arg) {
      return function.visitIfStatement(node, arg);
    });
  }

  @override
  R visitContinueSwitchStatement(ContinueSwitchStatement node) {
    return visit(node, (A arg) {
      return function.visitContinueSwitchStatement(node, arg);
    });
  }

  @override
  R visitSwitchStatement(SwitchStatement node) {
    return visit(node, (A arg) {
      return function.visitSwitchStatement(node, arg);
    });
  }

  @override
  R visitForInStatement(ForInStatement node) {
    return visit(node, (A arg) {
      return function.visitForInStatement(node, arg);
    });
  }

  @override
  R visitForStatement(ForStatement node) {
    return visit(node, (A arg) {
      return function.visitForStatement(node, arg);
    });
  }

  @override
  R visitDoStatement(DoStatement node) {
    return visit(node, (A arg) {
      return function.visitDoStatement(node, arg);
    });
  }

  @override
  R visitWhileStatement(WhileStatement node) {
    return visit(node, (A arg) {
      return function.visitWhileStatement(node, arg);
    });
  }

  @override
  R visitBreakStatement(BreakStatement node) {
    return visit(node, (A arg) {
      return function.visitBreakStatement(node, arg);
    });
  }

  @override
  R visitLabeledStatement(LabeledStatement node) {
    return visit(node, (A arg) {
      return function.visitLabeledStatement(node, arg);
    });
  }

  @override
  R visitAssertStatement(AssertStatement node) {
    return visit(node, (A arg) {
      return function.visitAssertStatement(node, arg);
    });
  }

  @override
  R visitEmptyStatement(EmptyStatement node) {
    return visit(node, (A arg) {
      return function.visitEmptyStatement(node, arg);
    });
  }

  @override
  R visitAssertBlock(AssertBlock node) {
    return visit(node, (A arg) {
      return function.visitAssertBlock(node, arg);
    });
  }

  @override
  R visitBlock(Block node) {
    return visit(node, (A arg) {
      return function.visitBlock(node, arg);
    });
  }

  @override
  R visitExpressionStatement(ExpressionStatement node) {
    return visit(node, (A arg) {
      return function.visitExpressionStatement(node, arg);
    });
  }

  @override
  R defaultStatement(Statement node) {
    throw new UnsupportedError("defaultStatement");
  }

  @override
  R visitCheckLibraryIsLoaded(CheckLibraryIsLoaded node) {
    return visit(node, (A arg) {
      return function.visitCheckLibraryIsLoaded(node, arg);
    });
  }

  @override
  R visitLoadLibrary(LoadLibrary node) {
    return visit(node, (A arg) {
      return function.visitLoadLibrary(node, arg);
    });
  }

  @override
  R visitInstantiation(Instantiation node) {
    return visit(node, (A arg) {
      return function.visitInstantiation(node, arg);
    });
  }

  @override
  R visitLet(Let node) {
    return visit(node, (A arg) {
      return function.visitLet(node, arg);
    });
  }

  @override
  R visitNullLiteral(NullLiteral node) {
    return visit(node, (A arg) {
      return function.visitNullLiteral(node, arg);
    });
  }

  @override
  R visitBoolLiteral(BoolLiteral node) {
    return visit(node, (A arg) {
      return function.visitBoolLiteral(node, arg);
    });
  }

  @override
  R visitDoubleLiteral(DoubleLiteral node) {
    return visit(node, (A arg) {
      return function.visitDoubleLiteral(node, arg);
    });
  }

  @override
  R visitIntLiteral(IntLiteral node) {
    return visit(node, (A arg) {
      return function.visitIntLiteral(node, arg);
    });
  }

  @override
  R visitStringLiteral(StringLiteral node) {
    return visit(node, (A arg) {
      return function.visitStringLiteral(node, arg);
    });
  }

  @override
  R visitConstantExpression(ConstantExpression node) {
    return visit(node, (A arg) {
      return function.visitConstantExpression(node, arg);
    });
  }

  @override
  R visitFunctionExpression(FunctionExpression node) {
    return visit(node, (A arg) {
      return function.visitFunctionExpression(node, arg);
    });
  }

  @override
  R visitAwaitExpression(AwaitExpression node) {
    return visit(node, (A arg) {
      return function.visitAwaitExpression(node, arg);
    });
  }

  @override
  R visitMapLiteral(MapLiteral node) {
    return visit(node, (A arg) {
      return function.visitMapLiteral(node, arg);
    });
  }

  @override
  R visitSetLiteral(SetLiteral node) {
    return visit(node, (A arg) {
      return function.visitSetLiteral(node, arg);
    });
  }

  @override
  R visitListLiteral(ListLiteral node) {
    return visit(node, (A arg) {
      return function.visitListLiteral(node, arg);
    });
  }

  @override
  R visitThrow(Throw node) {
    return visit(node, (A arg) {
      return function.visitThrow(node, arg);
    });
  }

  @override
  R visitRethrow(Rethrow node) {
    return visit(node, (A arg) {
      return function.visitRethrow(node, arg);
    });
  }

  @override
  R visitThisExpression(ThisExpression node) {
    return visit(node, (A arg) {
      return function.visitThisExpression(node, arg);
    });
  }

  @override
  R visitTypeLiteral(TypeLiteral node) {
    return visit(node, (A arg) {
      return function.visitTypeLiteral(node, arg);
    });
  }

  @override
  R visitSymbolLiteral(SymbolLiteral node) {
    return visit(node, (A arg) {
      return function.visitSymbolLiteral(node, arg);
    });
  }

  @override
  R visitAsExpression(AsExpression node) {
    return visit(node, (A arg) {
      return function.visitAsExpression(node, arg);
    });
  }

  @override
  R visitIsExpression(IsExpression node) {
    return visit(node, (A arg) {
      return function.visitIsExpression(node, arg);
    });
  }

  @override
  R visitStringConcatenation(StringConcatenation node) {
    return visit(node, (A arg) {
      return function.visitStringConcatenation(node, arg);
    });
  }

  @override
  R visitConditionalExpression(ConditionalExpression node) {
    return visit(node, (A arg) {
      return function.visitConditionalExpression(node, arg);
    });
  }

  @override
  R visitLogicalExpression(LogicalExpression node) {
    return visit(node, (A arg) {
      return function.visitLogicalExpression(node, arg);
    });
  }

  @override
  R visitNot(Not node) {
    return visit(node, (A arg) {
      return function.visitNot(node, arg);
    });
  }

  @override
  R visitConstructorInvocation(ConstructorInvocation node) {
    return visit(node, (A arg) {
      return function.visitConstructorInvocation(node, arg);
    });
  }

  @override
  R visitStaticInvocation(StaticInvocation node) {
    return visit(node, (A arg) {
      return function.visitStaticInvocation(node, arg);
    });
  }

  @override
  R visitSuperMethodInvocation(SuperMethodInvocation node) {
    return visit(node, (A arg) {
      return function.visitSuperMethodInvocation(node, arg);
    });
  }

  @override
  R visitDirectMethodInvocation(DirectMethodInvocation node) {
    return visit(node, (A arg) {
      return function.visitDirectMethodInvocation(node, arg);
    });
  }

  @override
  R visitMethodInvocation(MethodInvocation node) {
    return visit(node, (A arg) {
      return function.visitMethodInvocation(node, arg);
    });
  }

  @override
  R visitStaticSet(StaticSet node) {
    return visit(node, (A arg) {
      return function.visitStaticSet(node, arg);
    });
  }

  @override
  R visitStaticGet(StaticGet node) {
    return visit(node, (A arg) {
      return function.visitStaticGet(node, arg);
    });
  }

  @override
  R visitSuperPropertySet(SuperPropertySet node) {
    return visit(node, (A arg) {
      return function.visitSuperPropertySet(node, arg);
    });
  }

  @override
  R visitSuperPropertyGet(SuperPropertyGet node) {
    return visit(node, (A arg) {
      return function.visitSuperPropertyGet(node, arg);
    });
  }

  @override
  R visitDirectPropertySet(DirectPropertySet node) {
    return visit(node, (A arg) {
      return function.visitDirectPropertySet(node, arg);
    });
  }

  @override
  R visitDirectPropertyGet(DirectPropertyGet node) {
    return visit(node, (A arg) {
      return function.visitDirectPropertyGet(node, arg);
    });
  }

  @override
  R visitPropertySet(PropertySet node) {
    return visit(node, (A arg) {
      return function.visitPropertySet(node, arg);
    });
  }

  @override
  R visitPropertyGet(PropertyGet node) {
    return visit(node, (A arg) {
      return function.visitPropertyGet(node, arg);
    });
  }

  @override
  R visitVariableSet(VariableSet node) {
    return visit(node, (A arg) {
      return function.visitVariableSet(node, arg);
    });
  }

  @override
  R visitVariableGet(VariableGet node) {
    return visit(node, (A arg) {
      return function.visitVariableGet(node, arg);
    });
  }

  @override
  R visitInvalidExpression(InvalidExpression node) {
    return visit(node, (A arg) {
      return function.visitInvalidExpression(node, arg);
    });
  }

  @override
  R defaultBasicLiteral(BasicLiteral node) {
    throw new UnsupportedError("defaultBasicLiteral");
  }
}

class CaseSplitter extends Visitor1<Node, void> {
  @override
  defaultNode(Node node, _) {
    if (node is TreeNode) {
      return handleAnyTreeNode(node, null);
    }
    return node;
  }

  @override
  defaultBasicLiteral(BasicLiteral node, _) {
    return handleAnyTreeNode(node, null);
  }

  @override
  defaultConstant(Constant node, _) => node;

  @override
  defaultConstantReference(Constant node, _) => node;

  @override
  defaultDartType(DartType node, _) => node;

  @override
  defaultExpression(Expression node, _) {
    return handleAnyTreeNode(node, null);
  }

  @override
  defaultInitializer(Initializer node, _) {
    return handleAnyTreeNode(node, null);
  }

  @override
  defaultMember(Member node, _) {
    return handleAnyTreeNode(node, null);
  }

  @override
  defaultMemberReference(Member node, _) {
    return handleAnyTreeNode(node, null);
  }

  @override
  defaultStatement(Statement node, _) {
    return handleAnyTreeNode(node, null);
  }

  @override
  defaultTreeNode(TreeNode node, _) {
    return handleAnyTreeNode(node, null);
  }

  final dynamic expression;
  final dynamic statement;

  Node handleAnyTreeNode(TreeNode node, _) {
    Node transformed;
    if (node is Expression) {
      transformed = expression(node);
    } else if (node is Statement) {
      transformed = statement(node);
    } else {
      transformed = node;
    }

    // Should be added after the "functional" part if we may destroy the
    // original tree.

    if (node is! Component && !identical(node, transformed)) {
      // Components don't have parents.
      node.replaceWith(transformed);
    }

    return transformed;
  }

  CaseSplitter(this.statement, this.expression);
}

// (transform-component! component id silly-intliteral-transform)
// (define (silly-intliteral-transform exp)
//    (match exp
//     [(IntLiteral value) (IntLiteral (+ 1 value))]
//     [node node]))
Component transformComponentBang(
    Component component,
    Statement Function(Statement) transformStatement,
    Expression Function(Expression) transformExpression) {
  KernelBottomupFolder<Node, void> folder = new KernelBottomupFolder(
      new CaseSplitter(transformStatement, transformExpression),
      (a, b) => null,
      null);
  return folder.visitComponent(component);
}

// Expression transformLiteral(Expression node) {
//   iterate(6, (i) => print(i.toString()), null);
//   return node;
// }

// main() {
//   VariableDeclaration x =
//       new VariableDeclaration("x", type: const DynamicType());
//   Procedure foo = new Procedure(
//       new Name("foo"),
//       ProcedureKind.Method,
//       new FunctionNode(
//           new ReturnStatement(new MethodInvocation(new VariableGet(x),
//               new Name("+"), new Arguments([new IntLiteral(0)]))),
//           positionalParameters: [x]),
//       isStatic: true);
//   Procedure entryPoint = new Procedure(
//       new Name("main"),
//       ProcedureKind.Method,
//       new FunctionNode(new Block([
//         new ExpressionStatement(
//             new StaticInvocation(foo, new Arguments([new IntLiteral(1)])))
//       ])),
//       isStatic: true);
//   Library library = new Library(new Uri(scheme: "file", path: "foo.dart"),
//       procedures: [foo, entryPoint]);
//   Component component = new Component(libraries: [library])
//     ..mainMethod = entryPoint;

//   print("// Before:");
//   print(componentToString(component));
//   print("");

//   Component transformed = transformComponentBang(component, (x) => x, transformLiteral);

//   print("// After:");
//   print(componentToString(transformed));
// }
