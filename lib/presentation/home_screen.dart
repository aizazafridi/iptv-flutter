import 'package:flutter/material.dart';
import '../application/session.dart';
import '../domain/models.dart';
import 'browse_screen.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  final Session session;
  const HomeScreen({super.key, required this.session});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final form = GlobalKey<FormState>();
  final server = TextEditingController(),
      username = TextEditingController(),
      password = TextEditingController();
  String providerId = 'starshare';
  @override
  void initState() {
    super.initState();
    final config = widget.session.lastConfig;
    if (config != null) {
      server.text = config.server;
      username.text = config.username;
      password.text = config.password;
      providerId = config.providerId;
    }
  }

  @override
  void dispose() {
    server.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  void connect() {
    if (!form.currentState!.validate()) return;
    widget.session.connect(
      ProviderConfig(
        providerId: providerId,
        server: server.text.trim(),
        username: username.text.trim(),
        password: password.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final session = widget.session;
      return Scaffold(
        appBar: AppBar(
          title: const Text('STREAMLANE'),
          actions: [
            if (session.account != null)
              IconButton(
                tooltip: 'Sign out',
                onPressed: session.signOut,
                icon: const Icon(Icons.logout),
              ),
          ],
        ),
        body: session.loading
            ? const EmptyLoading()
            : session.account == null
            ? login()
            : dashboard(),
      );
    },
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
              const Text(
                'Connect your IPTV account. It will reconnect automatically next time.',
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                initialValue: providerId,
                decoration: const InputDecoration(labelText: 'Provider'),
                items: widget.session.registry.options.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (value) => providerId = value!,
              ),
              const SizedBox(height: 16),
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
                label: const Text('Connect'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget dashboard() {
    final session = widget.session, account = widget.session.account!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What are we watching?',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            '${session.provider!.displayName} · ${account.username} · ${account.status}',
          ),
          if (account.expiresAt != null)
            Text(
              'Expires ${account.expiresAt!.toLocal().toString().split(' ').first}',
            ),
          if (session.error != null)
            Text(
              session.error!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: session.provider!.supportedTypes
                .map(
                  (type) => SizedBox(
                    width: 240,
                    child: FocusCard(
                      autofocus: type == ContentType.live,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => BrowseScreen(
                            provider: session.provider!,
                            type: type,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            switch (type) {
                              ContentType.live => Icons.live_tv,
                              ContentType.movies => Icons.movie_outlined,
                              ContentType.series =>
                                Icons.video_library_outlined,
                            },
                            size: 42,
                            color: const Color(0xffc1a8ff),
                          ),
                          const SizedBox(height: 30),
                          Text(
                            type.label,
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text('Explore categories'),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
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
