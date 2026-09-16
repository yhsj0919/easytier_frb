/// This is copied from Cargokit (which is the official way to use it currently)
/// Details: https://fzyzcjy.github.io/flutter_rust_bridge/manual/integrate/builtin

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import 'artifacts_provider.dart';
import 'builder.dart';
import 'crate_hash.dart';
import 'environment.dart';
import 'options.dart';
import 'target.dart';

final log = Logger('build_gradle');

class BuildGradle {
  BuildGradle({required this.userOptions});

  final CargokitUserOptions userOptions;

  Future<void> build() async {
    final targets = Environment.targetPlatforms
        .map((arch) {
          final target = Target.forFlutterName(arch);
          if (target == null) {
            throw Exception(
              "Unknown darwin target or platform: $arch, ${Environment.darwinPlatformName}",
            );
          }
          return target;
        })
        .toSet()
        .toList();

    final environment = BuildEnvironment.fromEnvironment(isAndroid: true);
    final cacheKey = <String>[
      'android-rust-v1',
      CrateHash.compute(
        environment.manifestDir,
        tempStorage: environment.targetTempDir,
      ),
      environment.configuration.name,
      environment.androidNdkVersion ?? '',
      '${environment.androidMinSdkVersion ?? ''}',
      ...targets.map((target) => '${target.rust}:${target.android}'),
    ].join('|');
    final cacheMarker = File(
      path.join(Environment.outputDir, '.cargokit-rust-cache'),
    );
    final expectedLibraries = targets.map(
      (target) => File(
        path.join(
          Environment.outputDir,
          target.android!,
          'lib${environment.crateInfo.packageName}.so',
        ),
      ),
    );
    if (cacheMarker.existsSync() &&
        cacheMarker.readAsStringSync() == cacheKey &&
        expectedLibraries.every((library) => library.existsSync())) {
      _stripAndroidLibraries(environment, expectedLibraries);
      log.info('Rust 代码未变化，直接使用已缓存的 Android 原生库');
      return;
    }
    final provider = ArtifactProvider(
      environment: environment,
      userOptions: userOptions,
    );
    final artifacts = await provider.getArtifacts(targets);

    for (final target in targets) {
      final libs = artifacts[target]!;
      final outputDir = path.join(Environment.outputDir, target.android!);
      Directory(outputDir).createSync(recursive: true);

      for (final lib in libs) {
        if (lib.type == AritifactType.dylib) {
          File(lib.path).copySync(path.join(outputDir, lib.finalFileName));
        }
      }
    }
    _stripAndroidLibraries(environment, expectedLibraries);
    cacheMarker.parent.createSync(recursive: true);
    cacheMarker.writeAsStringSync(cacheKey, flush: true);
  }

  void _stripAndroidLibraries(
    BuildEnvironment environment,
    Iterable<File> libraries,
  ) {
    final sdk = environment.androidSdkPath!;
    final ndk = environment.androidNdkVersion!;
    final host = Platform.isWindows
        ? 'windows-x86_64'
        : Platform.isMacOS
            ? 'darwin-x86_64'
            : 'linux-x86_64';
    final executable = Platform.isWindows ? 'llvm-strip.exe' : 'llvm-strip';
    final strip = path.joinAll([
      sdk,
      'ndk',
      ndk,
      'toolchains',
      'llvm',
      'prebuilt',
      host,
      'bin',
      executable,
    ]);
    if (!File(strip).existsSync()) {
      log.warning('未找到 NDK llvm-strip，跳过 Android 原生库裁剪：$strip');
      return;
    }
    for (final library in libraries) {
      final result = Process.runSync(strip, ['--strip-unneeded', library.path]);
      if (result.exitCode != 0) {
        throw ProcessException(
          strip,
          ['--strip-unneeded', library.path],
          result.stderr.toString(),
          result.exitCode,
        );
      }
    }
  }
}
