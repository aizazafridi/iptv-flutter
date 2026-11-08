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
  bool busy = false, showPassword = false, showCurrent = false;
  String? error;
  @override
  void dispose() {
    password.dispose();
    current.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
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

  InputDecoration pinDecoration(
    String label, {
    required bool visible,
    required VoidCallback toggle,
  }) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 13),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    suffixIcon: IconButton(
      tooltip: visible ? 'Hide PIN' : 'Show PIN',
      onPressed: busy ? null : toggle,
      icon: Icon(
        visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        size: 18,
      ),
    ),
  );

  static const pinStyle = TextStyle(
    fontSize: 18,
    letterSpacing: 3,
    height: 1.2,
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    constraints: const BoxConstraints(maxWidth: 340),
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
    titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
    contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
    actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    title: Text(
      widget.setting ? 'Parental PIN' : 'Enter parental PIN',
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
    ),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.setting &&
                widget.locks.hasPassword &&
                widget.verifiedCurrent == null) ...[
              TextField(
                key: const ValueKey('current-parental-pin'),
                controller: current,
                obscureText: !showCurrent,
                enabled: !busy,
                style: pinStyle,
                textAlign: TextAlign.center,
                maxLines: 1,
                keyboardType: widget.locks.needsPinUpgrade
                    ? TextInputType.text
                    : TextInputType.number,
                enableSuggestions: false,
                autocorrect: false,
                inputFormatters: widget.locks.needsPinUpgrade
                    ? null
                    : [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                decoration: pinDecoration(
                  'Current PIN',
                  visible: showCurrent,
                  toggle: () => setState(() => showCurrent = !showCurrent),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              key: const ValueKey('parental-pin'),
              controller: password,
              obscureText: !showPassword,
              autofocus: true,
              enabled: !busy,
              style: pinStyle,
              textAlign: TextAlign.center,
              maxLines: 1,
              keyboardType: widget.setting || !widget.locks.needsPinUpgrade
                  ? TextInputType.number
                  : TextInputType.text,
              enableSuggestions: false,
              autocorrect: false,
              inputFormatters: widget.setting || !widget.locks.needsPinUpgrade
                  ? [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ]
                  : null,
              decoration: pinDecoration(
                widget.setting ? 'New PIN (6 digits)' : 'Parental PIN',
                visible: showPassword,
                toggle: () => setState(() => showPassword = !showPassword),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => submit(),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        style: TextButton.styleFrom(
          minimumSize: const Size(70, 40),
          textStyle: const TextStyle(fontSize: 14),
        ),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy ? null : submit,
        style: FilledButton.styleFrom(
          minimumSize: const Size(80, 40),
          textStyle: const TextStyle(fontSize: 14),
        ),
        child: Text(widget.setting ? 'Save' : 'Unlock'),
      ),
    ],
  );
}
