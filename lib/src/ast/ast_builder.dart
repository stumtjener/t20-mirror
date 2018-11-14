// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../location.dart';
import '../errors/errors.dart';
import '../fp.dart';
import '../immutable_collections.dart';

import '../static_semantics/type_utils.dart' as typeUtils
    show boolType, intType, stringType;

import 'algebra.dart';
import 'ast_module.dart';
import 'ast_expressions.dart';
import 'ast_declaration.dart';
import 'ast_patterns.dart';
import 'binder.dart';
import 'datatype.dart';

class Name {
  final Location location;
  final int intern;
  final String sourceName;

  Name(this.sourceName, this.location) : intern = sourceName.hashCode;

  String toString() {
    return "$sourceName:$location";
  }
}

class BuildContext {
  final ImmutableMap<int, Declaration> declarations;
  final ImmutableMap<int, Quantifier> quantifiers;
  final ImmutableMap<int, Signature> signatures;
  final ImmutableMap<int, TypeDescriptor> typenames;

  BuildContext(
      this.declarations, this.quantifiers, this.signatures, this.typenames);
  BuildContext.empty()
      : this(
            ImmutableMap<int, Declaration>.empty(),
            ImmutableMap<int, Quantifier>.empty(),
            ImmutableMap<int, Signature>.empty(),
            ImmutableMap<int, TypeDescriptor>.empty());

  Declaration getDeclaration(Name name) {
    return declarations.lookup(name.intern);
  }

  BuildContext putDeclaration(Name name, Declaration declaration) {
    return BuildContext(declarations.put(name.intern, declaration), quantifiers,
        signatures, typenames);
  }

  Signature getSignature(Name name) {
    return signatures.lookup(name.intern);
  }

  BuildContext putSignature(Name name, Signature signature) {
    return BuildContext(declarations, quantifiers,
        signatures.put(name.intern, signature), typenames);
  }

  TypeDescriptor getTypeDescriptor(Name name) {
    return typenames.lookup(name.intern);
  }

  BuildContext putTypeDescriptor(Name name, TypeDescriptor desc) {
    return BuildContext(declarations, quantifiers, signatures,
        typenames.put(name.intern, desc));
  }

  Quantifier getQuantifier(Name name) {
    return quantifiers.lookup(name.intern);
  }

  BuildContext putQuantifier(Name name, Quantifier quantifier) {
    return BuildContext(declarations, quantifiers.put(name.intern, quantifier),
        signatures, typenames);
  }

  BuildContext union(BuildContext other) {
    return BuildContext(
        declarations.union(other.declarations),
        quantifiers.union(other.quantifiers),
        signatures.union(other.signatures),
        typenames.union(other.typenames));
  }
}

class OutputBuildContext extends BuildContext {
  final List<Name> declaredNames;

  OutputBuildContext(this.declaredNames, BuildContext ctxt)
      : super(ctxt.declarations, ctxt.quantifiers, ctxt.signatures,
            ctxt.typenames);
}

typedef Build<T> = Pair<BuildContext, T> Function(BuildContext);

// builder : (BuildContext) -> (BuildContext * node)
// forall ctxt \in BuildContext. builder(ctxt) = (ctxt',_) such that |ctxt'| >= |ctxt|.
class ASTBuilder extends TAlgebra<Name, Build<ModuleMember>, Build<Expression>,
    Build<Pattern>, Build<Datatype>> {
  final List<Signature> lacksAccompanyingDefinition = new List<Signature>();
  final BuildContext emptyContext = new BuildContext.empty();

  Pair<BuildContext, T> trivial<T>(Build<T> builder) {
    return builder(emptyContext);
  }

  Pair<BuildContext, T> build<T>(Build<T> builder, BuildContext context) {
    return builder(context);
  }

  T forgetfulBuild<T>(Build<T> builder, BuildContext context) {
    Pair<BuildContext, T> result = builder(context);
    return result.snd;
  }

  Triple<BuildContext, List<Name>, Pattern> buildPattern(
      Build<Pattern> builder, BuildContext context) {
    Pair<BuildContext, Pattern> result = builder(context);
    if (result.fst is OutputBuildContext) {
      OutputBuildContext ctxt0 = result.fst;
      return Triple<BuildContext, List<Name>, Pattern>(
          ctxt0, ctxt0.declaredNames, result.snd);
    } else {
      throw "Logical error. Expected an 'OutputBuildContext'.";
    }
  }

  Triple<BuildContext, List<Name>, List<Pattern>> buildParameters(
      List<Build<Pattern>> parameters, BuildContext context) {
    BuildContext ctxt0 = context; // Output context.
    List<Pattern> parameters0 = new List<Pattern>();
    List<Name> declaredNames = new List<Name>();
    for (int i = 0; i < parameters.length; i++) {
      Triple<BuildContext, List<Name>, Pattern> result =
          buildPattern(parameters[i], context);
      ctxt0 = ctxt0.union(result.fst);
      declaredNames.addAll(result.snd);
      parameters0[i] = result.thd;
    }
    return Triple<BuildContext, List<Name>, List<Pattern>>(
        ctxt0, declaredNames, parameters0);
  }

  List<Name> checkDuplicates(List<Name> names) {
    Set<int> uniqueNames = new Set<int>();
    List<Name> dups = new List<Name>();
    for (int i = 0; i < names.length; i++) {
      if (uniqueNames.contains(names[i].intern)) {
        dups.add(names[i]);
      }
    }
    return dups;
  }

  Pair<BuildContext, T> reportDuplicates<T>(List<Name> duplicates,
      Pair<BuildContext, T> Function(LocatedError, Location location) error) {
    Name first = duplicates[0];
    return error(MultipleDeclarationsError(first.sourceName, first.location),
        first.location);
  }

  BuildContext exposeQuantifiers(Signature sig, BuildContext context) {
    return context; // TODO.
  }

  Binder binderOf(Name name) {
    return Binder.fromSource(name.sourceName, name.location);
  }

  Pair<BuildContext, ModuleMember> moduleError(
      LocatedError error, Location location) {
    return Pair<BuildContext, ModuleMember>(
        emptyContext, ErrorModule(error, location));
  }

  Pair<BuildContext, Expression> expressionError(
      LocatedError error, Location location) {
    return Pair<BuildContext, Expression>(
        emptyContext, new ErrorExpression(error, location));
  }

  Pair<BuildContext, Pattern> patternError(
      LocatedError error, Location location) {
    return Pair<BuildContext, Pattern>(
        emptyContext, new ErrorPattern(error, location));
  }

  Pair<BuildContext, Datatype> typeError(
      LocatedError error, Location location) {
    return Pair<BuildContext, Datatype>(
        emptyContext, new ErrorType(error, location));
  }

  Build<ModuleMember> datatypes(
          List<
                  Triple<Name, List<Name>,
                      List<Pair<Name, List<Build<Datatype>>>>>>
              defs,
          List<Name> deriving,
          {Location location}) =>
      (BuildContext ctxt) {
        // Context shared amongst definitions
        BuildContext sharedContext = ctxt;
        // Declared constructor names.
        List<Name> declaredNames = List<Name>();
        // Build each datatype definition.
        List<DatatypeDescriptor> descs = new List<DatatypeDescriptor>();
        for (int i = 0; i < defs.length; i++) {
          Triple<Name, List<Name>, List<Pair<Name, List<Build<Datatype>>>>>
              def = defs[i];
          // Create a binder for name.
          Name name = def.fst;
          Binder binder = binderOf(name);
          // Check for duplicate parameters.
          List<Name> typeParameters = def.snd;
          List<Name> dups = checkDuplicates(typeParameters);
          if (dups.length > 0) {
            return reportDuplicates(dups, moduleError);
          }
          // Transform the parameters.
          List<Quantifier> quantifiers = new List<Quantifier>();
          for (int i = 0; i < typeParameters.length; i++) {
            Quantifier q = Quantifier.of(binderOf(typeParameters[i]));
            quantifiers[i] = q;
          }
          // Create a partial type descriptor.
          // TODO add location information per descriptor.
          DatatypeDescriptor desc =
              DatatypeDescriptor.partial(binder, quantifiers, location);
          // Bind the (partial) descriptor in the context.
          sharedContext = sharedContext.putTypeDescriptor(name, desc);
          // Expose the quantifiers.
          BuildContext ctxt0 = sharedContext;
          for (int j = 0; j < quantifiers.length; j++) {
            ctxt0 = ctxt0.putQuantifier(typeParameters[i], quantifiers[j]);
          }
          // Build the data constructors.
          List<Pair<Name, List<Build<Datatype>>>> constructors = def.thd;
          List<DataConstructor> dataConstructors = new List<DataConstructor>();
          for (int j = 0; j < constructors.length; j++) {
            Pair<Name, List<Build<Datatype>>> constr = constructors[j];
            // Create a binder for the name.
            Name constrName = constr.fst;
            Binder constrBinder = binderOf(constrName);
            declaredNames.add(constrName);
            // Build each datatype
            List<Build<Datatype>> types = constr.snd;
            List<Datatype> types0 = new List<Datatype>();
            for (int k = 0; k < types.length; k++) {
              types0.add(forgetfulBuild<Datatype>(types[k], ctxt0));
            }
            // Construct the data constructor node.
            DataConstructor dataConstructor =
                DataConstructor(constrBinder, types0, constrName.location);
            dataConstructor.declarator = desc;
            dataConstructors.add(dataConstructor);
          }
          // Finish the type descriptor.
          desc.constructors = dataConstructors;
          descs.add(desc);
        }

        // Build the deriving clause.
        List<Derive> deriving0 = new List<Derive>();
        for (int i = 0; i < deriving.length; i++) {
          Object classDescriptor = null; // TODO look up in the environment.
          deriving0.add(Derive(classDescriptor));
        }
        // Attach the deriving clauses to each datatype declaration.
        for (int i = 0; i < descs.length; i++) {
          descs[i].deriving = deriving0;
        }

        // Construct the datatypes node.
        DatatypeDeclarations datatypeDeclarations =
            DatatypeDeclarations(descs, location);

        return Pair<BuildContext, ModuleMember>(
            sharedContext, datatypeDeclarations);
      };

  Build<ModuleMember> valueDef(Name name, Build<Expression> body,
          {Location location}) =>
      (BuildContext ctxt) {
        // Lookup the signature.
        Signature sig = ctxt.getSignature(name);
        if (sig == null) {
          // Signal an error.
          LocatedError err =
              MissingAccompanyingSignatureError(name.sourceName, location);
          return moduleError(err, location);
        }
        // Expose quantifiers.
        BuildContext ctxt0 = exposeQuantifiers(sig, ctxt);

        // Build the body.
        Expression body0 = forgetfulBuild<Expression>(body, ctxt0);

        // Create the declaration.
        ValueDeclaration member =
            new ValueDeclaration(sig, binderOf(name), body0, location);

        // Register [member] as a consumer of [sig].
        sig.addDefinition(member);

        // Create the output context.
        ctxt = ctxt.putDeclaration(name, member);

        return Pair<BuildContext, ModuleMember>(ctxt, member);
      };

  Build<ModuleMember> functionDef(
          Name name, List<Build<Pattern>> parameters, Build<Expression> body,
          {Location location}) =>
      (BuildContext ctxt) {
        // Lookup the signature.
        Signature sig = ctxt.getSignature(name);
        if (sig == null) {
          // Signal an error.
          LocatedError err =
              MissingAccompanyingSignatureError(name.sourceName, location);
          return moduleError(err, location);
        }
        // Expose quantifiers.
        BuildContext ctxt0 = exposeQuantifiers(sig, ctxt);

        // Build parameters.
        Triple<BuildContext, List<Name>, List<Pattern>> result =
            buildParameters(parameters, ctxt0);
        List<Pattern> parameters0 = result.thd;
        // Check for duplicate parameter names.
        List<Name> dups = checkDuplicates(result.snd);
        if (dups.length > 0) {
          return reportDuplicates(dups, moduleError);
        }

        // Expose parameters.
        ctxt0 = result.fst;

        // Build the body.
        Expression body0 = forgetfulBuild<Expression>(body, ctxt0);

        // Create the declaration.
        FunctionDeclaration member = new FunctionDeclaration(
            sig, binderOf(name), parameters0, body0, location);

        // Register [member] as a consumer of [sig].
        sig.addDefinition(member);

        // Create the output context.
        ctxt = ctxt.putDeclaration(name, member);

        return Pair<BuildContext, ModuleMember>(ctxt, member);
      };

  Build<ModuleMember> module(List<Build<ModuleMember>> members,
          {Location location}) =>
      (BuildContext ctxt) {
        // Build each member.
        List<ModuleMember> members0 = new List<ModuleMember>();
        for (int i = 0; i < members0.length; i++) {
          Pair<BuildContext, ModuleMember> result =
              build<ModuleMember>(members[i], ctxt);
          // Update the context.
          ctxt = result.fst;
          // Only include non-null members. Members like signatures become null.
          if (result.snd != null) {
            members0.add(result.snd);
          }
        }

        // Signal an error for every signature without an accompanying
        // definition.
        for (int i = 0; i < lacksAccompanyingDefinition.length; i++) {
          Signature sig = lacksAccompanyingDefinition[i];
          LocatedError err = MissingAccompanyingDefinitionError(
              sig.binder.sourceName, sig.binder.location);
          members0.add(ErrorModule(err, sig.location));
        }

        // Construct the module.
        TopModule module = new TopModule(members0, location);

        return Pair<BuildContext, ModuleMember>(ctxt, module);
      };

  Build<ModuleMember> typename(
          Name name, List<Name> typeParameters, Build<Datatype> type,
          {Location location}) =>
      (BuildContext ctxt) {
        // Create a fresh binder for [name].
        Binder binder = binderOf(name);
        // Check for duplicate type parameter names.
        List<Name> dups = checkDuplicates(typeParameters);
        if (dups.length > 0) {
          return reportDuplicates(dups, moduleError);
        }
        // Copy the original context.
        BuildContext ctxt0 = ctxt;
        // Transform the [typeParameters] into a list of quantifiers.
        List<Quantifier> quantifiers = new List<Quantifier>();
        for (int i = 0; i < typeParameters.length; i++) {
          Name typeParam = typeParameters[i];
          // Create a fresh binder.
          Binder typeBinder = binderOf(typeParam);
          // Construct a quantifier.
          Quantifier quantifier = Quantifier.of(typeBinder);
          quantifiers.add(quantifier);

          // Expose the quantifier.
          ctxt0.putQuantifier(typeParam, quantifier);
        }

        // Build the body.
        Datatype body0 = forgetfulBuild<Datatype>(type, ctxt0);

        // Construct the type descriptor.
        TypeAliasDescriptor desc =
            new TypeAliasDescriptor(binder, quantifiers, body0, location);

        // Construct the output context.
        ctxt = ctxt.putTypeDescriptor(name, desc);

        return Pair<BuildContext, ModuleMember>(ctxt, null);
      };

  Build<ModuleMember> signature(Name name, Build<Datatype> type,
          {Location location}) =>
      (BuildContext ctxt) {
        // Check whether there already exists a signature with [name], and whether
        // it has any associated definitions.
        if (ctxt.getSignature(name) != null) {
          lacksAccompanyingDefinition.add(ctxt.getSignature(name));
        }
        // Create a binder for [name].
        Binder binder = binderOf(name);

        // Build [type].
        Datatype type0 = forgetfulBuild<Datatype>(type, ctxt);

        // Construct the signature.
        Signature sig = new Signature(binder, type0, location);

        // Construct the output context.
        ctxt = ctxt.putSignature(name, sig);

        return Pair<BuildContext, ModuleMember>(ctxt, null);
      };

  Build<ModuleMember> errorModule(LocatedError error, {Location location}) =>
      (BuildContext ctxt) {
        return Pair<BuildContext, ModuleMember>(
            ctxt, new ErrorModule(error, location));
      };

  Build<Expression> boolLit(bool b, {Location location}) =>
      (BuildContext ctxt) {
        // Construct a boolean literal node.
        BoolLit lit = new BoolLit(b, location);
        lit.type = typeUtils.boolType;
        return Pair<BuildContext, Expression>(ctxt, lit);
      };

  Build<Expression> intLit(int n, {Location location}) => (BuildContext ctxt) {
        // Construct a boolean literal node.
        IntLit lit = new IntLit(n, location);
        lit.type = typeUtils.intType;
        return Pair<BuildContext, Expression>(ctxt, lit);
      };

  Build<Expression> stringLit(String s, {Location location}) =>
      (BuildContext ctxt) {
        // Construct a boolean literal node.
        StringLit lit = new StringLit(s, location);
        lit.type = typeUtils.stringType;
        return Pair<BuildContext, Expression>(ctxt, lit);
      };

  Build<Expression> varExp(Name name, {Location location}) =>
      (BuildContext ctxt) {
        // Lookup the declaration.
        Declaration declarator = ctxt.getDeclaration(name);
        if (declarator == null) {
          // Signal error.
          LocatedError err = UnboundNameError(name.sourceName, location);
          return expressionError(err, location);
        }

        // Construct a variable node.
        Variable v = new Variable(declarator, location);

        return Pair<BuildContext, Expression>(ctxt, v);
      };

  Build<Expression> apply(
          Build<Expression> fn, List<Build<Expression>> arguments,
          {Location location}) =>
      (BuildContext ctxt) {
        // Build the function expression.
        Expression fn0 = forgetfulBuild<Expression>(fn, ctxt);

        // Build the arguments.
        List<Expression> arguments0 = new List<Expression>();
        for (int i = 0; i < arguments.length; i++) {
          Expression exp = forgetfulBuild(arguments[i], ctxt);
          arguments0[i] = exp;
        }

        // Construct the application node.
        Apply apply = new Apply(fn0, arguments0, location);
        return Pair<BuildContext, Expression>(ctxt, apply);
      };

  Build<Expression> lambda(
          List<Build<Pattern>> parameters, Build<Expression> body,
          {Location location}) =>
      (BuildContext ctxt) {
        // Build the [parameters].
        Triple<BuildContext, List<Name>, List<Pattern>> result =
            buildParameters(parameters, ctxt);
        // Check for duplicate parameter names.
        List<Name> dups = checkDuplicates(result.snd);
        if (dups.length > 0) {
          return reportDuplicates(dups, expressionError);
        }

        // Build the [body].
        BuildContext ctxt0 = result.fst;
        Expression body0 = forgetfulBuild<Expression>(body, ctxt0);

        // Construct the lambda node.
        Lambda lambda = new Lambda(result.thd, body0, location);

        return Pair<BuildContext, Expression>(ctxt, lambda);
      };

  Build<Expression> let(List<Pair<Build<Pattern>, Build<Expression>>> bindings,
          Build<Expression> body,
          {BindingMethod bindingMethod = BindingMethod.Parallel,
          Location location}) =>
      (BuildContext ctxt) {
        // Copy the context.
        BuildContext ctxt0 = ctxt;
        List<Binding> bindings0 = new List<Binding>();
        List<Name> declaredNames;
        switch (bindingMethod) {
          case BindingMethod.Parallel:
            {
              // Build the patterns and their bodies in parallel, i.e. under the original context.
              List<BuildContext> contexts;
              for (int i = 0; i < bindings.length; i++) {
                // First build the pattern.
                Triple<BuildContext, List<Name>, Pattern> result =
                    buildPattern(bindings[i].fst, ctxt);
                ctxt0 = result.fst;
                if (declaredNames == null) {
                  declaredNames = result.snd;
                  contexts = <BuildContext>[ctxt0];
                } else {
                  declaredNames.addAll(result.snd);
                  contexts.add(ctxt0);
                }
                // Build the body under the original context.
                Expression body =
                    forgetfulBuild<Expression>(bindings[i].snd, ctxt);

                // Construct the binding node.
                bindings0.add(new Binding(result.thd, body));
              }
              // Merge the declaration contexts.
              ImmutableMap<int, Declaration> decls = ctxt.declarations;
              for (int i = 0; i < contexts.length; i++) {
                decls = decls.union(contexts[i].declarations);
              }
              ctxt0 = BuildContext(
                  decls, ctxt.quantifiers, ctxt.signatures, ctxt.typenames);
              break;
            }
          case BindingMethod.Sequential:
            {
              // Build the patterns and their bodies sequentially, i.e. increase the
              // context monotonically.
              for (int i = 0; i < bindings.length; i++) {
                // First build the pattern under the current (declaration) context.
                Triple<BuildContext, List<Name>, Pattern> result =
                    buildPattern(bindings[i].fst, ctxt0);
                // TODO allow shadowing of sequential names.
                if (declaredNames == null) {
                  declaredNames = result.snd;
                } else {
                  declaredNames.addAll(result.snd);
                }
                // Build the body under the current (declaration) context.
                Expression body =
                    forgetfulBuild<Expression>(bindings[i].snd, ctxt0);
                // Update the declaration context.
                ctxt0 = BuildContext(
                    ctxt0.declarations.union(result.fst.declarations),
                    ctxt0.quantifiers,
                    ctxt0.signatures,
                    ctxt0.typenames);

                // Construct the binding node.
                bindings0.add(new Binding(result.thd, body));
              }
              break;
            }
        }

        // Check for duplicate declarations.
        if (declaredNames != null) {
          List<Name> dups = checkDuplicates(declaredNames);
          if (dups.length > 0) {
            return reportDuplicates(dups, expressionError);
          }
        }

        // Build the continuation (body).
        Expression body0 = forgetfulBuild<Expression>(body, ctxt0);

        // Construct the let node.
        Let let = new Let(bindings0, body0, location);

        return new Pair<BuildContext, Expression>(ctxt, let);
      };

  Build<Expression> tuple(List<Build<Expression>> components,
          {Location location}) =>
      (BuildContext ctxt) {
        // Build each component.
        List<Expression> components0 = new List<Expression>();
        for (int i = 0; i < components.length; i++) {
          components0[i] = forgetfulBuild<Expression>(components[i], ctxt);
        }

        // Construct the tuple node.
        Tuple tuple = new Tuple(components0, location);

        return Pair<BuildContext, Expression>(ctxt, tuple);
      };

  Build<Expression> ifthenelse(Build<Expression> condition,
          Build<Expression> thenBranch, Build<Expression> elseBranch,
          {Location location}) =>
      (BuildContext ctxt) {
        // Build the [condition].
        Expression condition0 = forgetfulBuild<Expression>(condition, ctxt);
        // Build the branches.
        Expression thenBranch0 = forgetfulBuild<Expression>(thenBranch, ctxt);
        Expression elseBranch0 = forgetfulBuild<Expression>(elseBranch, ctxt);

        // Construct the if node.
        If ifthenelse = new If(condition0, thenBranch0, elseBranch0, location);
        return Pair<BuildContext, Expression>(ctxt, ifthenelse);
      };

  Build<Expression> match(Build<Expression> scrutinee,
          List<Pair<Build<Pattern>, Build<Expression>>> cases,
          {Location location}) =>
      (BuildContext ctxt) {
        // Build the [scrutinee].
        Expression scrutinee0 = forgetfulBuild<Expression>(scrutinee, ctxt);

        // Build the [cases].
        List<Case> cases0 = new List<Case>();
        for (int i = 0; i < cases.length; i++) {
          // Build the pattern first.
          Triple<BuildContext, List<Name>, Pattern> result =
              buildPattern(cases[i].fst, ctxt);
          BuildContext ctxt0 = result.fst;
          // Check for duplicates.
          List<Name> dups = checkDuplicates(result.snd);
          if (dups.length > 0) {
            return reportDuplicates(dups, expressionError);
          }
          // Build the right hand side.
          Expression rhs = forgetfulBuild<Expression>(cases[i].snd, ctxt0);

          // Construct the case.
          cases0.add(new Case(result.thd, rhs));
        }

        // Construct the match node.
        Match match = new Match(scrutinee0, cases0, location);
        return Pair<BuildContext, Expression>(ctxt, match);
      };

  Build<Expression> typeAscription(Build<Expression> exp, Build<Datatype> type,
          {Location location}) =>
      (BuildContext ctxt) {
        // Build the [type].
        Datatype type0 = forgetfulBuild<Datatype>(type, ctxt);

        // Build the expression.
        Expression exp0 = forgetfulBuild<Expression>(exp, ctxt);

        // Construct the type ascription node.
        TypeAscription typeAscription =
            new TypeAscription(exp0, type0, location);

        return Pair<BuildContext, Expression>(ctxt, typeAscription);
      };

  Build<Expression> errorExp(LocatedError error, {Location location}) =>
      (BuildContext ctxt) {
        return Pair<BuildContext, Expression>(
            ctxt, new ErrorExpression(error, location));
      };

  Build<Pattern> hasTypePattern(Build<Pattern> pattern, Build<Datatype> type,
          {Location location}) =>
      (BuildContext ctxt) {
        // Build the [type].
        Datatype type0 = forgetfulBuild<Datatype>(type, ctxt);
        // Build the [pattern].
        Triple<BuildContext, List<Name>, Pattern> result =
            buildPattern(pattern, ctxt);

        // Construct the has type node.
        HasTypePattern hasType =
            new HasTypePattern(result.thd, type0, location);
        return Pair<BuildContext, Pattern>(result.fst, hasType);
      };

  Build<Pattern> boolPattern(bool b, {Location location}) =>
      (BuildContext ctxt) {
        // Construct the output context.
        BuildContext ctxt0 = new OutputBuildContext(const <Name>[], ctxt);
        // Construct the bool pattern node.
        BoolPattern pattern = new BoolPattern(b, location);
        return Pair<BuildContext, Pattern>(ctxt0, pattern);
      };

  Build<Pattern> intPattern(int n, {Location location}) => (BuildContext ctxt) {
        // Construct the output context.
        BuildContext ctxt0 = new OutputBuildContext(const <Name>[], ctxt);
        // Construct the int pattern node.
        IntPattern pattern = new IntPattern(n, location);
        return Pair<BuildContext, Pattern>(ctxt0, pattern);
      };

  Build<Pattern> stringPattern(String s, {Location location}) =>
      (BuildContext ctxt) {
        // Construct the output context.
        BuildContext ctxt0 = new OutputBuildContext(const <Name>[], ctxt);
        // Construct the string pattern node.
        StringPattern pattern = new StringPattern(s, location);
        return Pair<BuildContext, Pattern>(ctxt0, pattern);
      };

  Build<Pattern> wildcard({Location location}) => (BuildContext ctxt) {
        // Construct the output context.
        BuildContext ctxt0 = new OutputBuildContext(const <Name>[], ctxt);
        // Construct the wild card pattern node.
        WildcardPattern pattern = new WildcardPattern(location);
        return Pair<BuildContext, Pattern>(ctxt0, pattern);
      };

  Build<Pattern> varPattern(Name name, {Location location}) =>
      (BuildContext ctxt) {
        // Construct the var pattern node.
        VariablePattern pattern = new VariablePattern(binderOf(name), location);

        // Construct the output context.
        ctxt = ctxt.putDeclaration(name, pattern);
        BuildContext ctxt0 = new OutputBuildContext(<Name>[name], ctxt);
        return Pair<BuildContext, Pattern>(ctxt0, pattern);
      };

  Build<Pattern> constrPattern(Name name, List<Build<Pattern>> parameters,
          {Location location}) =>
      (BuildContext ctxt) {
        // Copy the original context.
        BuildContext ctxt0 = ctxt;
        // Build each subpattern.
        List<Pattern> parameters0 = new List<Pattern>();
        List<Name> declaredNames;
        for (int i = 0; i < parameters.length; i++) {
          Triple<BuildContext, List<Name>, Pattern> result =
              buildPattern(parameters[i], ctxt);
          parameters0[i] = result.thd;
          if (declaredNames == null) {
            declaredNames = result.snd;
          } else {
            declaredNames.addAll(result.snd);
          }
          // Update the context.
          ctxt0 = ctxt0.union(result.fst);
        }
        // Check duplicates.
        List<Name> dups = checkDuplicates(declaredNames);
        if (dups.length > 0) {
          return reportDuplicates(dups, patternError);
        }

        // Construct the constructor node.
        ConstructorPattern constr =
            new ConstructorPattern(binderOf(name), parameters0, location);

        // Construct the output context.
        OutputBuildContext ctxt1 = new OutputBuildContext(declaredNames, ctxt0);

        return Pair<BuildContext, Pattern>(ctxt1, constr);
      };

  Build<Pattern> tuplePattern(List<Build<Pattern>> components,
          {Location location}) =>
      (BuildContext ctxt) {
        // Copy the original context.
        BuildContext ctxt0 = ctxt;
        // Build each subpattern.
        List<Pattern> components0 = new List<Pattern>();
        List<Name> declaredNames;
        for (int i = 0; i < components.length; i++) {
          Triple<BuildContext, List<Name>, Pattern> result =
              buildPattern(components[i], ctxt);
          components0[i] = result.thd;
          if (declaredNames == null) {
            declaredNames = result.snd;
          } else {
            declaredNames.addAll(result.snd);
          }
          // Update the context.
          ctxt0 = ctxt0.union(result.fst);
        }
        // Check duplicates.
        List<Name> dups = checkDuplicates(declaredNames);
        if (dups.length > 0) {
          return reportDuplicates(dups, patternError);
        }

        // Construct the tuple node.
        TuplePattern tuple = new TuplePattern(components0, location);

        // Construct the output context.
        OutputBuildContext ctxt1 = new OutputBuildContext(declaredNames, ctxt0);

        return Pair<BuildContext, Pattern>(ctxt1, tuple);
      };

  Build<Pattern> errorPattern(LocatedError error, {Location location}) =>
      (BuildContext ctxt) {
        return patternError(error, location);
      };

  Build<Datatype> intType({Location location}) => (BuildContext ctxt) {
        return Pair<BuildContext, Datatype>(ctxt, typeUtils.intType);
      };

  Build<Datatype> boolType({Location location}) => (BuildContext ctxt) {
        return Pair<BuildContext, Datatype>(ctxt, typeUtils.boolType);
      };

  Build<Datatype> stringType({Location location}) => (BuildContext ctxt) {
        return Pair<BuildContext, Datatype>(ctxt, typeUtils.stringType);
      };

  Build<Datatype> typeVar(Name name, {Location location}) =>
      (BuildContext ctxt) {
        // Look up the declarator.
        Quantifier quantifier = ctxt.getQuantifier(name);
        TypeVariable v;
        // Construct the type variable node.
        if (quantifier == null) {
          v = new TypeVariable();
        } else {
          v = new TypeVariable.bound(quantifier);
        }

        return Pair<BuildContext, Datatype>(ctxt, v);
      };

  Build<Datatype> forallType(List<Name> quantifiers, Build<Datatype> type,
          {Location location}) =>
      (BuildContext ctxt) {
        // Copy the original context.
        BuildContext ctxt0 = ctxt;
        // Transform [quantifiers].
        List<Quantifier> quantifiers0 = new List<Quantifier>();
        for (int i = 0; i < quantifiers.length; i++) {
          Name name = quantifiers[i];
          Quantifier q = Quantifier.of(binderOf(name));
          ctxt0 = ctxt.putQuantifier(name, q);
        }
        // Build the [type].
        Datatype type0 = forgetfulBuild<Datatype>(type, ctxt0);

        // Construct the forall type node.
        ForallType forallType = ForallType();
        forallType.quantifiers = quantifiers0;
        forallType.body = type0;

        return Pair<BuildContext, Datatype>(ctxt, forallType);
      };

  Build<Datatype> arrowType(
          List<Build<Datatype>> domain, Build<Datatype> codomain,
          {Location location}) =>
      (BuildContext ctxt) {
        // Build the [domain].
        List<Datatype> domain0 = new List<Datatype>();
        for (int i = 0; i < domain.length; i++) {
          domain0.add(forgetfulBuild<Datatype>(domain[i], ctxt));
        }
        // Build the [codomain].
        Datatype codomain0 = forgetfulBuild<Datatype>(codomain, ctxt);

        // Construct the arrow type node.
        Datatype arrowType = ArrowType(domain0, codomain0);

        return Pair<BuildContext, Datatype>(ctxt, arrowType);
      };

  Build<Datatype> typeConstr(Name name, List<Build<Datatype>> arguments,
          {Location location}) =>
      (BuildContext ctxt) {
        // Check whether the constructor name is defined.
        TypeDescriptor desc = ctxt.getTypeDescriptor(name);
        if (desc == null) {
          LocatedError err = UnboundNameError(name.sourceName, name.location);
          return typeError(err, location);
        }
        // Build each argument.
        List<Datatype> arguments0 = new List<Datatype>();
        for (int i = 0; i < arguments0.length; i++) {
          arguments0.add(forgetfulBuild<Datatype>(arguments[i], ctxt));
        }
        // Construct the constructor type node.
        TypeConstructor constr = new TypeConstructor.from(desc, arguments0);
        return Pair<BuildContext, Datatype>(ctxt, constr);
      };

  Build<Datatype> tupleType(List<Build<Datatype>> components,
          {Location location}) =>
      (BuildContext ctxt) {
        // Build each component.
        List<Datatype> components0 = new List<Datatype>();
        for (int i = 0; i < components0.length; i++) {
          components0.add(forgetfulBuild<Datatype>(components[i], ctxt));
        }
        // Construct the tuple type node.
        TupleType tupleType = new TupleType(components0);
        return Pair<BuildContext, Datatype>(ctxt, tupleType);
      };

  Build<Datatype> errorType(LocatedError error, {Location location}) =>
      (BuildContext ctxt) {
        return typeError(error, location);
      };

  Name termName(String name, {Location location}) {
    return Name(name, location);
  }

  Name typeName(String name, {Location location}) {
    return Name(name, location);
  }

  Name errorName(LocatedError error, {Location location}) {
    return null;
  }
}
