import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../application/phone_companion_server.dart';

class PhoneCompanionPanel extends StatefulWidget {
  final PhoneCompanionServer server;
  const PhoneCompanionPanel({super.key, required this.server});
  @override
  State<PhoneCompanionPanel> createState() => _PhoneCompanionPanelState();
}

class _PhoneCompanionPanelState extends State<PhoneCompanionPanel> {
  Timer? tick;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    tick?.cancel();
    super.dispose();
  }

  Future<void> toggle() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.server.running) {
        await widget.server.stop();
      } else {
        await widget.server.start();
      }
    } catch (e) {
      error = e is CompanionError
          ? e.message
          : 'Could not enable phone access. Check your network and firewall.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.server;
    return AlertDialog(
      title: const Text('Phone companion', style: TextStyle(fontSize: 22)),
      content: SizedBox(
        width: 550,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Search, manage My List and send titles from your phone. Use the same trusted home Wi-Fi. Local access uses HTTP.',
              ),
              if (s.running) ...[
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (s.urls.isNotEmpty)
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(8),
                        child: QrImageView(data: s.urls.first, size: 154),
                      ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Scan or open on your phone'),
                          for (final url in s.urls)
                            SelectableText(
                              url,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Color(0xff83bfff),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Text(
                            s.codeExpired
                                ? 'Code expired'
                                : s.code.isEmpty
                                ? 'Phone paired'
                                : s.code,
                            style: const TextStyle(
                              fontSize: 30,
                              letterSpacing: 4,
                            ),
                          ),
                          const Text(
                            'Code expires after 5 minutes. Each code pairs one phone.',
                            style: TextStyle(fontSize: 12),
                          ),
                          Text(
                            '${s.pairedCount} paired phone(s)',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: busy ? null : () => setState(s.newCode),
                  child: const Text('New pairing code'),
                ),
                const Text(
                  'Access ends when you disconnect phones, switch profiles, or close Streamora. Keep this screen open to pair. You can then send titles while browsing or watching.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: busy ? null : toggle,
          child: Text(
            busy
                ? 'Please wait…'
                : s.running
                ? 'Disconnect all phones'
                : 'Enable phone access',
          ),
        ),
      ],
    );
  }
}
