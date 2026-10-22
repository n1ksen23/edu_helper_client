import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

DateTime moscowNow() => DateTime.now().toUtc().add(const Duration(hours: 3));
String iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class ApiError implements Exception {
  final String message;
  ApiError(this.message);
  @override
  String toString() => message;
}

class Api {
  static const base = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://eduhelper.cosmomine.ru/api/v1',
  );
  final http.Client client;
  final FlutterSecureStorage storage;
  String? access, refresh;
  int? editorGroup;
  String? role;
  Future<void>? refreshing;
  Api({http.Client? client, FlutterSecureStorage? storage})
    : client = client ?? http.Client(),
      storage = storage ?? const FlutterSecureStorage();
  bool canEdit(int? group) =>
      access != null && (role == 'admin' || editorGroup == group);
  Future<void> restore() async {
    // Browser sessions deliberately remain in memory; native refresh tokens use OS storage.
    if (kIsWeb) return;
    try {
      refresh = await storage.read(key: 'refresh');
      if (refresh != null) await renew();
    } on ApiError {
      await clear();
    } catch (_) {
      // A transient network/OS-storage failure must not erase an editor's session.
      // Public reading remains available and the next launch can retry refresh.
    }
  }

  Future<void> accept(Map<String, dynamic> data) async {
    access = data['access_token'];
    refresh = data['refresh_token'];
    editorGroup = data['group_id'];
    role = data['role'];
    if (!kIsWeb) await storage.write(key: 'refresh', value: refresh);
  }

  Future<void> renew() async {
    final r = await client
        .post(
          Uri.parse('$base/auth/refresh'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': refresh}),
        )
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw ApiError('Сессия истекла. Войдите снова');
    await accept(jsonDecode(r.body));
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    bool retry = true,
  }) async {
    try {
      final req = http.Request(method, Uri.parse('$base$path'));
      req.headers['Content-Type'] = 'application/json';
      if (access != null) req.headers['Authorization'] = 'Bearer $access';
      if (body != null) req.body = jsonEncode(body);
      final r = await client
          .send(req)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 25));
      if (r.statusCode == 401 &&
          refresh != null &&
          retry &&
          !path.startsWith('/auth/')) {
        refreshing ??= renew();
        try {
          await refreshing;
        } catch (_) {
          await clear();
          rethrow;
        } finally {
          refreshing = null;
        }
        return await request(path, method: method, body: body, retry: false);
      }
      if (r.statusCode >= 400) {
        final data = jsonDecode(utf8.decode(r.bodyBytes));
        final detail = data['detail'];
        throw ApiError(
          detail is String ? detail : 'Проверьте заполнение полей',
        );
      }
      return r.statusCode == 204 ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError(
        'Не удалось связаться с сервером. Проверьте интернет и повторите.',
      );
    }
  }

  Future<void> clear() async {
    access = refresh = role = null;
    editorGroup = null;
    if (!kIsWeb) await storage.delete(key: 'refresh');
  }
}

class AppState extends ChangeNotifier {
  final Api api;
  final SharedPreferences prefs;
  int? group;
  String groupName = '';
  bool dark = true;
  AppState(this.api, this.prefs) {
    group = prefs.getInt('group');
    groupName = prefs.getString('groupName') ?? '';
    dark = prefs.getBool('dark') ?? true;
  }
  Future<void> selectGroup(Map<String, dynamic> g) async {
    group = g['id'];
    groupName = g['name'];
    await prefs.setInt('group', group!);
    await prefs.setString('groupName', groupName);
    notifyListeners();
  }

  Future<void> theme(bool v) async {
    dark = v;
    await prefs.setBool('dark', v);
    notifyListeners();
  }

  void changed() => notifyListeners();
}

String currentStatus(Map<String, dynamic> day, DateTime now) {
  final lessons = List<Map<String, dynamic>>.from(day['lessons']);
  if (lessons.isEmpty) return 'Сегодня нет занятий';
  final minutes = now.hour * 60 + now.minute;
  int time(String s) {
    final p = s.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  final current = lessons
      .where((l) => time(l['start']) <= minutes && minutes < time(l['end']))
      .toList();
  if (current.isNotEmpty) {
    return 'Сейчас: ${current.map((l) => l['subject']).join(' / ')}';
  }
  final next = lessons.where((l) => time(l['start']) > minutes).toList();
  if (next.isEmpty) return 'Занятия закончились';
  if (minutes < time(lessons.first['start'])) {
    return 'Начало в ${next.first['start']}: ${next.first['subject']}';
  }
  final firstSlot = lessons.first['slot'] as int;
  final shortened = day['shortened'] == true;
  for (int slot = firstSlot; slot < next.first['slot']; slot++) {
    final start =
        510 +
        (slot - 1) * (shortened ? 70 : 110) +
        (!shortened && slot >= 3 ? 35 : 0);
    if (minutes >= start &&
        minutes < start + (shortened ? 60 : 100) &&
        !lessons.any((l) => l['slot'] == slot)) {
      return 'Сейчас окно · далее ${next.first['start']}';
    }
  }
  return 'Перемена · далее ${next.first['start']}: ${next.first['subject']}';
}

// On Sunday the schedule opens on the upcoming Monday; the calendar still includes Sunday.
DateTime initialScheduleDate(DateTime now) {
  final day = DateTime(now.year, now.month, now.day);
  return now.weekday == DateTime.sunday
      ? day.add(const Duration(days: 1))
      : day;
}
