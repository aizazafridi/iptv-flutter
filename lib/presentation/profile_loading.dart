import 'package:flutter/material.dart';
import '../domain/models.dart';

/// Startup checks reflect completed work, never elapsed animation time.
class ProfileLoading extends StatefulWidget {
  final AccountProfile profile;
  final Offset origin;
  final double progress;
  final bool profileLoaded, historyLoaded, contentPrepared;
  const ProfileLoading({
    super.key,
    required this.profile,
    required this.origin,
    required this.progress,
    this.profileLoaded = false,
    this.historyLoaded = false,
    this.contentPrepared = false,
  });
  @override
  State<ProfileLoading> createState() => ProfileLoadingState();
}

class ProfileLoadingState extends State<ProfileLoading> {
  Future<void> finish() async {
    // Let the final completed check render before entering the dashboard.
    await WidgetsBinding.instance.endOfFrame;
  }

  Widget stage(String label, bool complete, bool active) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: complete
              ? const Icon(
                  Icons.check_circle,
                  size: 20,
                  color: Color(0xFF548FFF),
                )
              : active
              ? const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF8CBDFF),
                )
              : const Icon(
                  Icons.circle_outlined,
                  size: 20,
                  color: Color(0xFF69788F),
                ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFE3E9F3),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(0.3, 0.1),
        radius: 1.15,
        colors: [Color(0xFF102442), Color(0xFF050C1B), Color(0xFF020611)],
      ),
    ),
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 148,
              height: 148,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 136,
                    height: 136,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF2687FF,
                          ).withValues(alpha: 0.12),
                          blurRadius: 24,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                  ),
                  const Positioned.fill(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF67B6FF),
                      backgroundColor: Color(0xFF10233E),
                      semanticsLabel: 'Preparing your profile',
                    ),
                  ),
                  const Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'St',
                          style: TextStyle(color: Color(0xFF579DFF)),
                        ),
                        TextSpan(
                          text: 'reamora',
                          style: TextStyle(color: Color(0xFFE7F0FF)),
                        ),
                      ],
                    ),
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            const Text(
              'Getting your experience ready...',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: 245,
              child: Column(
                children: [
                  stage(
                    'Loading profile',
                    widget.profileLoaded,
                    !widget.profileLoaded,
                  ),
                  stage(
                    'Syncing watch history',
                    widget.historyLoaded,
                    widget.profileLoaded && !widget.historyLoaded,
                  ),
                  stage(
                    'Preparing content',
                    widget.contentPrepared,
                    widget.historyLoaded && !widget.contentPrepared,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
