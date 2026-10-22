import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'pages.dart';

class RepeatScheduleScreen extends StatefulWidget {
  final AppState state;
  final DateTime source;
  final bool wholeWeek;
  final Map<String, dynamic>? dayPayload;
  const RepeatScheduleScreen({
    super.key,
    required this.state,
    required this.source,
    this.wholeWeek = false,
    this.dayPayload,
  });
  @override
  State<RepeatScheduleScreen> createState() => _RepeatScheduleState();
}

class _RepeatScheduleState extends State<RepeatScheduleScreen> {
  int interval = 2, count = 4;
  bool overwrite = false, busy = false;
  String? error;
  late DateTime start;
  Map<String, dynamic>? result;
  @override
  void initState() {
    super.initState();
    start = widget.source.add(const Duration(days: 14));
  }

  String date(DateTime d) => DateFormat('d MMM yyyy', 'ru').format(d);

  Future<void> submit() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final base = '/groups/${widget.state.group}';
      if (widget.dayPayload != null) {
        await widget.state.api.request(
          '$base/days/${iso(widget.source)}',
          method: 'PUT',
          body: widget.dayPayload,
        );
      }
      final data = await widget.state.api.request(
        '$base/${widget.wholeWeek ? 'weeks' : 'days'}/${iso(widget.source)}/repeat',
        method: 'POST',
        body: {
          'start': iso(start),
          'weeks': count,
          'interval_weeks': interval,
          'overwrite': overwrite,
        },
      );
      if (mounted) setState(() => result = Map<String, dynamic>.from(data));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AppPage(
      title: widget.wholeWeek ? 'Повторить неделю' : 'Повторить день',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          if (result != null) ...[
            FormPanel(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Дней скопировано: ${result!['count']}'),
                    if ((result!['skipped'] ?? 0) > 0)
                      Text('Заполненных дней пропущено: ${result!['skipped']}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Готово'),
            ),
          ] else ...[
            FormPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      widget.wholeWeek ? 'Исходная неделя' : 'Исходный день',
                    ),
                    subtitle: Text(
                      widget.wholeWeek
                          ? '${date(widget.source)} — ${date(widget.source.add(const Duration(days: 5)))}'
                          : date(widget.source),
                    ),
                  ),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: interval,
                    decoration: const InputDecoration(labelText: 'Повторять'),
                    items: const [
                      DropdownMenuItem(
                        value: 2,
                        child: Text('Через неделю · того же типа'),
                      ),
                      DropdownMenuItem(value: 1, child: Text('Каждую неделю')),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            interval = v!;
                            start = widget.source.add(
                              Duration(days: 7 * interval),
                            );
                          }),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Первый повтор'),
                    subtitle: Text(date(start)),
                    trailing: const Icon(Icons.calendar_month_outlined),
                    onTap: busy
                        ? null
                        : () async {
                            final selected = await showDatePicker(
                              context: context,
                              initialDate: start,
                              firstDate: widget.source.add(
                                Duration(days: 7 * interval),
                              ),
                              lastDate: DateTime(2100),
                              selectableDayPredicate: (d) =>
                                  d.difference(widget.source).inDays %
                                      (7 * interval) ==
                                  0,
                            );
                            if (selected != null && mounted) {
                              setState(() => start = selected);
                            }
                          },
                  ),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Количество повторов'),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Уменьшить повторы',
                            onPressed: busy || count <= 1
                                ? null
                                : () => setState(() => count--),
                            icon: const Icon(Icons.remove),
                          ),
                          Text('$count'),
                          IconButton(
                            tooltip: 'Увеличить повторы',
                            onPressed: busy || count >= 104
                                ? null
                                : () => setState(() => count++),
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Заменить заполненные дни'),
                    value: overwrite,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => overwrite = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Даты повторов',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < count; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  widget.wholeWeek
                      ? '${date(start.add(Duration(days: i * interval * 7)))} — ${date(start.add(Duration(days: i * interval * 7 + 5)))}'
                      : date(start.add(Duration(days: i * interval * 7))),
                ),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy ? null : submit,
              child: Text(
                busy
                    ? 'Копирование…'
                    : widget.dayPayload != null
                    ? 'Сохранить и повторить'
                    : 'Повторить неделю',
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
