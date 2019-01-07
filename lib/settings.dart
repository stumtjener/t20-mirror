// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library t20.settings;

import 'dart:io' show Platform;

import 'package:args/args.dart';

class UsageError {}

class UnknownOptionError extends FormatException {
  UnknownOptionError(String message) : super(message);
}

class UnrecognisedOptionValue extends FormatException {
  UnrecognisedOptionValue(String option, String value)
      : super(
            "Invalid value; the option `$option' does accept `$value' as a valid value.");
}

class NamedOptions {
  static String get dump_ast => "dump-ast";
  static String get dump_dast => "dump-dast";
  static String get help => "help";
  static String get optimisation_level => "optimisation-level";
  static String get output => "output";
  static String get platform => "platform";
  static String get trace => "trace";
  static String get type_check => "type-check";
  static String get verbose => "verbose";
  static String get version => "version";
  static String get exit_after => "exit-after";
}

ArgParser _parser;

ArgParser _setupArgParser() {
  if (_parser != null) return _parser;

  ArgParser parser = new ArgParser();

  parser.addFlag(NamedOptions.dump_ast,
      negatable: false,
      defaultsTo: false,
      help: "Dump the syntax tree to stderr.");
  parser.addFlag(NamedOptions.dump_dast,
      negatable: false,
      defaultsTo: false,
      help: "Dump the elaborated syntax tree to stderr.");
  parser.addOption(NamedOptions.exit_after,
      defaultsTo: null,
      help: "Exit after running a particular component.",
      valueHelp: "codegen,elaborator,parser,typechecker");
  parser.addFlag(NamedOptions.help,
      abbr: 'h',
      negatable: false,
      defaultsTo: false,
      help: "Display this list of options.");
  parser.addOption(NamedOptions.optimisation_level,
      abbr: 'O',
      defaultsTo: "2",
      valueHelp: "number",
      help: "Set optimisation level to <number>");
  parser.addOption(NamedOptions.output,
      abbr: 'o',
      help: "Place the output into <file>.",
      valueHelp: "file",
      defaultsTo: "/dev/stdout");
  parser.addMultiOption(NamedOptions.trace,
      help: "Trace the operational behaviour of a component.",
      valueHelp: "codegen,elaborator,parser,typechecker");
  parser.addFlag(NamedOptions.type_check,
      negatable: true, defaultsTo: true, help: "Toggle type checking.");
  parser.addFlag(NamedOptions.verbose,
      abbr: 'v',
      negatable: false,
      defaultsTo: false,
      help: "Enable verbose logging.");
  parser.addFlag(NamedOptions.version,
      negatable: false, defaultsTo: false, help: "Display the version.");
  parser.addOption(NamedOptions.platform,
      help: "Specify where to locate the Dart Platform dill file.",
      defaultsTo: Platform.environment['T20_DART_PLATFORM_DILL'] ??
          "/usr/lib/dart/lib/_internal/vm_platform_strong.dill",
      valueHelp: "file");

  _parser = parser;
  return parser;
}

ArgResults _parse(List<String> args) {
  try {
    final ArgParser parser = _setupArgParser();
    return parser.parse(args);
  } on ArgParserException catch (err) {
    throw new UnknownOptionError(err.message);
  }
}

class Settings {
  // Boolean flags.
  final bool dumpAst;
  final bool dumpDast;
  final String exitAfter;
  final int optimisationLevel;
  final bool showHelp;
  final bool showVersion;
  final String platformDill;
  final MultiOption trace;
  final bool typeCheck;
  final bool verbose;

  // Other settings.
  final List<String> sourceFiles;
  final String outputFile;

  factory Settings.fromCLI(List<String> args, {bool allowNoSources = false}) {
    ArgResults results = _parse(args);
    bool dumpAst = results[NamedOptions.dump_ast] as bool;
    bool dumpDast = results[NamedOptions.dump_dast] as bool;
    String exitAfter = results[NamedOptions.exit_after] as String;
    String optLevel = results[NamedOptions.optimisation_level] as String;
    String outputFile = results[NamedOptions.output] as String;
    bool showHelp = results[NamedOptions.help] as bool;
    bool showVersion = results[NamedOptions.version] as bool;
    bool verbose = results[NamedOptions.verbose] as bool;
    String platformDill = results[NamedOptions.platform] as String;
    MultiOption trace = new MultiOption(
        results[NamedOptions.trace] as List<String>, verbose ?? false);
    bool typeCheck = results[NamedOptions.type_check] as bool;

    if (!_validateExitAfter(exitAfter)) {
      throw UnrecognisedOptionValue(NamedOptions.exit_after, exitAfter);
    }

    if (!_validateOptimisationLevel(optLevel)) {
      throw UnrecognisedOptionValue(NamedOptions.optimisation_level, optLevel);
    }
    int O = int.parse(optLevel);

    List<String> sourceFiles;
    if (results.rest.length > 0) {
      sourceFiles = results.rest;
    } else if (!allowNoSources && !showHelp && !showVersion) {
      throw new UsageError();
    }

    return Settings._(dumpAst, dumpDast, exitAfter, O, outputFile, showHelp,
        showVersion, sourceFiles, trace, typeCheck, verbose, platformDill);
  }

  factory Settings() => Settings.fromCLI(<String>[], allowNoSources: true);

  const Settings._(
      this.dumpAst,
      this.dumpDast,
      this.exitAfter,
      this.optimisationLevel,
      this.outputFile,
      this.showHelp,
      this.showVersion,
      this.sourceFiles,
      this.trace,
      this.typeCheck,
      this.verbose,
      this.platformDill);

  static bool _validateOptimisationLevel(String input) =>
      input != null && input.compareTo("0") >= 0 && input.compareTo("2") <= 0;

  static bool _validateExitAfter(String value, [bool allowNull = true]) {
    switch (value) {
      case "codegen":
      case "elaborator":
      case "parser":
      case "typechecker":
        return true;
      default:
        return allowNull && value == null;
    }
  }

  static String usage() {
    ArgParser parser = _setupArgParser();

    String header = "usage: t20 [OPTION]... FILE...";
    return "$header\n\nOptions are:\n${parser.usage}";
  }
}

class MultiOption {
  final List<String> values;
  final bool verbose;

  MultiOption(this.values, this.verbose);

  bool operator [](value) => verbose || values.contains(value);
}
