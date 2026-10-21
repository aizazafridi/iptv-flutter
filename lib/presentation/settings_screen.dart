import '../data/video_recordings.dart';
import '../data/playback_preferences.dart';
import 'package:flutter/material.dart';
import '../application/appearance.dart';
import '../application/session.dart';
import '../domain/models.dart';
import '../application/watch_history.dart';
import '../application/category_locks.dart';
import 'lock_password_dialog.dart';
import 'category_lock_settings_screen.dart';
import 'title_lock_settings_screen.dart';
import 'smooth_page_route.dart';
import 'profile_avatar.dart';
import 'widgets.dart';

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
  String? selectedSection;
  Widget settingsCategory({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    if (selectedSection != null) {
      return selectedSection == title
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            )
          : const SizedBox.shrink();
    }
    return FocusCard(
      autofocus: title == 'Profile settings',
      padding: const EdgeInsets.all(12),
      onTap: () => enterSection(title),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    );
  }

  bool enteringParental = false;
  Future<void> enterSection(String title) async {
    if (title != 'Parental controls') {
      setState(() => selectedSection = title);
      return;
    }
    if (enteringParental) return;
    enteringParental = true;
    try {
      final provider = widget.session.provider;
      if (provider == null) return;
      final locks = CategoryLocks.forProvider(provider);
      await locks.load();
      if (!mounted) return;
      final pin = await showDialog<String>(
        context: context,
        builder: (_) =>
            LockPasswordDialog(locks: locks, setting: !locks.hasPassword),
      );
      if (!mounted || pin == null || !locks.check(pin)) return;
      if (locks.needsPinUpgrade) {
        final upgraded = await showDialog<String>(
          context: context,
          builder: (_) => LockPasswordDialog(
            locks: locks,
            setting: true,
            verifiedCurrent: pin,
          ),
        );
        if (!mounted || upgraded == null || locks.needsPinUpgrade) return;
      }
      setState(() => selectedSection = title);
    } finally {
      enteringParental = false;
    }
  }

  Widget settingsLayout({required List<Widget> children}) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 540 ? 2 : 1;
      final width = (constraints.maxWidth - 24 - 12 * (columns - 1)) / columns;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: selectedSection == null
            ? Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final child in children)
                    SizedBox(width: width, height: 88, child: child),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
      );
    },
  );

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
  Future<void> openParental(Widget screen) async {
    final provider = widget.session.provider;
    if (provider == null) return;
    final locks = CategoryLocks.forProvider(provider);
    await locks.load();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(SmoothPageRoute<void>(builder: (_) => screen));
  }

  Future<void> clearRecordings() async {
    final provider = widget.session.provider;
    if (provider == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all recordings?'),
        content: const Text(
          'Permanently delete video recordings for this profile? Other profiles are unaffected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await VideoRecordings.forScope(
        WatchHistory.forProvider(provider).scope,
      ).deleteAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recordings deleted for this profile.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not delete recordings. Stop recording and try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> changePin() async {
    final provider = widget.session.provider;
    if (provider == null) return;
    final locks = CategoryLocks.forProvider(provider);
    await locks.load();
    if (!mounted) return;
    await showDialog<String>(
      context: context,
      builder: (_) => LockPasswordDialog(locks: locks, setting: true),
    );
  }

  Future<void> playerDefaults() async {
    final provider = widget.session.provider;
    if (provider == null) return;
    final preferences = PlaybackPreferences(
      WatchHistory.forProvider(provider).scope,
    );
    final saved = await preferences.load();
    if (!mounted) return;
    var seek = [30, 60, 120, 180].contains(saved['seek'])
        ? saved['seek'] as int
        : 30;
    var rate = [0.5, 1, 2, 3, 5].contains(saved['rate'])
        ? (saved['rate'] as num).toDouble()
        : 1.0;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Playback defaults'),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: seek,
                  decoration: const InputDecoration(labelText: 'Seek interval'),
                  items: [30, 60, 120, 180]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value seconds'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) update(() => seek = value);
                  },
                ),
                DropdownButtonFormField<double>(
                  initialValue: rate,
                  decoration: const InputDecoration(
                    labelText: 'Playback speed',
                  ),
                  items: [0.5, 1.0, 2.0, 3.0, 5.0]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value == 1 ? 'Normal' : '${value}x'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) update(() => rate = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;
    try {
      await preferences.save({...saved, 'seek': seek, 'rate': rate});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save playback defaults.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.session, widget.appearance]),
    builder: (context, _) => Theme(
      data: Theme.of(context).copyWith(
        visualDensity: VisualDensity.compact,
        listTileTheme: const ListTileThemeData(
          dense: true,
          minVerticalPadding: 4,
        ),
      ),
      child: PopScope(
        canPop: selectedSection == null,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && selectedSection != null) {
            setState(() => selectedSection = null);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: 48,
            title: Text(
              selectedSection ?? 'Settings',
              style: const TextStyle(fontSize: 18),
            ),
            leading: selectedSection == null
                ? null
                : BackButton(
                    onPressed: () => setState(() => selectedSection = null),
                  ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: settingsLayout(
                children: [
                  settingsCategory(
                    icon: Icons.person_outline,
                    title: 'Profile settings',
                    children: [
                      if (widget.session.activeProfile != null)
                        ListTile(
                          title: const Text('Edit current account'),
                          subtitle: Text(widget.session.activeProfile!.name),
                          leading: const Icon(Icons.edit_outlined),
                          onTap: widget.editAccount,
                        ),
                      addAccountTile(),
                      if (widget.session.activeProfile != null)
                        ListTile(
                          leading: const Icon(Icons.switch_account_outlined),
                          title: const Text('Switch account'),
                          onTap: () async {
                            await widget.switchUser();
                            if (context.mounted) Navigator.pop(context);
                          },
                        ),
                      accountManagement(),
                    ],
                  ),
                  if (widget.session.activeProfile != null) ...[
                    settingsCategory(
                      icon: Icons.video_settings,
                      title: 'Player settings',
                      children: [
                        ListTile(
                          onTap: playerDefaults,
                          title: const Text('Playback defaults'),
                          subtitle: const Text(
                            'Seek interval and playback speed',
                          ),
                        ),
                      ],
                    ),
                    settingsCategory(
                      icon: Icons.palette_outlined,
                      title: 'Appearance and browsing',
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Wrap(
                            spacing: 8,
                            children: [
                              for (final entry
                                  in AppAppearance.backgrounds.entries)
                                ChoiceChip(
                                  label: Text(entry.key),
                                  selected:
                                      widget.appearance.selected == entry.key,
                                  onSelected: (_) =>
                                      widget.appearance.choose(entry.key),
                                ),
                            ],
                          ),
                        ),
                        for (final type in ContentType.values)
                          SwitchListTile(
                            dense: true,
                            title: Text('${type.label} cards'),
                            value: widget.appearance.usesCards(type),
                            onChanged: (value) =>
                                widget.appearance.setCards(type, value),
                          ),
                      ],
                    ),
                    settingsCategory(
                      icon: Icons.shield_outlined,
                      title: 'Parental controls',
                      children: [
                        ListTile(
                          leading: const Icon(Icons.lock_outline),
                          title: const Text('Set or change parental PIN'),
                          onTap: changePin,
                        ),
                        ExpansionTile(
                          leading: const Icon(Icons.lock_outline),
                          title: const Text(
                            'PIN protection and hidden categories',
                          ),
                          children: [
                            for (final type in [
                              ContentType.live,
                              ContentType.series,
                              ContentType.movies,
                            ])
                              ExpansionTile(
                                title: Text(type.label),
                                childrenPadding: const EdgeInsets.only(
                                  left: 16,
                                ),
                                children: [
                                  ListTile(
                                    dense: true,
                                    title: const Text(
                                      'Category PIN protection',
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => openParental(
                                      CategoryLockSettingsScreen(
                                        provider: widget.session.provider!,
                                        type: type,
                                      ),
                                    ),
                                  ),
                                  ListTile(
                                    dense: true,
                                    title: const Text('Title PIN protection'),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => openParental(
                                      TitleLockSettingsScreen(
                                        provider: widget.session.provider!,
                                        type: type,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                    settingsCategory(
                      icon: Icons.storage_outlined,
                      title: 'Storage and history',
                      children: [
                        ListTile(
                          leading: const Icon(Icons.history),
                          title: const Text('Clear watch history'),
                          subtitle: const Text(
                            'Resume positions and recordings are preserved.',
                          ),
                          onTap: clearingHistory ? null : clearHistory,
                        ),
                        ListTile(
                          leading: const Icon(Icons.delete_outline),
                          title: const Text('Delete all recordings'),
                          subtitle: const Text('For this profile only'),
                          onTap: clearRecordings,
                        ),
                      ],
                    ),
                  ],
                  if (widget.session.error != null) Text(widget.session.error!),
                  if (widget.appearance.error != null)
                    Text(widget.appearance.error!),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
