import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'admin.dart';
import 'repeat.dart';
import 'editors.dart';
import 'design.dart';
import 'pages.dart';

final appProvider = Provider<AppState>((ref) => throw UnimplementedError());
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = Api();
  final state = AppState(api, await SharedPreferences.getInstance());
  runApp(
    ProviderScope(
      overrides: [appProvider.overrideWithValue(state)],
      child: const EduApp(),
    ),
  );
  unawaited(api.restore().then((_) => state.changed()));
}

class EduApp extends ConsumerStatefulWidget {
  const EduApp({super.key});
  @override
  ConsumerState<EduApp> createState() => _EduAppState();
}

class _EduAppState extends ConsumerState<EduApp> {
  late final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (c, s) => const HomeShell()),
      GoRoute(path: '/groups', builder: (c, s) => const GroupsScreen()),
      GoRoute(
        path: '/settings',
        builder: (c, s) => AppPage(
          title: 'Настройки',
          body: SettingsScreen(state: ref.read(appProvider)),
        ),
      ),
    ],
  );
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    return ListenableBuilder(
      listenable: state,
      builder: (c, _) => MaterialApp.router(
        title: 'EduHelper',
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        themeMode: state.dark ? ThemeMode.dark : ThemeMode.light,
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
      ),
    );
  }

  ThemeData theme(Brightness b) => originalTheme(b);
}

void showError(BuildContext context, Object error) {
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$error')));
  }
}

class LoadView extends StatelessWidget {
  final Future<dynamic> future;
  final Widget Function(dynamic) builder;
  final VoidCallback retry;
  const LoadView({
    super.key,
    required this.future,
    required this.builder,
    required this.retry,
  });
  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: future,
    builder: (c, s) {
      if (s.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48),
                const SizedBox(height: 16),
                Text('${s.error}', textAlign: TextAlign.center),
                TextButton(onPressed: retry, child: const Text('Повторить')),
              ],
            ),
          ),
        );
      }
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      return builder(s.data);
    },
  );
}

class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});
  @override
  ConsumerState<GroupsScreen> createState() => _GroupsState();
}

class _GroupsState extends ConsumerState<GroupsScreen> {
  late Future<dynamic> data;
  String query = '';
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    data = ref
        .read(appProvider)
        .api
        .request(
          '${ref.read(appProvider).api.role == 'admin' ? '/admin/groups' : '/groups'}?q=${Uri.encodeQueryComponent(query)}',
        );
  }

  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Выберите группу',
    action: IconButton(
      tooltip: 'Настройки',
      icon: const Icon(Icons.settings_outlined),
      onPressed: () => context.push('/settings'),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Номер группы',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) {
              query = v;
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 300), () {
                if (mounted) setState(load);
              });
            },
          ),
        ),
        Expanded(
          child: LoadView(
            future: data,
            retry: () => setState(load),
            builder: (rows) => rows.isEmpty
                ? const Center(child: Text('Опубликованных групп нет'))
                : ListView.builder(
                    itemCount: rows.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (c, i) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.school_outlined),
                        ),
                        title: Text(rows[i]['name']),

                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await ref.read(appProvider).selectGroup(rows[i]);
                          if (context.mounted) context.go('/');
                        },
                      ),
                    ),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      GroupRequestScreen(state: ref.read(appProvider)),
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Добавить свою группу'),
            ),
          ),
        ),
      ],
    ),
  );
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<HomeShell> {
  int tab = 0, revision = 0;
  String currentDate = iso(moscowNow());
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {
          final next = iso(moscowNow());
          if (next != currentDate) {
            currentDate = next;
            revision++;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    return ListenableBuilder(
      listenable: state,
      builder: (c, _) {
        if (state.group == null) return const GroupsScreen();
        return PopScope(
          canPop: tab == 0,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) setState(() => tab = 0);
          },
          child: Scaffold(
            body: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ['Задания', 'Расписание', 'Календарь'][tab],
                                    style: display(34, FontWeight.w800),
                                  ),
                                  const SizedBox(height: 3),
                                  GestureDetector(
                                    onTap: () => context.push('/groups'),
                                    child: Text(
                                      'Группа ${state.groupName}',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        color: hintGrey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (tab == 0 && state.api.canEdit(state.group))
                              IconButton.filled(
                                tooltip: 'Добавить ДЗ',
                                onPressed: () async {
                                  await editHomework(context, state);
                                  if (mounted) setState(() => revision++);
                                },
                                icon: const Icon(
                                  Icons.add,
                                  size: 26,
                                  color: Colors.white,
                                ),
                              ),
                            IconButton(
                              tooltip: 'Настройки',
                              onPressed: () => context.push('/settings'),
                              icon: const Icon(
                                Icons.settings_outlined,
                                size: 24,
                              ),
                              color: hintGrey,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: [
                          TasksScreen(
                            key: ValueKey('tasks-${state.group}-$revision'),
                            state: state,
                            onChanged: () => setState(() => revision++),
                          ),
                          ScheduleScreen(
                            key: ValueKey('schedule-${state.group}-$revision'),
                            state: state,
                          ),
                          CalendarScreen(
                            key: ValueKey('calendar-${state.group}-$revision'),
                            state: state,
                          ),
                        ][tab],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            bottomNavigationBar: OriginalTabBar(
              index: tab,
              onChanged: (v) => setState(() => tab = v),
            ),
          ),
        );
      },
    );
  }
}

class TasksScreen extends StatefulWidget {
  final AppState state;
  final VoidCallback onChanged;
  const TasksScreen({super.key, required this.state, required this.onChanged});
  @override
  State<TasksScreen> createState() => _TasksState();
}

class _TasksState extends State<TasksScreen> {
  bool archive = false, bySubject = false, loadingMore = false;
  String? cursor;
  List<dynamic> items = [], active = [];
  late Future<dynamic> data;
  AppState get s => widget.state;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    data = fetch();
  }

  Future<dynamic> fetch() async {
    final date = iso(moscowNow());
    final results = await Future.wait([
      s.api.request('/groups/${s.group}/homework?archive=$archive'),
      s.api.request('/groups/${s.group}/calendar?start=$date&end=$date'),
      if (archive) s.api.request('/groups/${s.group}/homework'),
    ]);
    items = results[0]['items'];
    cursor = results[0]['next_cursor'];
    active = archive ? results[2]['items'] : items;
    return results[1][0];
  }

  Future<void> more() async {
    setState(() => loadingMore = true);
    try {
      final r = await s.api.request(
        '/groups/${s.group}/homework?archive=true&cursor=${Uri.encodeQueryComponent(cursor!)}',
      );
      if (mounted) {
        setState(() {
          items.addAll(r['items']);
          cursor = r['next_cursor'];
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) => LoadView(
    future: data,
    retry: () => setState(load),
    builder: (day) {
      final list = List<dynamic>.from(items);
      if (bySubject) {
        list.sort((a, b) {
          final comparison = (a['subject'] as String).toLowerCase().compareTo(
            (b['subject'] as String).toLowerCase(),
          );
          return comparison != 0
              ? comparison
              : (a['due_date'] as String).compareTo(b['due_date']);
        });
      }
      return RefreshIndicator(
        onRefresh: () async {
          setState(load);
          await data;
        },
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: list.length + 2,
          itemBuilder: (c, i) {
            if (i == 0) {
              return Column(
                children: [
                  TodayHero(day: day, group: s.groupName, active: active),
                  const SizedBox(height: 16),
                  SegmentControl<bool>(
                    value: archive,
                    labels: const {false: 'Актуальные', true: 'Архив'},
                    onChanged: (v) => setState(() {
                      archive = v;
                      load();
                    }),
                  ),
                  const SizedBox(height: 10),
                  SegmentControl<bool>(
                    value: bySubject,
                    small: true,
                    labels: const {false: 'По сроку', true: 'По предметам'},
                    onChanged: (v) => setState(() => bySubject = v),
                  ),
                  const SizedBox(height: 14),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Text(
                        archive ? 'Архив пуст' : 'Заданий нет',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w300,
                          fontStyle: FontStyle.italic,
                          color: hintGrey,
                        ),
                      ),
                    ),
                ],
              );
            }
            if (i == list.length + 1) {
              return cursor == null
                  ? const SizedBox()
                  : TextButton(
                      onPressed: loadingMore ? null : more,
                      child: Text(loadingMore ? 'Загрузка…' : 'Загрузить ещё'),
                    );
            }
            final h = list[i - 1];
            final first =
                i == 1 || bySubject && list[i - 2]['subject'] != h['subject'];
            final last =
                i == list.length ||
                bySubject && list[i]['subject'] != h['subject'];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bySubject && first)
                  Padding(
                    padding: EdgeInsets.fromLTRB(14, i == 1 ? 6 : 22, 14, 7),
                    child: Text(
                      (h['subject'] as String).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .5,
                        color: hintGrey,
                      ),
                    ),
                  ),
                HomeworkRow(
                  homework: h,
                  archive: archive,
                  showSubject: !bySubject,
                  first: first,
                  last: last,
                  onEdit: s.api.canEdit(s.group)
                      ? () async {
                          await editHomework(context, s, h);
                          if (mounted) setState(load);
                        }
                      : null,
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

class ScheduleScreen extends StatefulWidget {
  final AppState state;
  const ScheduleScreen({super.key, required this.state});
  @override
  State<ScheduleScreen> createState() => _ScheduleState();
}

class _ScheduleState extends State<ScheduleScreen> {
  late DateTime monday;
  int selectedDay = 0;
  late Future<dynamic> data;
  @override
  void initState() {
    super.initState();
    final initial = initialScheduleDate(moscowNow());
    monday = initial.subtract(Duration(days: initial.weekday - 1));
    selectedDay = initial.weekday - 1;
    load();
  }

  void load() {
    data = fetch();
  }

  Future<dynamic> fetch() async {
    final path =
        '/groups/${widget.state.group}/calendar?start=${iso(monday)}&end=${iso(monday.add(const Duration(days: 5)))}';
    return widget.state.api.request(path);
  }

  @override
  Widget build(BuildContext context) => LoadView(
    future: data,
    retry: () => setState(load),
    builder: (days) => ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        SegmentControl<int>(
          small: true,
          value: selectedDay,
          labels: const {0: 'Пн', 1: 'Вт', 2: 'Ср', 3: 'Чт', 4: 'Пт', 5: 'Сб'},
          onChanged: (v) => setState(() => selectedDay = v),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              tooltip: 'Предыдущая неделя',
              onPressed: () => setState(() {
                monday = monday.subtract(const Duration(days: 7));
                load();
              }),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              '${DateFormat('d MMM', 'ru').format(monday)} — ${DateFormat('d MMM', 'ru').format(monday.add(const Duration(days: 5)))}',
              style: const TextStyle(fontSize: 14, color: hintGrey),
            ),
            IconButton(
              tooltip: 'Следующая неделя',
              onPressed: () => setState(() {
                monday = monday.add(const Duration(days: 7));
                load();
              }),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        if (widget.state.api.canEdit(widget.state.group))
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.copy_all_outlined, size: 19),
              label: const Text('Повторить неделю'),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RepeatScheduleScreen(
                      state: widget.state,
                      source: monday,
                      wholeWeek: true,
                    ),
                  ),
                );
                if (mounted) setState(load);
              },
            ),
          ),
        DayCard(
          day: days[selectedDay],
          state: widget.state,
          onChanged: () => setState(load),
        ),
      ],
    ),
  );
}

class DayCard extends StatelessWidget {
  final Map<String, dynamic> day;
  final AppState state;
  final VoidCallback onChanged;
  const DayCard({
    super.key,
    required this.day,
    required this.state,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final lessons = List<Map<String, dynamic>>.from(day['lessons']);
    final last = lessons.isEmpty
        ? 0
        : lessons.map((l) => l['slot'] as int).reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 0, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      capital(
                        DateFormat(
                          'EEEE, d MMMM',
                          'ru',
                        ).format(DateTime.parse(day['date'])),
                      ),
                      style: display(20, FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${day['week'] == 'upper' ? 'Верхняя' : 'Нижняя'} неделя${day['shortened'] ? ' · сокращённый день' : ''}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: hintGrey,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.api.canEdit(state.group))
                IconButton(
                  tooltip: 'Изменить расписание дня',
                  icon: const Icon(Icons.edit_outlined, size: 21),
                  onPressed: () async {
                    await editSchedule(context, state, day);
                    onChanged();
                  },
                ),
            ],
          ),
        ),
        if (last == 0)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'Пар нет',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w300,
                  fontStyle: FontStyle.italic,
                  color: hintGrey,
                ),
              ),
            ),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ColoredBox(
              color: cardColor(context),
              child: Column(
                children: [
                  for (int slot = 1; slot <= last; slot++)
                    lessonRow(context, lessons, slot),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget lessonRow(
    BuildContext context,
    List<Map<String, dynamic>> lessons,
    int slot,
  ) {
    final rows = lessons.where((l) => l['slot'] == slot).toList();
    final times = timeFor(slot, day['shortened']).split('–');
    final now = moscowNow();
    int minutes(String t) {
      final p = t.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }

    final current =
        day['date'] == iso(now) &&
        now.hour * 60 + now.minute >= minutes(times[0]) &&
        now.hour * 60 + now.minute < minutes(times[1]);
    return Column(
      children: [
        if (slot > 1)
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Divider(
              height: .5,
              thickness: .5,
              color: hintGrey.withValues(alpha: .18),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            border: current
                ? Border(
                    left: BorderSide(
                      width: 4,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                : null,
          ),
          padding: EdgeInsets.fromLTRB(current ? 10 : 14, 13, 14, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 50,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(times[0], style: display(16, FontWeight.w600)),
                    Text(
                      times[1],
                      style: display(16, FontWeight.w300, color: hintGrey),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: rows.isEmpty
                    ? const Text(
                        'Окно',
                        style: TextStyle(
                          fontSize: 17,
                          color: hintGrey,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final l in rows)
                            Padding(
                              padding: EdgeInsets.only(
                                top: l == rows.first ? 0 : 10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l['subject'],
                                    style: const TextStyle(
                                      fontSize: 17,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    [
                                          l['teacher'],
                                          (l['room'] as String? ?? '')
                                                  .isNotEmpty
                                              ? '${RegExp(r'^\d').hasMatch(l['room']) ? 'ауд. ' : ''}${l['room']}'
                                              : '',
                                          if (l['subgroup_id'] != null)
                                            l['subgroup_name'] ??
                                                'Подгруппа ${l['subgroup_id']}',
                                        ]
                                        .where((v) => v != null && v != '')
                                        .join(' · '),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: hintGrey,
                                    ),
                                  ),
                                  if (current)
                                    Text(
                                      'идёт сейчас',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CalendarScreen extends StatefulWidget {
  final AppState state;
  const CalendarScreen({super.key, required this.state});
  @override
  State<CalendarScreen> createState() => _CalendarState();
}

class _CalendarState extends State<CalendarScreen> {
  DateTime selected = DateTime(
    moscowNow().year,
    moscowNow().month,
    moscowNow().day,
  );
  late DateTime month;
  late Future<dynamic> data;
  @override
  void initState() {
    super.initState();
    month = DateTime(selected.year, selected.month);
    load();
  }

  void load() {
    data = widget.state.api.request(
      '/groups/${widget.state.group}/calendar?start=${iso(month)}&end=${iso(DateTime(month.year, month.month + 1, 0))}',
    );
  }

  @override
  Widget build(BuildContext context) => LoadView(
    future: data,
    retry: () => setState(load),
    builder: (days) {
      final index = selected.month == month.month ? selected.day - 1 : 0;
      final day = days[index];
      final offset = month.weekday - 1;
      final parts = <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  capital(DateFormat('LLLL yyyy', 'ru').format(month)),
                  style: display(22, FontWeight.w600),
                ),
              ),
              monthButton(Icons.chevron_left, 'Предыдущий месяц', -1),
              const SizedBox(width: 8),
              monthButton(Icons.chevron_right, 'Следующий месяц', 1),
            ],
          ),
        ),
        Container(
          key: const ValueKey('month-grid-panel'),
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          decoration: BoxDecoration(
            color: cardColor(context),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  for (final label in [
                    'Пн',
                    'Вт',
                    'Ср',
                    'Чт',
                    'Пт',
                    'Сб',
                    'Вс',
                  ])
                    Expanded(
                      child: Center(
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: hintGrey,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisExtent:
                      MediaQuery.textScalerOf(context).scale(18) > 25 ? 60 : 48,
                ),
                itemCount: days.length + offset,
                itemBuilder: (c, i) {
                  if (i < offset) return const SizedBox();
                  final n = i - offset + 1;
                  final row = days[n - 1];
                  final tasks = row['homework'] as List;
                  final isSelected = selected.day == n;
                  final now = moscowNow();
                  final isToday =
                      iso(DateTime(month.year, month.month, n)) == iso(now);
                  final past = DateTime(
                    month.year,
                    month.month,
                    n,
                  ).isBefore(DateTime(now.year, now.month, now.day));
                  final blue = Theme.of(context).colorScheme.primary;
                  return Center(
                    child: SizedBox(
                      width: 42,
                      height: MediaQuery.textScalerOf(context).scale(18) > 25
                          ? 54
                          : 42,
                      child: Material(
                        color: isSelected ? blue : Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => setState(
                            () =>
                                selected = DateTime(month.year, month.month, n),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$n',
                                style: display(
                                  18,
                                  isSelected
                                      ? FontWeight.w600
                                      : isToday
                                      ? FontWeight.w800
                                      : FontWeight.w400,
                                  color: isSelected
                                      ? Colors.white
                                      : isToday
                                      ? blue
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: tasks.isEmpty
                                      ? Colors.transparent
                                      : isSelected
                                      ? Colors.white
                                      : past
                                      ? hintGrey
                                      : blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        DayCard(day: day, state: widget.state, onChanged: () => setState(load)),
        if ((day['homework'] as List).isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 22, 14, 7),
            child: Text(
              'ЗАДАНИЯ',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: hintGrey,
                letterSpacing: .5,
              ),
            ),
          ),
          for (int i = 0; i < (day['homework'] as List).length; i++)
            HomeworkRow(
              homework: day['homework'][i],
              archive: DateTime.parse(day['date']).isBefore(
                DateTime(moscowNow().year, moscowNow().month, moscowNow().day),
              ),
              first: i == 0,
              last: i == day['homework'].length - 1,
              onEdit: widget.state.api.canEdit(widget.state.group)
                  ? () async {
                      await editHomework(
                        context,
                        widget.state,
                        day['homework'][i],
                      );
                      if (mounted) setState(load);
                    }
                  : null,
            ),
        ],
        if (widget.state.api.canEdit(widget.state.group))
          TextButton.icon(
            onPressed: () async {
              await editHomework(context, widget.state, null, selected);
              if (mounted) setState(load);
            },
            icon: const Icon(Icons.add),
            label: const Text('Добавить задание'),
          ),
      ];
      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 700 &&
              MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 320,
                    child: Column(children: parts.take(2).toList()),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: parts.skip(3).toList(),
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: parts,
          );
        },
      );
    },
  );
  Widget monthButton(IconData icon, String tooltip, int shift) => Material(
    color: cardColor(context),
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: tooltip,
      onPressed: () => setState(() {
        month = DateTime(month.year, month.month + shift);
        selected = month;
        load();
      }),
      icon: Icon(icon),
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      padding: EdgeInsets.zero,
    ),
  );
}

class SettingsScreen extends StatefulWidget {
  final AppState state;
  const SettingsScreen({super.key, required this.state});
  @override
  State<SettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsScreen> {
  final password = TextEditingController();
  bool admin = false, busy = false;
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (busy) return;
    if (password.text.isEmpty) {
      showError(context, 'Введите пароль');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => busy = true);
    final s = widget.state;
    try {
      await s.api.accept(
        await s.api.request(
          '/auth/login',
          method: 'POST',
          body: {'password': password.text, if (!admin) 'group_id': s.group},
        ),
      );
      password.clear();
      s.changed();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: cardColor(context),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: const Text(
                    'Тёмная тема',
                    style: TextStyle(fontSize: 17),
                  ),
                  value: s.dark,
                  onChanged: s.theme,
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 16),
                  child: Divider(height: .5, thickness: .5),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: const Icon(Icons.school_outlined),
                  title: const Text('Группа', style: TextStyle(fontSize: 17)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.groupName,
                        style: const TextStyle(fontSize: 16, color: hintGrey),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right, color: hintGrey),
                    ],
                  ),
                  onTap: () => context.push('/groups'),
                ),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 26, 14, 8),
          child: Text(
            'РЕДАКТИРОВАНИЕ',
            style: TextStyle(
              fontSize: 13,
              color: hintGrey,
              fontWeight: FontWeight.w600,
              letterSpacing: .5,
            ),
          ),
        ),
        if (s.api.canEdit(s.group)) ...[
          FormPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.verified_user_outlined),
                  title: Text(
                    s.api.role == 'admin' ? 'Администратор' : 'Редактор',
                  ),
                ),
                if (s.api.role == 'admin') ...[
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: const Text('Заявки и группы'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => AdminScreen(state: s)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () async {
              try {
                await s.api.request('/auth/logout', method: 'POST');
              } catch (_) {}
              await s.api.clear();
              s.changed();
              if (mounted) setState(() {});
            },
            child: const Text('Выйти'),
          ),
        ] else ...[
          FormPanel(
            child: Column(
              children: [
                TextField(
                  controller: password,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => login(),
                  decoration: InputDecoration(
                    labelText: admin ? 'Мастер-пароль' : 'Пароль группы',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'Вход администратора',
                    style: TextStyle(fontSize: 15),
                  ),
                  value: admin,
                  onChanged: busy ? null : (v) => setState(() => admin = v!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : login,
            child: Text(busy ? 'Вход…' : 'Войти'),
          ),
        ],
      ],
    );
  }
}
