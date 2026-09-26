import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

Future<String?> askName(
  BuildContext context, {
  required String title,
  String initial = '',
  String confirm = 'Create',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _NameDialog(title: title, initial: initial, confirm: confirm),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.confirm,
  });

  final String title;
  final String initial;
  final String confirm;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name = _controller.text.trim();
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: 'Name',
          hintStyle: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: colors.meta),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: colors.line),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: colors.accent),
          ),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (name.isNotEmpty) Navigator.of(context).pop(name);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: name.isEmpty
              ? null
              : () => Navigator.of(context).pop(name),
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
}) async {
  final colors = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colors.danger,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}
