import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:edu_helper/updates.dart';
import 'package:edu_helper/design.dart';

Map<String, dynamic> manifest({int build = 6}) => {
  'version': '1.0.5',
  'build_number': build,
  'size': 60000000,
  'sha256': 'a' * 64,
  'apk_url': 'https://eduhelper.cosmomine.ru/downloads/eduhelper-1.0.5.apk',
  'notes': 'Исправления и улучшения',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/updates');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> calls;
  late AppUpdater updater;
  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'info') return {'version': '1.0.4', 'build_number': 5};
      if (call.method == 'install') return 'permission';
      return null;
    });
    updater = AppUpdater(
      channel: channel,
      supported: true,
      client: MockClient(
        (r) async => http.Response(
          jsonEncode(manifest()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    updater.dispose();
  });

  test(
    'Manifest rejects other hosts, insecure links, invalid hashes and sizes',
    () {
      expect(AndroidRelease.parse(manifest()).build, 6);
      for (final change in [
        {'apk_url': 'https://evil.example/app.apk'},
        {
          'apk_url':
              'http://eduhelper.cosmomine.ru/downloads/eduhelper-1.0.5.apk',
        },
        {'sha256': 'bad'},
        {'size': 300000001},
        {'build_number': 0},
        {'notes': null},
      ]) {
        expect(
          () => AndroidRelease.parse({...manifest(), ...change}),
          throwsFormatException,
        );
      }
    },
  );
  test('Checks installed build, downloads only on request, then asks Android to install', () async {
    await updater.check();
    expect(updater.available, true);
    expect(calls, ['info']);
    expect(updater.ready, false);
    await updater.download();
    expect(updater.ready, true);
    expect(updater.progress, 1);
    await updater.install();
    expect(calls, ['info', 'download', 'install']);
    expect(updater.instruction, contains('настройках Android'));
    await updater.onNativeEvent(const MethodCall('installerOpened'));
    expect(updater.instruction, contains('Подтвердите'));
  });
  test('Same and older builds never offer an update', () async {
    for (final build in [5, 4]) {
      final u = AppUpdater(
        channel: channel,
        supported: true,
        client: MockClient(
          (r) async => http.Response(
            jsonEncode(manifest(build: build)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await u.check();
      await u.download();
      expect(u.available, false);
      expect(u.ready, false);
      u.dispose();
    }
    expect(calls, ['info', 'info']);
  });
  test('Network failure can be retried', () async {
    int attempt = 0;
    final u = AppUpdater(
      channel: channel,
      supported: true,
      client: MockClient((r) async {
        if (attempt++ == 0) throw http.ClientException('offline');
        return http.Response(
          jsonEncode(manifest()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await u.check();
    expect(u.error, isNotNull);
    expect(u.checking, false);
    await u.check();
    expect(u.error, isNull);
    expect(u.available, true);
    u.dispose();
  });
  test(
    'Cancelled download cannot be installed; progress and retry work',
    () async {
      final pending = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'info') {
          return {'version': '1.0.4', 'build_number': 5};
        }
        if (call.method == 'download') await pending.future;
        if (call.method == 'cancel') {
          pending.completeError(PlatformException(code: 'cancelled'));
        }
        return null;
      });
      await updater.check();
      final task = updater.download();
      await Future<void>.delayed(Duration.zero);
      await updater.onNativeEvent(
        const MethodCall('progress', {'received': 30000000, 'total': 60000000}),
      );
      expect(updater.progress, .5);
      await updater.cancel();
      await task;
      expect(updater.ready, false);
      expect(updater.error, isNull);
      expect(updater.downloading, false);
    },
  );
  test(
    'Invalid APK disables installation and offers a fresh download',
    () async {
      await updater.check();
      await updater.download();
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
          code: 'invalid',
          message: 'Файл не прошёл проверку',
        );
      });
      await updater.install();
      expect(updater.ready, false);
      expect(updater.error, contains('проверку'));
    },
  );
  testWidgets('Update page fits a phone and exposes download then install', (
    t,
  ) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: originalTheme(Brightness.dark),
        home: UpdateScreen(updater: updater),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Доступна версия 1.0.5'), findsOneWidget);
    await t.tap(find.text('Скачать обновление'));
    await t.pumpAndSettle();
    expect(find.text('Установить'), findsOneWidget);
    await t.tap(find.text('Установить'));
    await t.pumpAndSettle();
    expect(find.textContaining('Разрешите установку'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
