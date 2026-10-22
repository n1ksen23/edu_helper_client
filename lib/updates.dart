import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'design.dart';
import 'pages.dart';

class AndroidRelease {
  final String version, url, sha256, notes;
  final int build, size;
  const AndroidRelease({
    required this.version,
    required this.url,
    required this.sha256,
    required this.build,
    required this.size,
    required this.notes,
  });
  factory AndroidRelease.parse(Map<String, dynamic> data) {
    final version = data['version'],
        build = data['build_number'],
        size = data['size'];
    final hash = data['sha256'], url = data['apk_url'];
    if (version is! String ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
        build is! int ||
        build < 1 ||
        size is! int ||
        size < 1 ||
        size > 300000000 ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        url !=
            'https://eduhelper.cosmomine.ru/downloads/eduhelper-$version.apk') {
      throw const FormatException('Некорректные данные обновления');
    }
    final notes = data['notes'];
    if (notes is! String || notes.length > 4000) {
      throw const FormatException('Некорректные данные обновления');
    }
    return AndroidRelease(
      version: version,
      url: url as String,
      sha256: hash,
      build: build,
      size: size,
      notes: notes,
    );
  }
  Map<String, dynamic> toNative() => {
    'apk_url': url,
    'sha256': sha256,
    'size': size,
    'build_number': build,
  };
}

class AppUpdater extends ChangeNotifier {
  final http.Client client;
  final MethodChannel channel;
  final bool supported;
  String version = '';
  int build = 0, received = 0;
  AndroidRelease? release;
  bool checking = false, downloading = false, installing = false, ready = false;
  String? error, instruction;
  AppUpdater({http.Client? client, MethodChannel? channel, bool? supported})
    : client = client ?? http.Client(),
      channel =
          channel ?? const MethodChannel('ru.cosmomine.edu_helper/updates'),
      supported =
          supported ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    if (this.supported) this.channel.setMethodCallHandler(onNativeEvent);
  }
  bool get busy => checking || downloading || installing;
  bool get available => release != null;
  double get progress =>
      release == null ? 0 : (received / release!.size).clamp(0, 1);

  Future<void> onNativeEvent(MethodCall call) async {
    if (call.method == 'progress' && downloading) {
      received = (call.arguments['received'] as num).toInt();
    } else if (call.method == 'installerOpened') {
      instruction = 'Подтвердите обновление в окне Android.';
    } else if (call.method == 'permissionDenied') {
      instruction = null;
      error = 'Установка не разрешена. Нажмите «Установить» и разрешите её в настройках Android.';
    } else if (call.method == 'installerError') {
      instruction = null;
      error = 'Не удалось открыть установку. Попробуйте ещё раз.';
    } else {
      return;
    }
    notifyListeners();
  }

  Future<void> check() async {
    if (!supported || busy) return;
    checking = true;
    error = instruction = null;
    notifyListeners();
    try {
      final info = await channel.invokeMapMethod<String, dynamic>('info');
      version = info!['version'] as String;
      build = (info['build_number'] as num).toInt();
      final response = await client
          .get(
            Uri.parse('https://eduhelper.cosmomine.ru/downloads/android.json'),
            headers: {'Cache-Control': 'no-cache'},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 || response.bodyBytes.length > 16000) {
        throw const FormatException();
      }
      final latest = AndroidRelease.parse(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
      if (release?.build != latest.build) ready = false;
      release = latest.build > build ? latest : null;
      if (release == null) ready = false;
    } catch (_) {
      error =
          'Не удалось проверить обновления. Проверьте интернет и повторите.';
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  Future<void> download() async {
    if (!supported || busy || release == null) return;
    downloading = true;
    ready = false;
    received = 0;
    error = instruction = null;
    notifyListeners();
    try {
      await channel.invokeMethod<void>('download', release!.toNative());
      received = release!.size;
      ready = true;
    } on PlatformException catch (e) {
      if (e.code != 'cancelled') {
        error = e.message ?? 'Не удалось скачать обновление';
      }
    } catch (_) {
      error = 'Не удалось скачать обновление. Повторите попытку.';
    } finally {
      downloading = false;
      notifyListeners();
    }
  }

  Future<void> cancel() async {
    if (!downloading) return;
    try {
      await channel.invokeMethod<void>('cancel');
    } catch (_) {
      error = 'Не удалось отменить скачивание';
      notifyListeners();
    }
  }

  Future<void> install() async {
    if (!supported || busy || !ready) return;
    installing = true;
    error = instruction = null;
    notifyListeners();
    try {
      final status = await channel.invokeMethod<String>('install');
      instruction = status == 'permission'
          ? 'Разрешите установку для EduHelper в настройках Android и вернитесь в приложение.'
          : 'Подтвердите обновление в окне Android.';
    } on PlatformException catch (e) {
      if (e.code == 'missing' || e.code == 'invalid') ready = false;
      error = e.message ?? 'Не удалось открыть установку';
    } catch (_) {
      error = 'Не удалось открыть установку. Попробуйте ещё раз.';
    } finally {
      installing = false;
      notifyListeners();
    }
  }
}

final appUpdater = AppUpdater();

class UpdateSettingsTile extends StatelessWidget {
  const UpdateSettingsTile({super.key});
  @override
  Widget build(BuildContext context) => !appUpdater.supported
      ? const SizedBox.shrink()
      : ListenableBuilder(
          listenable: appUpdater,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.only(top: 20),
            child: FormPanel(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.system_update_outlined),
                title: const Text('Обновление приложения'),
                subtitle: Text(
                  appUpdater.available
                      ? 'Доступна версия ${appUpdater.release!.version}'
                      : appUpdater.version.isNotEmpty
                      ? 'Версия ${appUpdater.version}'
                      : 'Проверить обновления',
                ),
                trailing: Icon(
                  appUpdater.available
                      ? Icons.download_rounded
                      : Icons.chevron_right,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => UpdateScreen(updater: appUpdater),
                  ),
                ),
              ),
            ),
          ),
        );
}

class UpdateScreen extends StatefulWidget {
  final AppUpdater updater;
  const UpdateScreen({super.key, required this.updater});
  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.updater.check());
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Обновление',
    body: ListenableBuilder(
      listenable: widget.updater,
      builder: (context, _) {
        final u = widget.updater, release = widget.updater.release;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            FormPanel(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (u.version.isNotEmpty)
                      Text(
                        'Установлена версия ${u.version}',
                        style: const TextStyle(color: hintGrey),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      u.checking
                          ? 'Проверяем обновления…'
                          : release != null
                          ? 'Доступна версия ${release.version}'
                          : u.error == null
                          ? 'Установлена последняя версия'
                          : 'Обновления',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (u.checking)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: LinearProgressIndicator(),
                      ),
                    if (release != null) ...[
                      const SizedBox(height: 12),
                      if (release.notes.isNotEmpty) Text(release.notes),
                      const SizedBox(height: 8),
                      Text(
                        '${(release.size / 1048576).toStringAsFixed(1)} МБ',
                        style: const TextStyle(color: hintGrey),
                      ),
                    ],
                    if (u.downloading) ...[
                      const SizedBox(height: 20),
                      LinearProgressIndicator(value: u.progress),
                      const SizedBox(height: 8),
                      Text('Скачивание: ${(u.progress * 100).floor()}%'),
                    ],
                  ],
                ),
              ),
            ),
            if (u.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  u.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (u.instruction != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(u.instruction!),
              ),
            const SizedBox(height: 20),
            if (u.downloading)
              OutlinedButton(
                onPressed: u.cancel,
                child: const Text('Отменить скачивание'),
              )
            else if (u.ready)
              FilledButton(
                onPressed: u.busy ? null : u.install,
                child: Text(u.installing ? 'Подготовка…' : 'Установить'),
              )
            else if (release != null)
              FilledButton(
                onPressed: u.busy ? null : u.download,
                child: const Text('Скачать обновление'),
              ),
            if (!u.downloading && !u.ready)
              TextButton(
                onPressed: u.busy ? null : u.check,
                child: const Text('Проверить обновления'),
              ),
          ],
        );
      },
    ),
  );
}
