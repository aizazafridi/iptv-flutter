import 'package:flutter/material.dart';
import 'subtitle_settings_panel.dart';
import '../application/appearance.dart';
import '../application/session.dart';
import '../domain/models.dart';
import '../application/watch_history.dart';
import '../application/category_locks.dart';
import 'lock_password_dialog.dart';
import 'profile_avatar.dart';

class SettingsScreen extends StatefulWidget {
  final Session session;
  final AppAppearance appearance;
  final Future<void> Function() switchUser;
  final Future<void> Function()? addAccount;
  final Future<void> Function()? editAccount;
  const SettingsScreen({
    super.key,
    required this.session,
    required this.appearance,
    required this.switchUser,
    this.addAccount,
    this.editAccount,
  });
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool busy = false;
  bool clearingHistory = false;
  Future<void> clearHistory() async {
    final provider = widget.session.provider;
    if (provider == null) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Which watch history?'),
        children: [
          for (final entry in {
            'all': 'All watch history',
            'movies': 'Movies only',
            'series': 'Series only',
          }.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry.key),
              child: Text(entry.value),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    setState(() => clearingHistory = true);
    try {
      await WatchHistory.forProvider(
        provider,
      ).clear(type: choice == 'all' ? null : ContentType.values.byName(choice));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Watch history cleared for this account.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not clear watch history. Please retry.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => clearingHistory = false);
    }
  }

  Future<void> removeAccount(AccountProfile profile) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${profile.name}?'),
        content: const Text('Remove this saved account from this device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!mounted || remove != true) return;
    setState(() => busy = true);
    try {
      await widget.session.removeProfile(profile);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget accountManagement() => ExpansionTile(
    leading: const Icon(Icons.manage_accounts_outlined),
    title: const Text('Saved accounts'),
    children: [
      for (final profile in widget.session.profiles)
        ListTile(
          leading: ProfileAvatar(profile.avatar, size: 40),
          title: Text(profile.name),
          subtitle: widget.session.activeProfile?.id == profile.id
              ? const Text('Current account')
              : null,
          trailing: IconButton(
            tooltip: 'Remove ${profile.name}',
            icon: const Icon(Icons.person_remove_outlined),
            onPressed: busy || widget.session.loading
                ? null
                : () => removeAccount(profile),
          ),
        ),
      if (widget.session.profiles.isEmpty)
        const ListTile(title: Text('No saved accounts')),
    ],
  );

  Widget addAccountTile() => ListTile(
    leading: const Icon(Icons.person_add_alt_1),
    title: const Text('Add account'),
    subtitle: Text(
      widget.session.profiles.length >= 5
          ? 'Five accounts saved. Remove an account before adding another.'
          : '${widget.session.profiles.length} of 5 accounts saved',
    ),
    onTap: widget.session.profiles.length >= 5 || widget.session.loading
        ? null
        : widget.addAccount,
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.session, widget.appearance]),
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: widget.session.activeProfile == null
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: [
                addAccountTile(),
                const Text('Choose an account to change its settings.'),
                accountManagement(),
                if (widget.session.error != null) Text(widget.session.error!),
              ],
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: const Text('Edit current account'),
                      subtitle: Text(widget.session.activeProfile!.name),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: widget.session.loading || busy
                          ? null
                          : widget.editAccount,
                    ),
                    addAccountTile(),
                    ListTile(
                      leading: const Icon(Icons.switch_account_outlined),
                      title: const Text('Switch account'),
                      subtitle: Text(
                        widget.session.account == null
                            ? 'Enter a different IPTV account'
                            : 'Signed in as ${widget.session.account!.username}',
                      ),
                      trailing: busy
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: busy || widget.session.loading
                          ? null
                          : () async {
                              setState(() => busy = true);
                              await widget.switchUser();
                              if (!context.mounted) return;
                              if (widget.session.account == null) {
                                Navigator.of(context).pop();
                              } else {
                                setState(() => busy = false);
                              }
                            },
                    ),
                    ListTile(
                      leading: const Icon(Icons.history),
                      title: const Text('Clear watch history'),
                      subtitle: const Text(
                        'Choose Movies, Series, or all history. Resume positions and recordings are kept.',
                      ),
                      onTap: clearingHistory || widget.session.provider == null
                          ? null
                          : clearHistory,
                      trailing: clearingHistory
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    ),
                    if (widget.session.error != null)
                      Text(widget.session.error!),
                    const Divider(height: 40),
                    Text(
                      'App background color',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose a color. Your preference is saved for next time.',
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final entry in AppAppearance.backgrounds.entries)
                          ChoiceChip(
                            avatar: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: entry.value,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.grey),
                              ),
                            ),
                            label: Text(entry.key),
                            selected: widget.appearance.selected == entry.key,
                            onSelected: (_) =>
                                widget.appearance.choose(entry.key),
                          ),
                      ],
                    ),
                    const Divider(height: 40),
                    Text(
                      'Browsing layout',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enable cards to browse horizontal rows for each category.',
                    ),
                    for (final type in ContentType.values)
                      SwitchListTile(
                        title: Text('${type.label} cards'),
                        subtitle: const Text('Horizontal category rows'),
                        value: widget.appearance.usesCards(type),
                        onChanged: (enabled) =>
                            widget.appearance.setCards(type, enabled),
                      ),
                    const Divider(height: 40),
                    SubtitleSettingsPanel(
                      scope: widget.session.activeProfile?.id,
                    ),
                    const Divider(height: 24),
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('Category lock password'),
                      subtitle: const Text(
                        'Set or change the password for this account',
                      ),
                      onTap: widget.session.provider == null
                          ? null
                          : () async {
                              final locks = CategoryLocks.forProvider(
                                widget.session.provider!,
                              );
                              await locks.load();
                              if (!context.mounted) return;
                              await showDialog<void>(
                                context: context,
                                builder: (_) => LockPasswordDialog(
                                  locks: locks,
                                  setting: true,
                                ),
                              );
                            },
                    ),
                    const Divider(height: 24),
                    accountManagement(),
                    if (widget.appearance.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(widget.appearance.error!),
                      ),
                  ],
                ),
              ),
            ),
    ),
  );
}
