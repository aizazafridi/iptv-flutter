import 'package:flutter/material.dart';
import 'smooth_page_route.dart';
import '../application/session.dart';
import '../application/appearance.dart';
import 'settings_screen.dart';
import '../domain/models.dart';
import 'browse_screen.dart';
import 'widgets.dart';
import 'profile_avatar.dart';
import 'system_clock.dart';

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
                : 'STREAMLANE',
          ),
          actions: [
            if (!widget.addAccountOnly) const SystemClock(),
            if (!widget.addAccountOnly && session.account != null)
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
            if (!widget.addAccountOnly && session.activeProfile != null)
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
        body: session.loading
            ? const EmptyLoading()
            : widget.addAccountOnly
            ? login()
            : session.account == null
            ? profilePicker()
            : dashboard(),
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
                  width: 220,
                  child: Column(
                    children: [
                      FocusCard(
                        autofocus:
                            widget.session.profiles.first.id == profile.id,
                        onTap: () => widget.session.selectProfile(profile),
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

  Widget login() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Your entertainment.\nOne place.',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                widget.editProfile != null
                    ? 'Update your account details and avatar.'
                    : 'Add your IPTV account, name and avatar.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: profileName,
                maxLength: 30,
                decoration: const InputDecoration(labelText: 'Account name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter an account name'
                    : null,
              ),
              const Text('Choose an avatar'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (
                    var index = 0;
                    index < ProfileAvatar.names.length;
                    index++
                  )
                    Tooltip(
                      message: ProfileAvatar.names[index],
                      child: InkWell(
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
              const SizedBox(height: 24),
              TextFormField(
                controller: server,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://your-server:port',
                ),
                validator: (value) {
                  final uri = Uri.tryParse(value?.trim() ?? '');
                  return uri != null &&
                          ['http', 'https'].contains(uri.scheme) &&
                          uri.host.isNotEmpty
                      ? null
                      : 'Enter a valid HTTP or HTTPS URL';
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: username,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter your username'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: password,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Password'),
                onFieldSubmitted: (_) => connect(),
                validator: (value) => value == null || value.isEmpty
                    ? 'Enter your password'
                    : null,
              ),
              if (widget.session.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    widget.session.error!,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: connect,
                icon: const Icon(Icons.login),
                label: Text(
                  widget.editProfile != null ? 'Save changes' : 'Connect',
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget dashboard() {
    final session = widget.session;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - 48).clamp(0, double.infinity),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'What are we watching?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                ),
                if (session.error != null)
                  Text(
                    session.error!,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                const SizedBox(height: 32),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: session.provider!.supportedTypes
                      .map(
                        (type) => SizedBox(
                          width: 280,
                          child: FocusCard(
                            autofocus: type == ContentType.live,
                            onTap: () => Navigator.of(context).push(
                              SmoothPageRoute<void>(
                                builder: (_) => BrowseScreen(
                                  provider: session.provider!,
                                  type: type,
                                  appearance: widget.appearance,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    switch (type) {
                                      ContentType.live => Icons.live_tv,
                                      ContentType.movies =>
                                        Icons.movie_outlined,
                                      ContentType.series =>
                                        Icons.video_library_outlined,
                                    },
                                    size: 64,
                                    color: const Color(0xffc1a8ff),
                                  ),
                                  const SizedBox(height: 30),
                                  Text(
                                    type.label,
                                    style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EmptyLoading extends StatelessWidget {
  const EmptyLoading({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 20),
        Text('Connecting to your account…'),
      ],
    ),
  );
}
