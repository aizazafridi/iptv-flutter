import 'package:flutter/material.dart';
import '../application/category_locks.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'lock_password_dialog.dart';

Future<bool> requestTitleAccess(
  BuildContext context,
  IptvProvider provider,
  ContentItem item,
) async {
  final locks = CategoryLocks.forProvider(provider);
  await locks.load();
  if (!context.mounted) return false;
  if (!locks.titleLocked(item)) return true;
  final pin = await showDialog<String>(
    context: context,
    builder: (_) => LockPasswordDialog(locks: locks),
  );
  return context.mounted && pin != null && locks.unlockTitle(item, pin);
}
