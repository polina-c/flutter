// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import '../base/utils.dart';
import '../convert.dart';
import 'compile.dart';

enum CompileTarget {
  js,
  wasm,
}

sealed class WebCompilerConfig {
  const WebCompilerConfig({required this.renderer});

  /// Returns which target this compiler outputs (js or wasm)
  CompileTarget get compileTarget;
  final WebRendererMode renderer;

  String get buildKey;

  Map<String, Object> get buildEventAnalyticsValues => <String, Object>{};
}

/// Configuration for the Dart-to-Javascript compiler (dart2js).
class JsCompilerConfig extends WebCompilerConfig {
  const JsCompilerConfig({
    this.csp = false,
    this.dumpInfo = false,
    this.nativeNullAssertions = false,
    this.optimizationLevel = kDart2jsDefaultOptimizationLevel,
    this.noFrequencyBasedMinification = false,
    this.sourceMaps = true,
    super.renderer = WebRendererMode.auto,
  });

  /// Instantiates [JsCompilerConfig] suitable for the `flutter run` command.
  const JsCompilerConfig.run({
    required bool nativeNullAssertions,
    required WebRendererMode renderer,
  }) : this(
          nativeNullAssertions: nativeNullAssertions,
          optimizationLevel: kDart2jsDefaultOptimizationLevel,
          renderer: renderer,
        );

  /// The default optimization level for dart2js.
  ///
  /// Maps to [kDart2jsOptimization].
  static const String kDart2jsDefaultOptimizationLevel = 'O4';

  /// Build environment flag for [optimizationLevel].
  static const String kDart2jsOptimization = 'Dart2jsOptimization';

  /// Build environment flag for [dumpInfo].
  static const String kDart2jsDumpInfo = 'Dart2jsDumpInfo';

  /// Build environment flag for [noFrequencyBasedMinification].
  static const String kDart2jsNoFrequencyBasedMinification =
      'Dart2jsNoFrequencyBasedMinification';

  /// Build environment flag for [csp].
  static const String kCspMode = 'cspMode';

  /// Build environment flag for [sourceMaps].
  static const String kSourceMapsEnabled = 'SourceMaps';

  /// Build environment flag for [nativeNullAssertions].
  static const String kNativeNullAssertions = 'NativeNullAssertions';

  /// Whether to disable dynamic generation code to satisfy CSP policies.
  final bool csp;

  /// If `--dump-info` should be passed to the compiler.
  final bool dumpInfo;

  /// Whether native null assertions are enabled.
  final bool nativeNullAssertions;

  // If `--no-frequency-based-minification` should be passed to dart2js
  // TODO(kevmoo): consider renaming this to be "positive". Double negatives are confusing.
  final bool noFrequencyBasedMinification;

  /// The compiler optimization level.
  ///
  /// Valid values are O1 (lowest, profile default) to O4 (highest, release default).
  // TODO(kevmoo): consider storing this as an [int] and validating it!
  final String optimizationLevel;

  /// `true` if the JavaScript compiler build should output source maps.
  final bool sourceMaps;

  @override
  CompileTarget get compileTarget => CompileTarget.js;

  /// Arguments to use in both phases: full JS compile and CFE-only.
  List<String> toSharedCommandOptions() => <String>[
        if (nativeNullAssertions) '--native-null-assertions',
        if (!sourceMaps) '--no-source-maps',
      ];

  /// Arguments to use in the full JS compile, but not CFE-only.
  ///
  /// Includes the contents of [toSharedCommandOptions].
  List<String> toCommandOptions() => <String>[
        ...toSharedCommandOptions(),
        '-$optimizationLevel',
        if (dumpInfo) '--dump-info',
        if (noFrequencyBasedMinification) '--no-frequency-based-minification',
        if (csp) '--csp',
      ];

  @override
  String get buildKey {
    final Map<String, dynamic> settings = <String, dynamic>{
      'csp': csp,
      'dumpInfo': dumpInfo,
      'nativeNullAssertions': nativeNullAssertions,
      'noFrequencyBasedMinification': noFrequencyBasedMinification,
      'optimizationLevel': optimizationLevel,
      'sourceMaps': sourceMaps,
    };
    return jsonEncode(settings);
  }
}

/// Configuration for the Wasm compiler.
class WasmCompilerConfig extends WebCompilerConfig {
  const WasmCompilerConfig({
    this.omitTypeChecks = false,
    this.wasmOpt = WasmOptLevel.defaultValue,
    super.renderer = WebRendererMode.auto,
  });

  /// Build environment for [omitTypeChecks].
  static const String kOmitTypeChecks = 'WasmOmitTypeChecks';

  /// Build environment for [wasmOpt].
  static const String kRunWasmOpt = 'RunWasmOpt';

  /// If `omit-type-checks` should be passed to `dart2wasm`.
  final bool omitTypeChecks;

  /// Run wasm-opt on the resulting module.
  final WasmOptLevel wasmOpt;

  @override
  CompileTarget get compileTarget => CompileTarget.wasm;

  List<String> toCommandOptions() {
    // -O1: Optimizes
    // -O2: Same as -O1 but also minifies (still semantics preserving)
    // -O3: Same as -O2 but also omits implicit type checks.
    // -O4: Same as -O3 but also omits explicit type checks.
    //      (NOTE: This differs from dart2js -O4 semantics atm.)

    // Ortogonal: The name section is always kept by default and we emit it only
    // in [WasmOptLevel.full] mode (similar to `--strip` of static symbols in
    // AOT mode).
    final String level = !omitTypeChecks ? '-O2' : '-O4';
    return switch (wasmOpt) {
      WasmOptLevel.none => <String>['-O0'],
      WasmOptLevel.debug => <String>[level, '--no-minify'],
      WasmOptLevel.full => <String>[level, '--no-name-section'],
    };
  }

  @override
  Map<String, Object> get buildEventAnalyticsValues => <String, Object>{
        ...super.buildEventAnalyticsValues,
        kOmitTypeChecks: omitTypeChecks.toString(),
        kRunWasmOpt: wasmOpt.name,
      };

  @override
  String get buildKey {
    final Map<String, dynamic> settings = <String, dynamic>{
      'omitTypeChecks': omitTypeChecks,
      'wasmOpt': wasmOpt.name,
    };
    return jsonEncode(settings);
  }

}

enum WasmOptLevel implements CliEnum {
  full,
  debug,
  none;

  static const WasmOptLevel defaultValue = WasmOptLevel.full;

  @override
  String get cliName => name;

  @override
  String get helpText => switch (this) {
        WasmOptLevel.none =>
          'wasm-opt is not run. Fastest build; bigger, slower output.',
        WasmOptLevel.debug =>
          'Similar to `${WasmOptLevel.full.name}`, but member names are preserved. Debugging is easier, but size is a bit bigger.',
        WasmOptLevel.full =>
          'wasm-opt is run. Build time is slower, but output is smaller and faster.',
      };
}
