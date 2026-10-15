import 'package:flutter/material.dart';
import '../application/category_locks.dart';
import '../domain/models.dart';

class LockPasswordDialog extends StatefulWidget {
  final CategoryLocks locks;
  final bool setting;
  const LockPasswordDialog({
    super.key,
    required this.locks,
    this.setting = false,
  });
  @override
  State<LockPasswordDialog> createState() => _LockPasswordDialogState();
}

class _LockPasswordDialogState extends State<LockPasswordDialog> {
  final password = TextEditingController(), current = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    password.dispose();
    current.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.setting) {
        await widget.locks.setPassword(password.text, current: current.text);
      } else if (!widget.locks.check(password.text)) {
        throw const ProviderException('Incorrect lock password.');
      }
      if (mounted) Navigator.pop(context, password.text);
    } catch (exception) {
      if (mounted) {
        setState(() {
          busy = false;
          error = exception is ProviderException
              ? exception.message
              : 'Could not save lock settings. Please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.setting ? 'Category lock password' : 'Unlock category'),
    content: SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.setting && widget.locks.hasPassword)
            TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
          TextField(
            controller: password,
            obscureText: true,
            autofocus: true,
            enabled: !busy,
            decoration: InputDecoration(
              labelText: widget.setting
                  ? 'New password (at least 4 characters)'
                  : 'Lock password',
            ),
            onSubmitted: (_) => submit(),
          ),
          if (error != null) Text(error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy ? null : submit,
        child: Text(widget.setting ? 'Save' : 'Unlock'),
      ),
    ],
  );
}
