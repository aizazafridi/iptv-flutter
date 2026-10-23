import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'smooth_page_route.dart';
import '../application/session.dart';
import '../application/appearance.dart';
import 'settings_screen.dart';
import '../domain/models.dart';
import 'widgets.dart';
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
  Offset loadingOrigin = Offset.zero;
  Future<void> selectProfile(AccountProfile profile) async {
    if (selectingProfile != null || widget.session.loading) return;
    final profileBox =
        profileKeys[profile.id]?.currentContext?.findRenderObject()
            as RenderBox?;
    final bodyBox = bodyKey.currentContext?.findRenderObject() as RenderBox?;
    loadingOrigin = profileBox != null && bodyBox != null
        ? profileBox.localToGlobal(profileBox.size.center(Offset.zero)) -
              bodyBox.localToGlobal(bodyBox.size.center(Offset.zero))
        : Offset.zero;
    setState(() => selectingProfile = profile);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await widget.session.selectProfile(profile);
    if (!mounted) return;
    if (widget.session.error == null) await loadingKey.currentState?.finish();
    if (mounted) setState(() => selectingProfile = null);
  }

  late final List<FocusNode> accountFields = List.generate(
    4,
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
          if (index < 3) {
            accountFields[index + 1].requestFocus();
          } else {
            node.nextFocus();
          }
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          if (index > 0) {
            accountFields[index - 1].requestFocus();
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
  final form = GlobalKey<FormState>();
  final server = TextEditingController(),
      username = TextEditingController(),
      password = TextEditingController();
  // New accounts use the generic Xtream adapter; edits retain their adapter.
  String get providerId => widget.editProfile?.config.providerId ?? 'xtream';
  final profileName = TextEditingController();
  int avatar = 0;
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
      server.text = config.server;
      if (!widget.addAccountOnly || widget.editProfile != null) {
        username.text = config.username;
        password.text = config.password;
      }
    }
    final editing = widget.editProfile;
    if (editing != null) {
      profileName.text = editing.name;
      avatar = editing.avatar;
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

  Future<void> addAccount() async {
    final added = await Navigator.of(context).push<bool>(
      SmoothPageRoute<bool>(
        builder: (_) => HomeScreen(
          session: widget.session,
          appearance: widget.appearance,
          addAccountOnly: true,
        ),
      ),
    );
    if (mounted && added == true) Navigator.of(context).pop();
  }

  Future<void> editAccount() async {
    final profile = widget.session.activeProfile;
    if (profile == null) return;
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
          username: username.text.trim(),
          password: password.text,
        ),
        name: profileName.text,
        avatar: avatar,
      );
      if (mounted && saved) Navigator.of(context).pop(true);
      return;
    }
    final previousId = widget.session.activeProfile?.id;
    await widget.session.connect(
      ProviderConfig(
        providerId: providerId,
        server: server.text.trim(),
        username: username.text.trim(),
        password: password.text,
      ),
      name: profileName.text,
      avatar: avatar,
    );
    if (mounted &&
        widget.addAccountOnly &&
        widget.session.activeProfile?.id != previousId &&
        widget.session.error == null) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final session = widget.session;
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: widget.addAccountOnly ? null : 68,
          title: Text(
            widget.editProfile != null
                ? 'Edit account'
                : widget.addAccountOnly
                ? 'Add account'
                : 'STREAMORA',
          ),
          actions: [
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
                ],
              ),
          ],
        ),
        body: SizedBox.expand(
          key: bodyKey,
          child: selectingProfile != null
              ? ProfileLoading(
                  key: loadingKey,
                  profile: selectingProfile!,
                  origin: loadingOrigin,
                  progress: session.loadingProgress ?? 0,
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
  Widget profilePicker() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Who's watching?",
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          if (widget.session.error != null) Text(widget.session.error!),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final profile in widget.session.profiles)
                SizedBox(
                  key: profileKeys.putIfAbsent(profile.id, () => GlobalKey()),
                  width: 220,
                  child: Column(
                    children: [
                      FocusCard(
                        autofocus:
                            widget.session.profiles.first.id == profile.id,
                        onTap: () => selectProfile(profile),
                        child: Column(
                          children: [
                            ProfileAvatar(profile.avatar, size: 160),
                            const SizedBox(height: 12),
                            Text(
                              profile.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (widget.session.profiles.isEmpty)
            const Text(
              'No saved accounts. Open Settings to add your first account.',
            ),
        ],
      ),
    ),
  );

  List<TextEditingController> get fieldControllers => [
    profileName,
    server,
    username,
    password,
  ];
  static const fieldLabels = [
    'Account name',
    'Server URL',
    'Username',
    'Password',
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
            obscureText: index == 3,
            autocorrect: false,
            enableSuggestions: index != 3,
            maxLength: index == 0 ? 30 : null,
            keyboardType: index == 1 ? TextInputType.url : TextInputType.text,
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
      obscureText: index == 3,
      onTap: () => editField(index),
      decoration: InputDecoration(
        labelText: fieldLabels[index],
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        suffixIcon: const Icon(Icons.edit_outlined, size: 18),
      ),
      validator: (value) {
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
                  child: ProfileAvatar(index, size: 48),
                ),
              ),
            ),
        ],
      ),
    ],
  );

  Widget login() => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 700;
      final fields = Column(
        mainAxisSize: MainAxisSize.min,
        children: [for (var index = 0; index < 4; index++) accountField(index)],
      );
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 900 : 460),
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
                        SizedBox(width: 230, child: accountAvatars()),
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
