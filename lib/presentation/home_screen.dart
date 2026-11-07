import 'dart:async';
import '../application/category_locks.dart';
import '../data/locked_provider.dart';
import 'lock_password_dialog.dart';
import 'profile_selection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'smooth_page_route.dart';
import '../application/session.dart';
import '../application/appearance.dart';
import 'settings_screen.dart';
import '../domain/models.dart';
import 'profile_avatar.dart';
import 'profile_loading.dart';
import 'system_clock.dart';
import 'dashboard.dart';

class HomeScreen extends StatefulWidget {
  final Session session;
  final AppAppearance appearance;
  final bool addAccountOnly;
  final AccountProfile? editProfile;
  const HomeScreen({
    super.key,
    required this.session,
    required this.appearance,
    this.addAccountOnly = false,
    this.editProfile,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final bodyKey = GlobalKey();
  final profileKeys = <String, GlobalKey>{};
  final loadingKey = GlobalKey<ProfileLoadingState>();
  AccountProfile? selectingProfile;
  Future<bool> verifyProfile(
    AccountProfile profile, {
    bool managing = false,
  }) async {
    final locks = CategoryLocks(profile.id);
    await locks.load();
    if (!mounted) return false;
    if (!locks.profilePinRequired && !(managing && locks.hasPassword)) {
      return true;
    }
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => LockPasswordDialog(locks: locks),
    );
    return mounted && pin != null && locks.check(pin);
  }

  Future<void> selectProfile(AccountProfile profile) async {
    if (selectingProfile != null || widget.session.loading) return;
    if (!await verifyProfile(profile) || !mounted) return;
    setState(() => selectingProfile = profile);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await widget.session.selectProfile(profile);
    if (!mounted) return;
    if (widget.session.error == null) await loadingKey.currentState?.finish();
    if (mounted) setState(() => selectingProfile = null);
  }

  late final List<FocusNode> accountFields = List.generate(
    5,
    (index) => FocusNode(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          editField(index);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          final position = visibleFields.indexOf(index);
          if (position < visibleFields.length - 1) {
            accountFields[visibleFields[position + 1]].requestFocus();
          } else {
            node.nextFocus();
          }
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          final position = visibleFields.indexOf(index);
          if (position > 0) {
            accountFields[visibleFields[position - 1]].requestFocus();
          } else {
            connectionTypeFocus.requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          avatarNodes[avatar].requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    ),
  );
  final avatarNodes = List.generate(
    ProfileAvatar.names.length,
    (_) => FocusNode(),
  );
  final connectionTypeFocus = FocusNode(debugLabel: 'connection type');
  final form = GlobalKey<FormState>();
  final server = TextEditingController(),
      username = TextEditingController(),
      password = TextEditingController();
  // New accounts use the generic Xtream adapter; edits retain their adapter.
  String providerId = 'xtream';
  bool get isM3u => providerId == 'm3u';
  List<int> get visibleFields => [
    0,
    1,
    if (!isM3u) ...[2, 3],
    if (kidsProfile || requireProfilePin) 4,
  ];
  final profileName = TextEditingController();
  int avatar = 0;
  bool kidsProfile = false, requireProfilePin = false, existingPin = false;
  Set<String> allowedKidsCategories = {};
  final profilePin = TextEditingController();
  Future<void> loadPolicy(String id) async {
    final locks = CategoryLocks(id);
    await locks.load();
    if (mounted) {
      setState(() {
        kidsProfile = locks.kidsProfile;
        requireProfilePin = locks.profilePinRequired;
        existingPin = locks.hasPassword;
        allowedKidsCategories = Set.of(locks.allowedKidsCategories);
      });
    }
  }

  Future<void> configurePolicy(CategoryLocks locks) => locks.setProfilePolicy(
    kids: kidsProfile,
    requirePin: requireProfilePin,
    allowed: allowedKidsCategories,
    pin: profilePin.text,
  );

  @override
  void initState() {
    super.initState();
    widget.session.appearance ??= widget.appearance;
    final config =
        widget.editProfile?.config ??
        widget.session.lastConfig ??
        (widget.addAccountOnly && widget.session.profiles.isNotEmpty
            ? widget.session.profiles.last.config
            : null);
    if (config != null) {
      providerId = config.providerId;
      if (!widget.addAccountOnly || widget.editProfile != null) {
        server.text = config.server;
        username.text = config.username;
        password.text = config.password;
      }
    }
    final editing = widget.editProfile;
    if (editing != null) {
      profileName.text = editing.name;
      avatar = editing.avatar;
      unawaited(loadPolicy(editing.id));
    }
  }

  @override
  void dispose() {
    for (final node in avatarNodes) {
      node.dispose();
    }
    for (final node in accountFields) {
      node.dispose();
    }
    profilePin.dispose();
    connectionTypeFocus.dispose();
    profileName.dispose();
    server.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> switchUser() async {
    await widget.session.signOut();
    if (!mounted || widget.session.account != null) return;
    // Retain the server, but require fresh credentials for the next account.
    username.clear();
    password.clear();
  }

  Future<void> addAccount({bool fromStartup = false}) async {
    final added = await Navigator.of(context).push<bool>(
      SmoothPageRoute<bool>(
        builder: (_) => HomeScreen(
          session: widget.session,
          appearance: widget.appearance,
          addAccountOnly: true,
        ),
      ),
    );
    if (mounted && added == true && !fromStartup) Navigator.of(context).pop();
  }

  Future<void> editAccount() async {
    final profile = widget.session.activeProfile;
    if (profile == null) return;
    await editSavedProfile(profile);
  }

  Future<void> editSavedProfile(
    AccountProfile profile, {
    bool verified = false,
  }) async {
    if (!verified && !await verifyProfile(profile, managing: true)) return;
    if (!mounted) return;
    await Navigator.of(context).push<bool>(
      SmoothPageRoute<bool>(
        builder: (_) => HomeScreen(
          session: widget.session,
          appearance: widget.appearance,
          addAccountOnly: true,
          editProfile: profile,
        ),
      ),
    );
  }

  Future<void> connect() async {
    if (!form.currentState!.validate()) return;
    if (widget.editProfile != null) {
      final saved = await widget.session.updateCurrentProfile(
        ProviderConfig(
          providerId: providerId,
          server: server.text.trim(),
          username: isM3u ? '' : username.text.trim(),
          password: isM3u ? '' : password.text,
        ),
        name: profileName.text,
        avatar: avatar,
        profileId: widget.editProfile!.id,
        configureProfile: configurePolicy,
      );
      if (mounted && saved) Navigator.of(context).pop(true);
      return;
    }
    final previousId = widget.session.activeProfile?.id;
    await widget.session.connect(
      ProviderConfig(
        providerId: providerId,
        server: server.text.trim(),
        username: isM3u ? '' : username.text.trim(),
        password: isM3u ? '' : password.text,
      ),
      name: profileName.text,
      avatar: avatar,
      configureProfile: configurePolicy,
    );
    if (mounted &&
        widget.addAccountOnly &&
        widget.session.activeProfile?.id != previousId &&
        widget.session.error == null) {
      Navigator.of(context).pop(true);
    }
  }

  List<Widget> accountActions() {
    final session = widget.session;
    return [
      if (!widget.addAccountOnly) const SystemClock(),
      if (!widget.addAccountOnly &&
          session.account != null &&
          selectingProfile == null)
        IconButton(
          tooltip: 'Switch account',
          iconSize: 32,
          constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
          icon: const Icon(Icons.switch_account_outlined),
          onPressed: session.loading ? null : switchUser,
        ),
      if (!widget.addAccountOnly)
        IconButton(
          tooltip: 'Settings',
          iconSize: 32,
          constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
          icon: const Icon(Icons.settings_outlined),
          onPressed: session.loading
              ? null
              : () => Navigator.of(context).push(
                  SmoothPageRoute<void>(
                    builder: (_) => SettingsScreen(
                      session: session,
                      appearance: widget.appearance,
                      switchUser: switchUser,
                      addAccount: addAccount,
                      editAccount: editAccount,
                    ),
                  ),
                ),
        ),
      if (!widget.addAccountOnly &&
          session.activeProfile != null &&
          selectingProfile == null)
        PopupMenuButton<String>(
          tooltip: 'Current account',
          iconSize: 44,
          enabled: !session.loading,
          icon: ProfileAvatar(session.activeProfile!.avatar, size: 44),
          onSelected: (value) {
            if (value == 'edit') editAccount();
            if (value == 'switch') switchUser();
          },
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              enabled: false,
              child: Text(
                session.activeProfile!.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            PopupMenuItem<String>(
              enabled: false,
              child: Text(
                session.account?.expiresAt == null
                    ? 'Expiry date unavailable'
                    : 'Expires ${MaterialLocalizations.of(context).formatFullDate(session.account!.expiresAt!.toLocal())}',
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Edit'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem<String>(
              value: 'switch',
              child: ListTile(
                leading: Icon(Icons.switch_account_outlined),
                title: Text('Switch account'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final session = widget.session;
      return Scaffold(
        appBar: !widget.addAccountOnly
            ? null
            : AppBar(
                toolbarHeight: widget.addAccountOnly
                    ? null
                    : session.account != null
                    ? 48
                    : 60,
                title: Text(
                  widget.editProfile != null
                      ? 'Edit account'
                      : widget.addAccountOnly
                      ? 'Add account'
                      : session.account != null
                      ? ''
                      : 'STREAMORA',
                ),
                actions: accountActions(),
              ),
        body: SizedBox.expand(
          key: bodyKey,
          child: selectingProfile != null
              ? ProfileLoading(
                  key: loadingKey,
                  profile: selectingProfile!,
                  origin: Offset.zero,
                  progress: session.loadingProgress ?? 0,
                  profileLoaded: session.profileLoaded,
                  historyLoaded: session.historyLoaded,
                  contentPrepared: session.contentPrepared,
                )
              : session.loading
              ? EmptyLoading(
                  message: session.loadingMessage,
                  progress: session.loadingProgress,
                )
              : widget.addAccountOnly
              ? login()
              : session.account == null
              ? profilePicker()
              : dashboard(),
        ),
      );
    },
  );
  Future<void> manageProfile(AccountProfile profile) async {
    if (!await verifyProfile(profile, managing: true) || !mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(profile.name),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'edit'),
            child: const Text('Edit profile'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('Delete profile'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'edit') {
      await editSavedProfile(profile, verified: true);
      return;
    }
    if (!mounted) return;
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete profile?'),
          content: Text('Remove ${profile.name} from this device?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed == true) await widget.session.removeProfile(profile);
    }
  }

  Widget profilePicker() => ProfileSelectionScreen(
    profiles: widget.session.profiles,
    lastProfileId: widget.session.lastProfileId,
    error: widget.session.error,
    onSelect: selectProfile,
    onManage: manageProfile,
    onAdd: () => addAccount(fromStartup: true),
  );

  List<TextEditingController> get fieldControllers => [
    profileName,
    server,
    username,
    password,
    profilePin,
  ];
  List<String> get fieldLabels => [
    'Account name',
    isM3u ? 'M3U playlist URL' : 'Server URL',
    'Username',
    'Password',
    'Six-digit PIN',
  ];
  bool editingField = false;
  Future<void> editField(int index) async {
    if (editingField) return;
    editingField = true;
    final draft = TextEditingController(text: fieldControllers[index].text);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(fieldLabels[index]),
        content: SizedBox(
          width: 440,
          child: TextField(
            controller: draft,
            autofocus: true,
            obscureText: index >= 3,
            autocorrect: false,
            enableSuggestions: index != 3,
            maxLength: index == 0
                ? 30
                : index == 4
                ? 6
                : null,
            inputFormatters: index == 4
                ? [FilteringTextInputFormatter.digitsOnly]
                : null,
            keyboardType: index == 1
                ? TextInputType.url
                : index == 4
                ? TextInputType.number
                : TextInputType.text,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, draft.text),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    // The closing dialog may still paint its editor during the reverse animation.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    draft.dispose();
    editingField = false;
    if (!mounted) return;
    if (value != null) setState(() => fieldControllers[index].text = value);
    accountFields[index].requestFocus();
  }

  Widget accountField(int index) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: fieldControllers[index],
      focusNode: accountFields[index],
      autofocus: index == 0,
      readOnly: true,
      showCursor: false,
      enableInteractiveSelection: false,
      obscureText: index >= 3,
      onTap: () => editField(index),
      decoration: InputDecoration(
        labelText: fieldLabels[index],
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        suffixIcon: const Icon(Icons.edit_outlined, size: 18),
      ),
      validator: (value) {
        if (index == 4) {
          if (value == null || value.isEmpty) {
            return existingPin ? null : 'Enter a six-digit PIN';
          }
          return RegExp(r'^[0-9]{6}$').hasMatch(value)
              ? null
              : 'Use exactly six digits';
        }
        if (value == null || value.trim().isEmpty) {
          return 'Enter ${fieldLabels[index].toLowerCase()}';
        }
        if (index == 1) {
          final uri = Uri.tryParse(value.trim());
          if (uri == null ||
              !['http', 'https'].contains(uri.scheme) ||
              uri.host.isEmpty) {
            return 'Enter a valid HTTP or HTTPS URL';
          }
        }
        return null;
      },
    ),
  );

  Widget accountAvatars() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('Choose an avatar'),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var index = 0; index < ProfileAvatar.names.length; index++)
            Tooltip(
              message: ProfileAvatar.names[index],
              child: InkWell(
                focusNode: avatarNodes[index],
                onTap: () => setState(() => avatar = index),
                borderRadius: BorderRadius.circular(32),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: avatar == index
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: ProfileAvatar(index, size: 38),
                ),
              ),
            ),
        ],
      ),
    ],
  );

  Future<void> chooseKidsCategories() async {
    final draft = ProviderConfig(
      providerId: providerId,
      server: server.text.trim(),
      username: username.text.trim(),
      password: password.text,
    );
    dynamic candidate;
    try {
      candidate = widget.session.registry.create(draft);
      final raw = candidate is LockedProvider ? candidate.delegate : candidate;
      await raw.connect();
      final categories = <Category>[];
      for (final type in ContentType.values) {
        if (raw.supportedTypes.contains(type)) {
          categories.addAll(await raw.getCategories(type) as List<Category>);
        }
      }
      if (!mounted) return;
      final selected = Set<String>.of(allowedKidsCategories);
      final saved = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Allowed Kids categories'),
            content: SizedBox(
              width: 480,
              height: 340,
              child: ListView.builder(
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final category = categories[index];
                  final key = '${category.type.name}:${category.id}';
                  return CheckboxListTile(
                    title: Text(category.name),
                    subtitle: Text(category.type.label),
                    value: selected.contains(key),
                    onChanged: (value) => update(() {
                      if (value == true) {
                        selected.add(key);
                      } else {
                        selected.remove(key);
                      }
                    }),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
      if (mounted && saved == true) {
        setState(() => allowedKidsCategories = selected);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enter working connection details before choosing categories.',
            ),
          ),
        );
      }
    } finally {
      candidate?.dispose();
    }
  }

  Widget login() => Theme(
    data: Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(fontSizeFactor: .82),
      visualDensity: VisualDensity.compact,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 36),
          textStyle: const TextStyle(fontSize: 13),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 36),
          textStyle: const TextStyle(fontSize: 13),
        ),
      ),
    ),
    child: accountForm(),
  );

  Widget accountForm() => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 700;
      final fields = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            focusNode: connectionTypeFocus,
            initialValue: isM3u ? 'm3u' : 'xtream',
            decoration: const InputDecoration(
              labelText: 'Connection type',
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'xtream', child: Text('Xtream Codes')),
              DropdownMenuItem(value: 'm3u', child: Text('M3U Playlist')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => providerId = value);
            },
          ),
          const SizedBox(height: 8),
          for (final index in visibleFields) accountField(index),
          SwitchListTile(
            dense: true,
            title: const Text('Kids profile'),
            subtitle: const Text(
              'Only categories selected by a parent are allowed',
            ),
            value: kidsProfile,
            onChanged: (value) => setState(() => kidsProfile = value),
          ),
          if (kidsProfile)
            TextButton.icon(
              onPressed: chooseKidsCategories,
              icon: const Icon(Icons.child_care),
              label: Text(
                'Allowed categories (${allowedKidsCategories.length})',
              ),
            ),
          SwitchListTile(
            dense: true,
            title: const Text('Require PIN to open profile'),
            value: requireProfilePin,
            onChanged: (value) => setState(() => requireProfilePin = value),
          ),
        ],
      );
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 760 : 440),
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 190, child: accountAvatars()),
                        const SizedBox(width: 32),
                        Expanded(child: fields),
                      ],
                    )
                  else ...[
                    fields,
                    accountAvatars(),
                  ],
                  if (widget.session.error != null)
                    Text(
                      widget.session.error!,
                      style: const TextStyle(color: Colors.orangeAccent),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: connect,
                        icon: const Icon(Icons.check),
                        label: Text(
                          widget.editProfile != null
                              ? 'Save changes'
                              : 'Connect',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget dashboard() => StreamoraDashboard(
    key: ValueKey(widget.session.activeProfile?.id ?? widget.session.provider),
    session: widget.session,
    appearance: widget.appearance,
    headerActions: accountActions(),
    onSettings: () => Navigator.of(context).push(
      SmoothPageRoute<void>(
        builder: (_) => SettingsScreen(
          session: widget.session,
          appearance: widget.appearance,
          switchUser: switchUser,
          addAccount: addAccount,
          editAccount: editAccount,
        ),
      ),
    ),
  );
}

class EmptyLoading extends StatelessWidget {
  final String message;
  final double? progress;
  const EmptyLoading({super.key, this.message = 'Loading', this.progress});
  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox(
      width: 32,
      height: 32,
      child: CircularProgressIndicator(
        strokeWidth: 3,
        semanticsLabel: 'Loading',
      ),
    ),
  );
}
