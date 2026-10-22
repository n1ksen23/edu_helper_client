import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'main.dart' show showError;

Future<void> editHomework(
  BuildContext context,
  AppState s, [
  Map<String, dynamic>? h,
  DateTime? date,
]) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => HomeworkEditor(state: s, homework: h, date: date),
  ),
);

class HomeworkEditor extends StatefulWidget {
  final AppState state;
  final Map<String, dynamic>? homework;
  final DateTime? date;
  const HomeworkEditor({
    super.key,
    required this.state,
    this.homework,
    this.date,
  });
  @override
  State<HomeworkEditor> createState() => _HomeworkEditorState();
}

class _HomeworkEditorState extends State<HomeworkEditor> {
  final form = GlobalKey<FormState>();
  late TextEditingController subject, text;
  late DateTime due;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    subject = TextEditingController(text: widget.homework?['subject'] ?? '');
    text = TextEditingController(text: widget.homework?['text'] ?? '');
    due = widget.homework != null
        ? DateTime.parse(widget.homework!['due_date'])
        : widget.date ?? moscowNow();
  }

  @override
  void dispose() {
    subject.dispose();
    text.dispose();
    super.dispose();
  }

  Future<void> save({bool delete = false}) async {
    if (!delete && !form.currentState!.validate()) return;
    if (delete && !await confirm(context, 'Удалить задание?')) return;
    setState(() => busy = true);
    try {
      final h = widget.homework;
      await widget.state.api.request(
        '/groups/${widget.state.group}/homework${h == null ? '' : '/${h['id']}'}',
        method: delete
            ? 'DELETE'
            : h == null
            ? 'POST'
            : 'PUT',
        body: delete
            ? null
            : {
                'subject': subject.text.trim(),
                'text': text.text.trim(),
                'due_date': iso(due),
              },
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.homework == null ? 'Новое задание' : 'Редактирование ДЗ',
      ),
      actions: [
        if (widget.homework != null)
          IconButton(
            tooltip: 'Удалить',
            onPressed: busy ? null : () => save(delete: true),
            icon: const Icon(Icons.delete_outline),
          ),
      ],
    ),
    body: SafeArea(
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: subject,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Предмет'),
              validator: requiredText,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: text,
              minLines: 5,
              maxLines: 14,
              maxLength: 20000,
              decoration: const InputDecoration(
                labelText: 'Задание',
                alignLabelWithHint: true,
              ),
              validator: requiredText,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Срок сдачи'),
              subtitle: Text(DateFormat('d MMMM yyyy', 'ru').format(due)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: due,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => due = d);
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? 'Сохранение…' : 'Сохранить'),
            ),
          ],
        ),
      ),
    ),
  );
}

String? requiredText(String? v) =>
    v == null || v.trim().isEmpty ? 'Заполните поле' : null;
Future<bool> confirm(BuildContext context, String title) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    ) ??
    false;
Future<void> editSchedule(
  BuildContext context,
  AppState s,
  Map<String, dynamic> day,
) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => ScheduleEditor(state: s, day: day),
  ),
);
Future<void> editTemplate(BuildContext context, AppState s) async {
  final weekday = await showDialog<int>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('Шаблон дня недели'),
      children: [
        for (int n = 1; n <= 6; n++)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, n),
            child: Text(
              [
                'Понедельник',
                'Вторник',
                'Среда',
                'Четверг',
                'Пятница',
                'Суббота',
              ][n - 1],
            ),
          ),
      ],
    ),
  );
  if (weekday == null || !context.mounted) return;
  try {
    final data = await s.api.request('/groups/${s.group}/templates/$weekday');
    if (context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ScheduleEditor(
            state: s,
            day: {
              ...data,
              'date': iso(
                DateTime(2026, 10, 19).add(Duration(days: weekday - 1)),
              ),
            },
            weekday: weekday,
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

class ScheduleEditor extends StatefulWidget {
  final AppState state;
  final Map<String, dynamic> day;
  final int? weekday;
  const ScheduleEditor({
    super.key,
    required this.state,
    required this.day,
    this.weekday,
  });
  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  late bool shortened;
  late List<Map<String, dynamic>> lessons;
  List<dynamic> subgroups = [];
  bool busy = false;
  late Future<void> loading;
  AppState get s => widget.state;
  DateTime get date => DateTime.parse(widget.day['date']);
  @override
  void initState() {
    super.initState();
    shortened = widget.day['shortened'];
    lessons = List<Map<String, dynamic>>.from(
      (widget.day['lessons'] as List).map((l) => Map<String, dynamic>.from(l)),
    );
    loading = load();
  }

  Future<void> load() async {
    subgroups = await s.api.request('/groups/${s.group}/subgroups');
    // Fetch the raw day for editing so upper/lower rows are not lost by the public calendar filter.
    if (widget.weekday == null) {
      final raw = await s.api.request(
        '/groups/${s.group}/days/${widget.day['date']}',
      );
      if (raw != null) {
        lessons = List<Map<String, dynamic>>.from(
          (raw['lessons'] as List).map((l) => Map<String, dynamic>.from(l)),
        );
        shortened = raw['shortened'];
      }
    }
  }

  Map<String, dynamic> payload() => {
    'shortened': shortened,
    'lessons': lessons
        .map(
          (l) => {
            for (final key in [
              'slot',
              'subject',
              'teacher',
              'room',
              'subgroup_id',
              'week',
            ])
              if (l.containsKey(key)) key: l[key],
          },
        )
        .toList(),
  };
  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await s.api.request(
        '/groups/${s.group}/${widget.weekday == null ? 'days/${widget.day['date']}' : 'templates/${widget.weekday}'}',
        method: 'PUT',
        body: payload(),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Расписание сохранено')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> repeat() async {
    final start = await showDatePicker(
      context: context,
      initialDate: date.add(const Duration(days: 7)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (start == null || !mounted) return;
    final controller = TextEditingController(text: '4');
    final weeks = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Повторить на недели'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Количество недель (1–104)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text);
              if (n != null && n >= 1 && n <= 104) Navigator.pop(c, n);
            },
            child: const Text('Далее'),
          ),
        ],
      ),
    );
    if (weeks == null || !mounted) return;
    if (!await confirm(
      context,
      'Сохранить и повторить на $weeks недель с ${iso(start)}? Расписание на этих датах будет заменено.',
    )) {
      return;
    }
    setState(() => busy = true);
    try {
      final path =
          '/groups/${s.group}/${widget.weekday == null ? 'days/${widget.day['date']}' : 'templates/${widget.weekday}'}';
      await s.api.request(path, method: 'PUT', body: payload());
      await s.api.request(
        '$path/repeat',
        method: 'POST',
        body: {'start': iso(start), 'weeks': weeks},
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> copy() async {
    final source = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (source == null) return;
    try {
      final row = await s.api.request('/groups/${s.group}/days/${iso(source)}');
      if (mounted) {
        setState(() {
          lessons = List<Map<String, dynamic>>.from(
            (row['lessons'] as List).map((l) => Map<String, dynamic>.from(l)),
          );
          shortened = row['shortened'];
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> lesson([int? index]) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => LessonEditor(
          lesson: index == null ? null : lessons[index],
          subgroups: subgroups,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        if (index == null) {
          lessons.add(result);
        } else {
          lessons[index] = result;
        }
        lessons.sort((a, b) => (a['slot'] as int).compareTo(b['slot']));
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.weekday == null
            ? 'Расписание · ${iso(date)}'
            : 'Недельный шаблон',
      ),
    ),
    body: SafeArea(
      child: FutureBuilder<void>(
        future: loading,
        builder: (c, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${snapshot.error}'),
                  TextButton(
                    onPressed: () => setState(() => loading = load()),
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Сокращённый день'),
                value: shortened,
                onChanged: (v) => setState(() => shortened = v),
              ),
              for (int i = 0; i < lessons.length; i++)
                Card(
                  child: ListTile(
                    title: Text(
                      '${lessons[i]['slot']}. ${lessons[i]['subject']}',
                    ),
                    subtitle: Text(
                      '${lessons[i]['week'] == 'both'
                          ? 'Обе недели'
                          : lessons[i]['week'] == 'upper'
                          ? 'Верхняя'
                          : 'Нижняя'} · ${lessons[i]['room'] ?? ''}',
                    ),
                    onTap: () => lesson(i),
                    trailing: IconButton(
                      tooltip: 'Удалить пару',
                      onPressed: () => setState(() => lessons.removeAt(i)),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              if (date.weekday != 7 || widget.weekday != null)
                OutlinedButton.icon(
                  onPressed: busy ? null : () => lesson(),
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить пару'),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: busy ? null : copy,
                    child: const Text('Скопировать день'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (await confirm(context, 'Отменить все пары?')) {
                              setState(() => lessons.clear());
                            }
                          },
                    child: const Text('Очистить день'),
                  ),
                  TextButton(
                    onPressed: busy ? null : repeat,
                    child: const Text('Повторить на недели'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Предпросмотр',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final l in lessons)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${l['slot']}. ${timeFor(l['slot'], shortened)} · ${l['subject']}\n${l['teacher'] ?? ''} · ${l['room'] ?? ''}${l['subgroup_id'] == null ? '' : ' · ${subgroups.where((g) => g['id'] == l['subgroup_id']).map((g) => g['name']).join()}'}',
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy ? null : save,
                child: Text(busy ? 'Сохранение…' : 'Сохранить'),
              ),
            ],
          );
        },
      ),
    ),
  );
}

String timeFor(int slot, bool short) {
  final start =
      510 + (slot - 1) * (short ? 70 : 110) + (!short && slot >= 3 ? 35 : 0);
  final end = start + (short ? 60 : 100);
  String f(int t) =>
      '${(t ~/ 60).toString().padLeft(2, '0')}:${(t % 60).toString().padLeft(2, '0')}';
  return '${f(start)}–${f(end)}';
}

class LessonEditor extends StatefulWidget {
  final Map<String, dynamic>? lesson;
  final List<dynamic> subgroups;
  const LessonEditor({super.key, this.lesson, required this.subgroups});
  @override
  State<LessonEditor> createState() => _LessonEditorState();
}

class _LessonEditorState extends State<LessonEditor> {
  final form = GlobalKey<FormState>();
  late TextEditingController slot, subject, teacher, room;
  late String week;
  int? subgroup;
  @override
  void initState() {
    super.initState();
    final l = widget.lesson ?? {};
    slot = TextEditingController(text: '${l['slot'] ?? 1}');
    subject = TextEditingController(text: l['subject'] ?? '');
    teacher = TextEditingController(text: l['teacher'] ?? '');
    room = TextEditingController(text: l['room'] ?? '');
    week = l['week'] ?? 'both';
    subgroup = l['subgroup_id'];
  }

  @override
  void dispose() {
    for (final c in [slot, subject, teacher, room]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Учебная пара')),
    body: SafeArea(
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: slot,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Номер пары'),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                return n == null || n < 1 || n > 100
                    ? 'Введите номер от 1 до 100'
                    : null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: subject,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Предмет'),
              validator: requiredText,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: teacher,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Преподаватель'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: room,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Аудитория'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: week,
              decoration: const InputDecoration(labelText: 'Неделя'),
              items: const [
                DropdownMenuItem(value: 'both', child: Text('Обе недели')),
                DropdownMenuItem(value: 'upper', child: Text('Верхняя')),
                DropdownMenuItem(value: 'lower', child: Text('Нижняя')),
              ],
              onChanged: (v) => week = v!,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: subgroup ?? 0,
              decoration: const InputDecoration(labelText: 'Подгруппа'),
              items: [
                const DropdownMenuItem(value: 0, child: Text('Вся группа')),
                for (final g in widget.subgroups)
                  DropdownMenuItem(
                    value: g['id'] as int,
                    child: Text(g['name']),
                  ),
              ],
              onChanged: (v) => subgroup = v == 0 ? null : v,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(context, {
                    'slot': int.parse(slot.text),
                    'subject': subject.text.trim(),
                    'teacher': teacher.text.trim(),
                    'room': room.text.trim(),
                    'week': week,
                    'subgroup_id': subgroup,
                  });
                }
              },
              child: const Text('Готово'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> editSubgroups(BuildContext context, AppState s) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SubgroupsEditor(state: s)));

class SubgroupsEditor extends StatefulWidget {
  final AppState state;
  const SubgroupsEditor({super.key, required this.state});
  @override
  State<SubgroupsEditor> createState() => _SubgroupsEditorState();
}

class _SubgroupsEditorState extends State<SubgroupsEditor> {
  late Future<dynamic> data;
  AppState get s => widget.state;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    data = s.api.request('/groups/${s.group}/subgroups');
  }

  Future<void> edit([Map<String, dynamic>? g]) async {
    final controller = TextEditingController(text: g?['name'] ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Подгруппа'),
        content: TextField(
          controller: controller,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(c, controller.text.trim());
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (name == null) return;
    try {
      await s.api.request(
        '/groups/${s.group}/subgroups${g == null ? '' : '/${g['id']}'}',
        method: g == null ? 'POST' : 'PUT',
        body: {'name': name},
      );
      if (mounted) setState(load);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Подгруппы')),
    floatingActionButton: FloatingActionButton(
      onPressed: edit,
      child: const Icon(Icons.add),
    ),
    body: FutureBuilder<dynamic>(
      future: data,
      builder: (c, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(load),
              child: Text('${snapshot.error} · Повторить'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data as List;
        return ListView(
          children: [
            for (final g in rows)
              ListTile(
                title: Text(g['name']),
                onTap: () => edit(g),
                trailing: IconButton(
                  tooltip: 'Удалить',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (!await confirm(context, 'Удалить подгруппу?')) return;
                    try {
                      await s.api.request(
                        '/groups/${s.group}/subgroups/${g['id']}',
                        method: 'DELETE',
                      );
                      if (mounted) setState(load);
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                ),
              ),
          ],
        );
      },
    ),
  );
}
