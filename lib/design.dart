import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';

const accentBlue = Color(0xff007aff);
const hintGrey = Color(0xff8e8e93);
Color cardColor(BuildContext context) => Theme.of(context).colorScheme.surface;
TextStyle display(double size, FontWeight weight, {Color? color}) => TextStyle(
  fontFamily: 'SF Display',
  fontSize: size,
  fontWeight: weight,
  letterSpacing: -.3,
  color: color,
);
String capital(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
ThemeData originalTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final bg = Color(dark ? 0xff1c1c1e : 0xfff2f2f7);
  final card = Color(dark ? 0xff2c2c2e : 0xffffffff);
  final text = Color(dark ? 0xfff5f5f7 : 0xff000000);
  final blue = Color(dark ? 0xff0a84ff : 0xff007aff);
  final scheme = ColorScheme.fromSeed(seedColor: blue, brightness: brightness)
      .copyWith(
        primary: blue,
        onPrimary: Colors.white,
        secondary: blue,
        surface: card,
        onSurface: text,
        error: const Color(0xffff3b30),
        surfaceTint: Colors.transparent,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'SF Text',
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    dividerColor: hintGrey.withValues(alpha: .18),
    textTheme: TextTheme(
      bodyLarge: TextStyle(fontSize: 17, color: text, height: 1.3),
      bodyMedium: TextStyle(fontSize: 15, color: text),
      bodySmall: const TextStyle(fontSize: 13, color: hintGrey),
      titleMedium: TextStyle(fontSize: 17, color: text),
      titleLarge: display(22, FontWeight.w600, color: text),
      headlineSmall: display(28, FontWeight.w700, color: text),
      headlineMedium: display(34, FontWeight.w800, color: text),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: text,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: display(24, FontWeight.w700, color: text),
    ),
    cardTheme: CardThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      border: UnderlineInputBorder(
        borderSide: BorderSide(color: hintGrey.withValues(alpha: .25)),
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: hintGrey.withValues(alpha: .25)),
      ),
      labelStyle: const TextStyle(color: hintGrey, fontSize: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: const TextStyle(
          fontFamily: 'SF Text',
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(
          fontFamily: 'SF Text',
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    iconTheme: IconThemeData(color: blue, size: 24),
  );
}

class SegmentControl<T> extends StatelessWidget {
  final T value;
  final Map<T, String> labels;
  final ValueChanged<T> onChanged;
  final bool small;
  const SegmentControl({
    super.key,
    required this.value,
    required this.labels,
    required this.onChanged,
    this.small = false,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: const Color(0xff767680).withValues(alpha: .14),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        for (final entry in labels.entries)
          Expanded(
            child: Semantics(
              selected: entry.key == value,
              button: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onChanged(entry.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    constraints: BoxConstraints(minHeight: small ? 34 : 38),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: entry.key == value
                          ? cardColor(context)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: entry.key == value
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .14),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      entry.value,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: small ? 13 : 14,
                        fontWeight: entry.key == value
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class OriginalTabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const OriginalTabBar({
    super.key,
    required this.index,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    const labels = ['Задания', 'Расписание', 'Календарь'];
    const icons = [
      Icons.check_circle_outline_rounded,
      Icons.schedule_rounded,
      Icons.calendar_today_outlined,
    ];
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: cardColor(context).withValues(alpha: .86),
            border: Border(
              top: BorderSide(
                color: hintGrey.withValues(alpha: .18),
                width: .5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Row(
                    children: [
                      for (int n = 0; n < 3; n++)
                        Expanded(
                          child: Semantics(
                            selected: index == n,
                            button: true,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onChanged(n),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      icons[n],
                                      size: 26,
                                      color: index == n
                                          ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                          : hintGrey,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      labels[n],
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: index == n
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: index == n
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                            : hintGrey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TodayHero extends StatelessWidget {
  final Map<String, dynamic> day;
  final String group;
  final List<dynamic> active;
  const TodayHero({
    super.key,
    required this.day,
    required this.group,
    required this.active,
  });
  @override
  Widget build(BuildContext context) {
    final now = moscowNow();
    final today = DateTime(now.year, now.month, now.day);
    final hot = active
        .where(
          (h) => DateTime.parse(h['due_date']).difference(today).inDays <= 2,
        )
        .length;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff007aff), Color(0xff476bff)],
        ),
        boxShadow: [
          BoxShadow(
            color: accentBlue.withValues(alpha: .28),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -6,
            bottom: -26,
            child: Text(
              group,
              style: display(
                112,
                FontWeight.w200,
                color: Colors.white.withValues(alpha: .16),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: DefaultTextStyle(
              style: const TextStyle(
                fontFamily: 'SF Text',
                color: Colors.white,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '${now.day}',
                        style: display(
                          78,
                          FontWeight.w100,
                          color: Colors.white,
                        ).copyWith(height: .9, letterSpacing: -3),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              capital(DateFormat('EEEE', 'ru').format(now)),
                              style: display(
                                22,
                                FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${DateFormat('MMMM', 'ru').format(now)} · ${day['week'] == 'upper' ? 'верхняя' : 'нижняя'} неделя',
                              style: const TextStyle(
                                fontFamily: 'SF Display',
                                fontSize: 16,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (hot > 0) _chip('$hot горит', true),
                      _chip(
                        '${active.length} ${active.length == 1 ? 'актуальное' : 'актуальных'}',
                        false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    currentStatus(day, now),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, bool hot) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      color: hot ? const Color(0xffff3b30) : Colors.white.withValues(alpha: .2),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),
  );
}

class HomeworkRow extends StatelessWidget {
  final Map<String, dynamic> homework;
  final bool archive, showSubject;
  final VoidCallback? onEdit;
  final bool first, last;
  const HomeworkRow({
    super.key,
    required this.homework,
    this.archive = false,
    this.showSubject = true,
    this.onEdit,
    this.first = true,
    this.last = true,
  });
  @override
  Widget build(BuildContext context) {
    final now = moscowNow();
    final d = DateTime.parse(homework['due_date']);
    final left = d.difference(DateTime(now.year, now.month, now.day)).inDays;
    final urgent = !archive && left <= 2;
    final accent = Theme.of(context).colorScheme.primary;
    final red = Theme.of(context).colorScheme.error;
    final when = archive
        ? 'срок был ${DateFormat('d MMMM', 'ru').format(d)}'
        : left == 0
        ? 'сегодня'
        : left == 1
        ? 'завтра'
        : 'до ${DateFormat('d MMMM', 'ru').format(d)} · через $left дн.';
    return Container(
      decoration: BoxDecoration(
        color: cardColor(context),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(first ? 16 : 0),
          bottom: Radius.circular(last ? 16 : 0),
        ),
      ),
      child: Column(
        children: [
          if (!first)
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Divider(
                height: .5,
                thickness: .5,
                color: hintGrey.withValues(alpha: .18),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 27,
                  height: 27,
                  margin: const EdgeInsets.only(top: 1),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: urgent ? red : null,
                    border: urgent
                        ? null
                        : Border.all(
                            color: archive ? hintGrey : accent,
                            width: 2,
                          ),
                    boxShadow: urgent
                        ? [
                            BoxShadow(
                              color: red.withValues(alpha: .4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: urgent
                      ? const Text(
                          '!',
                          style: TextStyle(
                            fontFamily: 'SF Display',
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showSubject)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            (homework['subject'] as String).toUpperCase(),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: .2,
                              color: archive ? hintGrey : accent,
                            ),
                          ),
                        ),
                      Text(
                        homework['text'],
                        style: TextStyle(
                          fontSize: 17,
                          height: 1.3,
                          fontWeight: archive
                              ? FontWeight.w300
                              : FontWeight.w400,
                          color: archive ? hintGrey : null,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        when,
                        style: TextStyle(
                          fontSize: 14,
                          color: urgent ? red : hintGrey,
                          fontWeight: urgent
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    tooltip: 'Изменить ДЗ',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
