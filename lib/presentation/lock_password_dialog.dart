import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/category_locks.dart';
import '../domain/models.dart';

class LockPasswordDialog extends StatefulWidget {
  final CategoryLocks locks;
  final bool setting;
  final String? verifiedCurrent;
  const LockPasswordDialog({
    super.key,
    required this.locks,
    this.setting = false,
    this.verifiedCurrent,
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
        await widget.locks.setPassword(
          password.text,
          current: widget.verifiedCurrent ?? current.text,
        );
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
    title: Text(widget.setting ? 'Parental PIN' : 'Enter parental PIN'),
    content: SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.setting &&
              widget.locks.hasPassword &&
              widget.verifiedCurrent == null)
            TextField(
              controller: current,
              obscureText: true,
              keyboardType: widget.locks.needsPinUpgrade
                  ? TextInputType.text
                  : TextInputType.number,
              inputFormatters: widget.locks.needsPinUpgrade
                  ? null
                  : [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
              decoration: const InputDecoration(labelText: 'Current PIN'),
            ),
          TextField(
            controller: password,
            obscureText: true,
            autofocus: true,
            enabled: !busy,
            keyboardType: widget.setting || !widget.locks.needsPinUpgrade
                ? TextInputType.number
                : TextInputType.text,
            inputFormatters: widget.setting || !widget.locks.needsPinUpgrade
                ? [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ]
                : null,
            decoration: InputDecoration(
              labelText: widget.setting ? 'New PIN (6 digits)' : 'Parental PIN',
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
