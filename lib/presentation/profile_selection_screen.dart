import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import 'profile_avatar.dart';

class ProfileSelectionScreen extends StatefulWidget {
  final List<AccountProfile> profiles;
  final String? lastProfileId, error;
  final Future<void> Function(AccountProfile) onSelect, onManage;
  final VoidCallback onAdd;
  const ProfileSelectionScreen({
    super.key,
    required this.profiles,
    this.lastProfileId,
    this.error,
    required this.onSelect,
    required this.onManage,
    required this.onAdd,
  });
  @override
  State<ProfileSelectionScreen> createState() => _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends State<ProfileSelectionScreen> {
  final nodes = <String, FocusNode>{};
  final manageFocus = FocusNode(debugLabel: 'manage profiles');
  bool managing = false, selecting = false;
  String? selected;
  List<String> get ids => [
    ...widget.profiles.map((p) => p.id),
    if (widget.profiles.length < 5) 'add',
  ];
  FocusNode node(String id) =>
      nodes.putIfAbsent(id, () => FocusNode(debugLabel: 'profile $id'));
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        node(
          ids.contains(widget.lastProfileId)
              ? widget.lastProfileId!
              : ids.first,
        ).requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final item in nodes.values) {
      item.dispose();
    }
    manageFocus.dispose();
    super.dispose();
  }

  Future<void> chooseProfile(String id) async {
    if (selecting) return;
    if (id == 'add') {
      widget.onAdd();
      return;
    }
    final profile = widget.profiles.firstWhere((p) => p.id == id);
    if (managing) {
      await widget.onManage(profile);
      return;
    }
    setState(() {
      selected = id;
      selecting = true;
    });
    await Future<void>.delayed(
      MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
    );
    if (!mounted) return;
    await widget.onSelect(profile);
    if (mounted) {
      setState(() {
        selected = null;
        selecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xff0d111b),
    child: SafeArea(
      child: Stack(
        children: [
          const Positioned(
            top: 24,
            left: 32,
            child: Text(
              'Streamora',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: Color(0xff64b5f6),
              ),
            ),
          ),
          Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final count = ids.length;
                final size =
                    ((constraints.maxWidth - 64 - (count - 1) * 20) / count -
                            12)
                        .clamp(72.0, 150.0);
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 80,
                  ),
                  child: AnimatedOpacity(
                    opacity: selecting ? .15 : 1,
                    duration: const Duration(milliseconds: 300),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          managing ? 'Manage profiles' : "Who's watching?",
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 44,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 38),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var index = 0; index < count; index++)
                              Padding(
                                padding: EdgeInsets.only(
                                  right: index == count - 1 ? 0 : 20,
                                ),
                                child: _ProfileChoice(
                                  id: ids[index],
                                  name: ids[index] == 'add'
                                      ? 'Add profile'
                                      : widget.profiles
                                            .firstWhere(
                                              (p) => p.id == ids[index],
                                            )
                                            .name,
                                  avatar: ids[index] == 'add'
                                      ? null
                                      : widget.profiles
                                            .firstWhere(
                                              (p) => p.id == ids[index],
                                            )
                                            .avatar,
                                  size: size,
                                  focus: node(ids[index]),
                                  editing: managing,
                                  selected: selected == ids[index],
                                  onActivate: () => chooseProfile(ids[index]),
                                  onKey: (event) {
                                    if (event is! KeyDownEvent &&
                                        event is! KeyRepeatEvent) {
                                      return KeyEventResult.ignored;
                                    }
                                    if (event.logicalKey ==
                                            LogicalKeyboardKey.arrowLeft ||
                                        event.logicalKey ==
                                            LogicalKeyboardKey.arrowRight) {
                                      node(
                                        ids[(index +
                                                (event.logicalKey ==
                                                        LogicalKeyboardKey
                                                            .arrowLeft
                                                    ? -1
                                                    : 1))
                                            .clamp(0, count - 1)],
                                      ).requestFocus();
                                      return KeyEventResult.handled;
                                    }
                                    if (event.logicalKey ==
                                        LogicalKeyboardKey.arrowDown) {
                                      manageFocus.requestFocus();
                                      return KeyEventResult.handled;
                                    }
                                    if (event is KeyDownEvent &&
                                        (event.logicalKey ==
                                                LogicalKeyboardKey.select ||
                                            event.logicalKey ==
                                                LogicalKeyboardKey.enter)) {
                                      unawaited(chooseProfile(ids[index]));
                                      return KeyEventResult.handled;
                                    }
                                    return KeyEventResult.ignored;
                                  },
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        Focus(
                          canRequestFocus: false,
                          onKeyEvent: (_, event) {
                            if (event is KeyDownEvent &&
                                event.logicalKey ==
                                    LogicalKeyboardKey.arrowUp) {
                              node(
                                ids.contains(widget.lastProfileId)
                                    ? widget.lastProfileId!
                                    : ids.first,
                              ).requestFocus();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: OutlinedButton(
                            focusNode: manageFocus,
                            onPressed: selecting
                                ? null
                                : () => setState(() => managing = !managing),
                            child: Text(
                              managing ? 'Done' : 'Manage Profiles',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                        if (widget.error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: Text(
                              widget.error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _ProfileChoice extends StatelessWidget {
  final String id, name;
  final int? avatar;
  final double size;
  final FocusNode focus;
  final bool editing, selected;
  final VoidCallback onActivate;
  final KeyEventResult Function(KeyEvent) onKey;
  const _ProfileChoice({
    required this.id,
    required this.name,
    this.avatar,
    required this.size,
    required this.focus,
    required this.editing,
    required this.selected,
    required this.onActivate,
    required this.onKey,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onActivate,
    child: Focus(
      focusNode: focus,
      onKeyEvent: (_, event) => onKey(event),
      child: ListenableBuilder(
        listenable: focus,
        builder: (context, _) => SizedBox(
          width: size + 12,
          child: Column(
            children: [
              AnimatedScale(
                scale: selected
                    ? 1.08
                    : focus.hasFocus
                    ? 1.04
                    : 1,
                duration: const Duration(milliseconds: 170),
                curve: Curves.easeOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: focus.hasFocus
                          ? const Color(0xff64b5f6)
                          : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: focus.hasFocus
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xff64b5f6,
                              ).withValues(alpha: .15),
                              blurRadius: 12,
                            ),
                          ]
                        : [],
                  ),
                  child: Material(
                    color: const Color(0xff202b3b),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      canRequestFocus: false,
                      borderRadius: BorderRadius.circular(16),
                      onTap: onActivate,
                      child: Stack(
                        children: [
                          if (avatar != null)
                            ProfileAvatar(
                              avatar!,
                              size: size,
                              roundedSquare: true,
                            )
                          else
                            SizedBox.square(
                              dimension: size,
                              child: const Icon(
                                Icons.add,
                                size: 48,
                                color: Colors.white70,
                              ),
                            ),
                          if (editing && avatar != null)
                            const Positioned(
                              right: 8,
                              bottom: 8,
                              child: CircleAvatar(
                                radius: 15,
                                backgroundColor: Color(0xff15243b),
                                child: Icon(
                                  Icons.edit_outlined,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 22,
                  color: focus.hasFocus ? Colors.white : Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
