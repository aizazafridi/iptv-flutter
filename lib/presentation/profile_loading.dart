import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'profile_avatar.dart';

/// Progress follows completed startup stages, with interpolation between them.
class ProfileLoading extends StatefulWidget {
  final AccountProfile profile;
  final Offset origin;
  final double progress;
  const ProfileLoading({
    super.key,
    required this.profile,
    required this.origin,
    required this.progress,
  });
  @override
  State<ProfileLoading> createState() => ProfileLoadingState();
}

class ProfileLoadingState extends State<ProfileLoading>
    with SingleTickerProviderStateMixin {
  late final progress = AnimationController(vsync: this, value: 0);
  @override
  void initState() {
    super.initState();
    if (widget.origin.distance < 0.5) motionFinished.complete();
    advance();
  }

  final motionFinished = Completer<void>();
  bool finishing = false;
  void advance() {
    if (finishing) return;
    final target = widget.progress.clamp(progress.value, 1.0);
    progress.animateTo(
      target,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant ProfileLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) advance();
  }

  Future<void> finish() async {
    finishing = true;
    try {
      await progress
          .animateTo(
            1,
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeInOutCubic,
          )
          .orCancel;
      await motionFinished.future;
    } on TickerCanceled {
      /* The screen was closed during loading. */
    }
  }

  @override
  void dispose() {
    if (!motionFinished.isCompleted) motionFinished.complete();
    progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: TweenAnimationBuilder<Offset>(
      tween: Tween(begin: widget.origin, end: Offset.zero),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeInOutSine,
      onEnd: () {
        if (!motionFinished.isCompleted) motionFinished.complete();
      },
      builder: (_, offset, child) =>
          Transform.translate(offset: offset, child: child),
      child: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProfileAvatar(widget.profile.avatar, size: 160),
            const SizedBox(height: 12),
            Text(
              widget.profile.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            AnimatedBuilder(
              animation: progress,
              builder: (_, _) => Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress.value,
                      minHeight: 6,
                      semanticsLabel: 'Loading profile',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Loading ${(progress.value * 100).floor()}%',
                    style: const TextStyle(fontSize: 13),
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
