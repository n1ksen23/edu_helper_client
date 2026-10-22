import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'design.dart';
import 'pages.dart';

class AdminScreen extends StatefulWidget {
  final AppState state;
  const AdminScreen({super.key, required this.state});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<Map<String, dynamic>> requests = [], groups = [];
  String status = 'pending';
  int? cursor;
  bool loading = true, busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool more = false}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final page = await widget.state.api.request(
        '/admin/group-requests?status=$status${more && cursor != null ? '&before=$cursor' : ''}',
      );
      final allGroups = await widget.state.api.request('/admin/groups');
      if (!mounted) return;
      setState(() {
        final items = List<Map<String, dynamic>>.from(page['items']);
        requests = more ? [...requests, ...items] : items;
        cursor = page['next_cursor'];
        groups = List<Map<String, dynamic>>.from(allGroups);
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit({
    Map<String, dynamic>? group,
    Map<String, dynamic>? request,
  }) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AdminGroupEditor(
          state: widget.state,
          group: group,
          request: request,
        ),
      ),
    );
    if (saved == true && mounted) {
      widget.state.changed();
      await load();
    }
  }

  Future<void> changeStatus(Map<String, dynamic> request, String value) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.state.api.request(
        '/admin/group-requests/${request['id']}',
        method: 'PATCH',
        body: {'status': value},
      );
      if (mounted) await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: AppPage(
      title: 'Администрирование',
      body: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Заявки'),
              Tab(text: 'Группы'),
            ],
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(error!),
                  TextButton(
                    onPressed: loading ? null : () => load(),
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              children: [
                RefreshIndicator(
                  onRefresh: () => load(),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: status,
                        decoration: const InputDecoration(labelText: 'Заявки'),
                        items: const [
                          DropdownMenuItem(
                            value: 'pending',
                            child: Text('Новые'),
                          ),
                          DropdownMenuItem(
                            value: 'approved',
                            child: Text('Принятые'),
                          ),
                          DropdownMenuItem(
                            value: 'rejected',
                            child: Text('Отклонённые'),
                          ),
                        ],
                        onChanged: loading || busy
                            ? null
                            : (v) {
                                status = v!;
                                load();
                              },
                      ),
                      const SizedBox(height: 16),
                      if (!loading && error == null && requests.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('Заявок нет')),
                        ),
                      for (final r in requests) ...[
                        FormPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 8),
                              Text(
                                'Группа ${r['group_number']}',
                                style: display(21, FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              SelectableText(r['contacts']),
                              const SizedBox(height: 8),
                              Text(
                                DateFormat('d MMMM yyyy, HH:mm', 'ru').format(
                                  DateTime.parse(r['created_at'])
                                      .toUtc()
                                      .add(const Duration(hours: 3)),
                                ),
                                style: const TextStyle(
                                  color: hintGrey,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (r['status'] == 'pending') ...[
                                FilledButton(
                                  onPressed: busy || loading
                                      ? null
                                      : () => edit(request: r),
                                  child: const Text('Принять и создать группу'),
                                ),
                                TextButton(
                                  onPressed: busy || loading
                                      ? null
                                      : () => changeStatus(r, 'rejected'),
                                  child: const Text('Отклонить'),
                                ),
                              ] else
                                TextButton(
                                  onPressed: busy || loading
                                      ? null
                                      : () => changeStatus(r, 'pending'),
                                  child: const Text('Вернуть в новые'),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (cursor != null)
                        TextButton(
                          onPressed: loading ? null : () => load(more: true),
                          child: const Text('Загрузить ещё'),
                        ),
                    ],
                  ),
                ),
                RefreshIndicator(
                  onRefresh: () => load(),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      FilledButton.icon(
                        onPressed: () => edit(),
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text('Создать группу'),
                      ),
                      const SizedBox(height: 16),
                      for (final g in groups)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: FormPanel(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(g['name']),
                              subtitle: Text(
                                !g['active']
                                    ? 'Отключена'
                                    : g['published']
                                    ? 'Опубликована'
                                    : 'Скрыта',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => edit(group: g),
                            ),
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
  );
}

class AdminGroupEditor extends StatefulWidget {
  final AppState state;
  final Map<String, dynamic>? group, request;
  const AdminGroupEditor({
    super.key,
    required this.state,
    this.group,
    this.request,
  });
  @override
  State<AdminGroupEditor> createState() => _AdminGroupEditorState();
}

class _AdminGroupEditorState extends State<AdminGroupEditor> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(), password = TextEditingController();
  bool published = true, active = true, busy = false, visible = false;
  String? error;
  Map<String, dynamic>? saved;

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    name.text = g?['name'] ?? widget.request?['group_number'] ?? '';
    published = g?['published'] ?? true;
    active = g?['active'] ?? true;
  }

  @override
  void dispose() {
    name.dispose();
    password.dispose();
    super.dispose();
  }

  void generate() {
    const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    password.text = List.generate(
      20,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
    setState(() => visible = true);
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final g = widget.group, r = widget.request;
      final result = await widget.state.api.request(
        r != null
            ? '/admin/group-requests/${r['id']}/accept'
            : '/admin/groups${g == null ? '' : '/${g['id']}'}',
        method: g == null ? 'POST' : 'PUT',
        body: {
          'name': name.text.trim(),
          'password': password.text.isEmpty ? null : password.text,
          'published': published,
          'active': active,
          'timezone': g?['timezone'] ?? 'Europe/Moscow',
        },
      );
      if (!mounted) return;
      if (widget.state.group == result['id']) {
        await widget.state.selectGroup(result);
      }
      if (mounted) setState(() => saved = Map<String, dynamic>.from(result));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> revoke() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Завершить сеансы редакторов?'),
        content: const Text(
          'Для редактирования группы потребуется снова войти по паролю.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.state.api.request(
        '/admin/groups/${widget.group!['id']}/revoke',
        method: 'POST',
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Сеансы завершены')));
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> copyAccess() async {
    await Clipboard.setData(
      ClipboardData(text: 'Группа ${saved!['name']}\nПароль: ${password.text}'),
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Данные скопированы')));
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AppPage(
      title: saved != null
          ? 'Группа сохранена'
          : widget.group == null
          ? 'Новая группа'
          : 'Группа ${widget.group!['name']}',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          if (saved != null) ...[
            FormPanel(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Группа ${saved!['name']}',
                      style: display(22, FontWeight.w600),
                    ),
                    if (password.text.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('Пароль'),
                      SelectableText(
                        password.text,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ],
                    if (widget.request != null) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Контакты старосты',
                        style: TextStyle(color: hintGrey),
                      ),
                      SelectableText(widget.request!['contacts']),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (password.text.isNotEmpty)
              OutlinedButton.icon(
                onPressed: copyAccess,
                icon: const Icon(Icons.copy),
                label: const Text('Скопировать группу и пароль'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Готово'),
            ),
          ] else
            Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.request != null) ...[
                    FormPanel(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: SelectableText(widget.request!['contacts']),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FormPanel(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: name,
                          enabled: !busy,
                          maxLength: 100,
                          decoration: const InputDecoration(
                            labelText: 'Номер группы',
                            counterText: '',
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Укажите номер группы'
                              : null,
                        ),
                        TextFormField(
                          controller: password,
                          enabled: !busy,
                          obscureText: !visible,
                          autocorrect: false,
                          enableSuggestions: false,
                          maxLength: 200,
                          decoration: InputDecoration(
                            labelText: widget.group == null
                                ? 'Пароль'
                                : 'Новый пароль',
                            helperText: widget.group == null
                                ? null
                                : 'Оставьте пустым, чтобы сохранить пароль',
                            counterText: '',
                            suffixIcon: IconButton(
                              tooltip: visible
                                  ? 'Скрыть пароль'
                                  : 'Показать пароль',
                              onPressed: () =>
                                  setState(() => visible = !visible),
                              icon: Icon(
                                visible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                          validator: (v) =>
                              (v?.isEmpty ?? true) && widget.group != null
                              ? null
                              : (v?.length ?? 0) < 12
                              ? 'Минимум 12 символов'
                              : null,
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: busy ? null : generate,
                            child: const Text('Сгенерировать пароль'),
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Опубликована'),
                          value: published,
                          onChanged: busy
                              ? null
                              : (v) => setState(() => published = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Активна'),
                          value: active,
                          onChanged: busy
                              ? null
                              : (v) => setState(() => active = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: busy ? null : save,
                    child: Text(
                      busy
                          ? 'Сохранение…'
                          : widget.request != null
                          ? 'Создать группу и принять заявку'
                          : 'Сохранить',
                    ),
                  ),
                  if (widget.group != null)
                    TextButton(
                      onPressed: busy ? null : revoke,
                      child: const Text('Завершить сеансы редакторов'),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
