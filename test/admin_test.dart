import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:edu_helper/admin.dart';
import 'package:edu_helper/api.dart';
import 'package:edu_helper/design.dart';

void main() {
  testWidgets(
    'Admin reads contact and accepts request with a generated password',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      Map<String, dynamic>? submitted;
      final api = Api(
        client: MockClient((r) async {
          Object data;
          if (r.url.path.endsWith('/accept')) {
            submitted = jsonDecode(r.body);
            data = {'id': 9, ...submitted!};
          } else if (r.url.path.endsWith('/group-requests')) {
            data = {
              'items': [
                {
                  'id': 1,
                  'group_number': '5101',
                  'contacts': 'head@example.org',
                  'status': 'pending',
                  'created_at': '2026-10-22T12:00:00Z',
                },
              ],
              'next_cursor': null,
            };
          } else {
            data = <Object>[];
          }
          return http.Response(
            jsonEncode(data),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      api.role = 'admin';
      api.access = 'test';
      final state = AppState(api, await SharedPreferences.getInstance());
      await t.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: originalTheme(Brightness.dark),
          home: AdminScreen(state: state),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('head@example.org'), findsOneWidget);
      await t.tap(find.text('Принять и создать группу'));
      await t.pumpAndSettle();
      expect(find.text('5101'), findsOneWidget);
      await t.tap(find.text('Сгенерировать пароль'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Создать группу и принять заявку'));
    await t.pumpAndSettle();
      await t.tap(find.text('Создать группу и принять заявку'));
      await t.pumpAndSettle();
      expect(submitted!['name'], '5101');
      expect((submitted!['password'] as String).length, 20);
      expect(submitted!['published'], true);
      expect(find.text('Группа сохранена'), findsOneWidget);
      expect(find.text('Скопировать группу и пароль'), findsOneWidget);
      expect(find.text('head@example.org'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
