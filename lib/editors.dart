import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'pages.dart';
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
  Widget build(BuildContext context) => EditorScaffold(
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

class ScheduleEditor extends StatefulWidget {
  final AppState state;
  final Map<String, dynamic> day;
  const ScheduleEditor({super.key, required this.state, required this.day});
  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  late bool shortened;
  late List<Map<String, dynamic>> lessons;
  final List<dynamic> subgroups = const [
    {'id': 1, 'name': 'Пг 1'},
    {'id': 2, 'name': 'Пг 2'},
  ];
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
    {
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
        '/groups/${s.group}/days/${widget.day['date']}',
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
      final path = '/groups/${s.group}/days/${widget.day['date']}';
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
          initialSlot:
              (lessons
                          .map((l) => l['slot'] as int)
                          .fold<int>(0, (a, b) => a > b ? a : b) +
                      1)
                  .clamp(1, 100),
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
  Widget build(BuildContext context) => EditorScaffold(
    appBar: AppBar(title: Text('Расписание · ${iso(date)}')),
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
                    subtitle: Text('${lessons[i]['room'] ?? ''}'),
                    onTap: () => lesson(i),
                    trailing: IconButton(
                      tooltip: 'Удалить пару',
                      onPressed: () => setState(() => lessons.removeAt(i)),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              if (date.weekday != 7)
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
  final int initialSlot;
  const LessonEditor({super.key, this.lesson, this.initialSlot = 1});
  @override
  State<LessonEditor> createState() => _LessonEditorState();
}

class _LessonEditorState extends State<LessonEditor> {
  final form = GlobalKey<FormState>();
  late TextEditingController subject, teacher, room;
  late int slot;
  int? subgroup;
  @override
  void initState() {
    super.initState();
    final l = widget.lesson ?? {};
    slot = l['slot'] ?? widget.initialSlot;
    subject = TextEditingController(text: l['subject'] ?? '');
    teacher = TextEditingController(text: l['teacher'] ?? '');
    room = TextEditingController(text: l['room'] ?? '');
    subgroup = l['subgroup_id'];
  }

  @override
  void dispose() {
    for (final c in [subject, teacher, room]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EditorScaffold(
    appBar: AppBar(title: const Text('Учебная пара')),
    body: SafeArea(
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Номер пары', style: TextStyle(fontSize: 17)),
                ),
                IconButton.filledTonal(
                  tooltip: 'Уменьшить номер пары',
                  onPressed: slot <= 1 ? null : () => setState(() => slot--),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
                SizedBox(
                  width: 52,
                  child: Center(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        '$slot',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Увеличить номер пары',
                  onPressed: slot >= 100 ? null : () => setState(() => slot++),
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                ),
              ],
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
            DropdownButtonFormField<int>(
              initialValue: subgroup ?? 0,
              decoration: const InputDecoration(labelText: 'Подгруппа'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Вся группа')),
                DropdownMenuItem(value: 1, child: Text('Пг 1')),
                DropdownMenuItem(value: 2, child: Text('Пг 2')),
              ],
              onChanged: (v) => subgroup = v == 0 ? null : v,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(context, {
                    'slot': slot,
                    'subject': subject.text.trim(),
                    'teacher': teacher.text.trim(),
                    'room': room.text.trim(),
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
