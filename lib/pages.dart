import 'package:flutter/material.dart';

import 'api.dart';
import 'design.dart';

class AppPage extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? action;
  const AppPage({
    super.key,
    required this.title,
    required this.body,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 20, 20),
                child: Row(
                  children: [
                    if (Navigator.of(context).canPop()) ...[
                      IconButton(
                        tooltip: 'Назад',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(title, style: display(32, FontWeight.w800)),
                    ),
                    ?action,
                  ],
                ),
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    ),
  );
}

class FormPanel extends StatelessWidget {
  final Widget child;
  const FormPanel({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Material(
    color: cardColor(context),
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: child,
    ),
  );
}

class GroupRequestScreen extends StatefulWidget {
  final AppState state;
  const GroupRequestScreen({super.key, required this.state});
  @override
  State<GroupRequestScreen> createState() => _GroupRequestState();
}

class _GroupRequestState extends State<GroupRequestScreen> {
  final form = GlobalKey<FormState>();
  final number = TextEditingController(), contacts = TextEditingController();
  bool busy = false, sent = false;
  String? error;
  @override
  void dispose() {
    number.dispose();
    contacts.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.state.api.request(
        '/group-requests',
        method: 'POST',
        body: {
          'group_number': number.text.trim(),
          'contacts': contacts.text.trim(),
        },
      );
      if (mounted) setState(() => sent = true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Добавить группу',
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        if (sent) ...[
          const SizedBox(height: 24),
          Icon(
            Icons.check_circle_outline_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 48,
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Заявка отправлена',
              style: display(22, FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Свяжемся с вами по указанным контактам.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: hintGrey),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Готово'),
          ),
        ] else
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FormPanel(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: number,
                        autofocus: true,
                        maxLength: 50,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Номер группы',
                          counterText: '',
                        ),
                        validator: (v) {
                          final text = v?.trim() ?? '';
                          if (text.isEmpty) return 'Укажите номер группы';
                          if (!RegExp(
                            r'^[0-9A-Za-zА-Яа-я][0-9A-Za-zА-Яа-я -]*$',
                          ).hasMatch(text)) {
                            return 'Проверьте номер группы';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: contacts,
                        minLines: 2,
                        maxLines: 5,
                        maxLength: 1000,
                        decoration: const InputDecoration(
                          labelText: 'Контакты',
                          hintText: 'Telegram, email или телефон',
                          counterText: '',
                        ),
                        validator: (v) => (v?.trim().length ?? 0) < 5
                            ? 'Укажите, как с вами связаться'
                            : null,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Сюда отправим пароль для редактирования.',
                  style: TextStyle(fontSize: 13, color: hintGrey),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: Text(busy ? 'Отправка…' : 'Отправить заявку'),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class EditorScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  const EditorScaffold({super.key, this.appBar, required this.body});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appBar == null
        ? null
        : PreferredSize(
            preferredSize: appBar!.preferredSize,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: appBar,
              ),
            ),
          ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: body,
      ),
    ),
  );
}
