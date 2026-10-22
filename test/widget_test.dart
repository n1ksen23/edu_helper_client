import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:edu_helper/main.dart';
import 'package:edu_helper/api.dart';
import 'package:edu_helper/editors.dart';
import 'package:edu_helper/design.dart';
import 'package:edu_helper/pages.dart';
import 'package:edu_helper/repeat.dart';

Map<String, dynamic> day(String date) => {
  'date': date,
  'week':
      DateTime.parse(date)
                  .subtract(Duration(days: DateTime.parse(date).weekday - 1))
                  .difference(DateTime(2026, 10, 19))
                  .inDays ~/
              7 %
              2 ==
          0
      ? 'lower'
      : 'upper',
  'shortened': false,
  'lessons': [
    {
      'slot': 2,
      'subject': 'Математика',
      'teacher': 'Иванов',
      'room': '101',
      'week': 'both',
      'subgroup_id': null,
      'start': '10:20',
      'end': '12:00',
    },
  ],
  'homework': [],
};
Future<AppState> state({bool selected = true, bool failure = false}) async {
  SharedPreferences.setMockInitialValues(
    selected ? {'group': 1, 'groupName': '4992'} : {},
  );
  final api = Api(
    client: MockClient((req) async {
      if (failure) {
        return http.Response(
          jsonEncode({'detail': 'Ошибка сервера'}),
          503,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      dynamic result;
      final p = req.url.path;
      if (p.endsWith('/auth/login')) {
        result = {
          'access_token': 'access',
          'refresh_token': 'refresh-with-enough-characters',
          'group_id': 1,
          'role': 'editor',
        };
      } else if (p.endsWith('/groups')) {
        result = [
          {'id': 1, 'name': '4992'},
        ];
      } else if (p.endsWith('/calendar')) {
        final start = DateTime.parse(req.url.queryParameters['start']!);
        final end = DateTime.parse(req.url.queryParameters['end']!);
        result = [
          for (int n = 0; n <= end.difference(start).inDays; n++)
            day(iso(start.add(Duration(days: n)))),
        ];
      } else if (p.endsWith('/homework') && req.method == 'GET') {
        result = {
          'items': [
            {
              'id': 5,
              'subject': 'Алгебра',
              'text': 'Решить задачи',
              'due_date': iso(moscowNow()),
            },
          ],
          'next_cursor': null,
        };
      } else if (p.endsWith('/subgroups')) {
        result = [];
      } else if (p.contains('/days/')) {
        result = day(iso(moscowNow()));
      } else {
        result = {'id': 5};
      }
      return http.Response(
        jsonEncode(result),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  return AppState(api, await SharedPreferences.getInstance());
}

Widget app(AppState s) => ProviderScope(
  overrides: [appProvider.overrideWithValue(s)],
  child: const EduApp(),
);
void main() {
  test('Current lesson, gap, before and after classes', () {
    final d = day('2026-10-22');
    expect(
      currentStatus(d, DateTime(2026, 10, 22, 11)),
      contains('Сейчас: Математика'),
    );
    expect(currentStatus(d, DateTime(2026, 10, 22, 8)), contains('Начало'));
    expect(
      currentStatus(d, DateTime(2026, 10, 22, 20)),
      contains('закончились'),
    );
    expect(timeFor(6, false), '18:15–19:55');
    expect(timeFor(6, true), '14:20–15:20');
  });
  testWidgets('Guest chooses group and navigates all tabs', (t) async {
    final s = await state(selected: false);
    await t.pumpWidget(app(s));
    await t.pumpAndSettle();
    expect(find.text('Выберите группу'), findsOneWidget);
    await t.tap(find.text('4992'));
    await t.pumpAndSettle();
    expect(find.text('Решить задачи'), findsOneWidget);
    expect(find.byTooltip('Добавить ДЗ'), findsNothing);
    await t.tap(find.text('Расписание'));
    await t.pumpAndSettle();
    expect(find.text('Математика'), findsWidgets);
    expect(find.text('Окно'), findsWidgets);
    await t.tap(find.text('Календарь'));
    await t.pumpAndSettle();
    expect(find.text('Пн'), findsOneWidget);
    await t.tap(find.byTooltip('Настройки'));
    await t.pumpAndSettle();
    expect(find.text('Пароль группы'), findsOneWidget);
    await t.tap(find.text('Тёмная тема'));
    await t.pumpAndSettle();
    expect(s.dark, isFalse);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('API errors have retry', (t) async {
    final s = await state(failure: true);
    await t.pumpWidget(app(s));
    await t.pumpAndSettle();
    expect(find.text('Повторить'), findsOneWidget);
    expect(find.textContaining('Ошибка сервера'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('Editor sees homework controls', (t) async {
    final s = await state();
    s.api.access = 'test';
    s.api.role = 'editor';
    s.api.editorGroup = 1;
    await t.pumpWidget(app(s));
    await t.pumpAndSettle();
    expect(find.byTooltip('Добавить ДЗ'), findsOneWidget);
    final addIcon = t.widget<Icon>(
      find.descendant(
        of: find.byTooltip('Добавить ДЗ'),
        matching: find.byIcon(Icons.add),
      ),
    );
    expect(addIcon.color, Colors.white);
    await t.tap(find.byTooltip('Добавить ДЗ'));
    await t.pumpAndSettle();
    expect(find.text('Новое задание'), findsOneWidget);
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    expect(find.text('Заполните поле'), findsNWidgets(2));
    await t.enterText(find.byType(TextFormField).at(0), 'Геометрия');
    await t.enterText(
      find.byType(TextFormField).at(1),
      'Доказать теорему\nЗадача 3',
    );
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    expect(find.text('Новое задание'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('Small phone and large text avoid overflow', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final s = await state();
    await t.pumpWidget(
      ProviderScope(
        overrides: [appProvider.overrideWithValue(s)],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(1.8),
            ),
            child: Scaffold(
              body: TasksScreen(state: s, onChanged: () {}),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('Editor login and Android back navigation', (t) async {
    FlutterSecureStorage.setMockInitialValues({});
    final s = await state();
    await t.pumpWidget(app(s));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Настройки'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'group-password-123');
    await t.tap(find.text('Войти'));
    await t.pumpAndSettle();
    expect(s.api.canEdit(1), isTrue);
    expect(
      await s.api.storage.read(key: 'refresh'),
      'refresh-with-enough-characters',
    );
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Решить задачи'), findsOneWidget);
    await t.tap(find.byTooltip('Изменить ДЗ'));
    await t.pumpAndSettle();
    expect(find.text('Редактирование ДЗ'), findsOneWidget);
    await t.enterText(find.byType(TextFormField).at(1), 'Обновлённое задание');
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    expect(find.text('Редактирование ДЗ'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('Minute clock refresh preserves archive selection', (t) async {
    final s = await state();
    await t.pumpWidget(app(s));
    await t.pumpAndSettle();
    await t.tap(find.text('Архив'));
    await t.pumpAndSettle();
    expect(
      t
          .widget<SegmentControl<bool>>(find.byType(SegmentControl<bool>).first)
          .value,
      true,
    );
    await t.pump(const Duration(minutes: 1));
    await t.pumpAndSettle();
    expect(
      t
          .widget<SegmentControl<bool>>(find.byType(SegmentControl<bool>).first)
          .value,
      true,
    );
    await t.pumpWidget(const SizedBox());
  });
  test('Sunday opens upcoming Monday', () {
    expect(initialScheduleDate(DateTime(2026, 10, 25)), DateTime(2026, 10, 26));
    expect(initialScheduleDate(DateTime(2026, 10, 24)), DateTime(2026, 10, 24));
  });
  testWidgets('Schedule has six days and follows date parity', (t) async {
    final s = await state();
    await t.pumpWidget(app(s));
    await t.pumpAndSettle();
    await t.tap(find.text('Расписание'));
    await t.pumpAndSettle();
    expect(find.text('Вс'), findsNothing);
    expect(find.byType(SegmentControl<String>), findsNothing);
    await t.tap(find.byTooltip('Следующая неделя'));
    await t.pumpAndSettle();
    final initial = initialScheduleDate(moscowNow());
    final next = initial.add(const Duration(days: 7));
    expect(
      find.text(
        day(iso(next))['week'] == 'upper' ? 'Верхняя неделя' : 'Нижняя неделя',
      ),
      findsOneWidget,
    );
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('Submit group application validates and confirms', (t) async {
    final s = await state(selected: false);
    await t.pumpWidget(app(s));
    await t.pumpAndSettle();
    await t.tap(find.text('Добавить свою группу'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Отправить заявку'));
    await t.tap(find.text('Отправить заявку'));
    await t.pumpAndSettle();
    expect(find.text('Укажите номер группы'), findsOneWidget);
    await t.enterText(find.byType(TextFormField).at(0), '5101');
    await t.enterText(find.byType(TextFormField).at(1), 'test@example.org');
    await t.ensureVisible(find.text('Отправить заявку'));
    await t.tap(find.text('Отправить заявку'));
    await t.pumpAndSettle();
    expect(find.text('Заявка отправлена'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('Monitor layout bounds settings and calendar', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final s = await state();
    await t.pumpWidget(app(s));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Настройки'));
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(FormPanel)).width, lessThanOrEqualTo(640));
    expect(t.getCenter(find.byType(FormPanel)).dx, closeTo(960, 1));
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    await t.tap(find.text('Календарь'));
    await t.pumpAndSettle();
    final grid = t.getRect(find.byKey(const ValueKey('month-grid-panel')));
    final details = t.getRect(find.byType(DayCard));
    expect(grid.height, lessThan(350));
    expect(grid.width, lessThanOrEqualTo(320));
    expect(details.left, greaterThan(grid.right));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('Fixed subgroup labels and pair arrow controls', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: originalTheme(Brightness.dark),
        home: const LessonEditor(),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Неделя'), findsNothing);
    expect(find.text('Обе недели'), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(3));
    await t.tap(find.byTooltip('Увеличить номер пары'));
    await t.pump();
    expect(find.text('2'), findsOneWidget);
    await t.tap(find.byTooltip('Уменьшить номер пары'));
    await t.pump();
    expect(find.text('1'), findsOneWidget);
    await t.tap(find.byType(DropdownButtonFormField<int>));
    await t.pumpAndSettle();
    expect(find.text('Пг 1'), findsOneWidget);
    expect(find.text('Пг 2'), findsOneWidget);
    expect(find.text('Пг 3'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('Editor settings have no schedule or subgroup management', (
    t,
  ) async {
    final s = await state();
    s.api.access = 'test';
    s.api.role = 'editor';
    s.api.editorGroup = 1;
    await t.pumpWidget(app(s));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Настройки'));
    await t.pumpAndSettle();
    expect(find.text('Недельные шаблоны'), findsNothing);
    expect(find.text('Подгруппы'), findsNothing);
    expect(find.text('Редактор'), findsOneWidget);
    expect(find.text('Заявки и группы'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  for (final width in [360.0, 1920.0]) {
    testWidgets('Editors constrain layout at width $width', (t) async {
      t.view.physicalSize = Size(width, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final s = await state();
      for (final editor in <Widget>[
        const LessonEditor(),
        ScheduleEditor(state: s, day: day('2026-10-22')),
        RepeatScheduleScreen(
          state: s,
          source: DateTime(2026, 10, 19),
          wholeWeek: true,
        ),
      ]) {
        await t.pumpWidget(
          MaterialApp(theme: originalTheme(Brightness.dark), home: editor),
        );
        await t.pumpAndSettle();
        final list = t.getRect(find.byType(ListView).first);
        expect(list.width, lessThanOrEqualTo(640));
        expect(list.center.dx, closeTo(width / 2, 1));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      }
    });
  }
}
