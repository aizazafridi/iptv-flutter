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
              'STREAMORA',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 22,
                letterSpacing: 4,
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
                            24)
                        .clamp(64.0, 112.0);
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
                          managing ? 'Manage profiles' : 'Choose your profile',
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 30,
                            letterSpacing: .3,
                            height: 1.2,
                            fontWeight: FontWeight.w400,
                            color: Color(0xfff1f4fa),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          managing
                              ? 'PERSONALIZE YOUR EXPERIENCE'
                              : 'SELECT A PROFILE TO CONTINUE',
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 10,
                            letterSpacing: 2.2,
                            fontWeight: FontWeight.w500,
                            color: Color(0xff8fa8c4),
                          ),
                        ),
                        const SizedBox(height: 28),
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
  Widget build(BuildContext context) => Focus(
    focusNode: focus,
    descendantsAreFocusable: false,
    onKeyEvent: (_, event) => onKey(event),
    child: ListenableBuilder(
      listenable: focus,
      builder: (context, _) => AnimatedScale(
        scale: selected
            ? 1.06
            : focus.hasFocus
            ? 1.03
            : 1,
        duration: const Duration(milliseconds: 170),
        child: Semantics(
          button: true,
          label: name,
          selected: focus.hasFocus,
          child: GestureDetector(
            onTap: onActivate,
            child: AnimatedContainer(
              key: ValueKey('profile-card-$id'),
              width: size + 24,
              duration: const Duration(milliseconds: 170),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: focus.hasFocus
                    ? const Color(0xff26374d)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: focus.hasFocus
                      ? const Color(0xff64b5f6)
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      if (avatar != null)
                        ProfileAvatar(avatar!, size: size, roundedSquare: true)
                      else
                        Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(
                            color: const Color(0xff202b3b),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.add,
                            size: 36,
                            color: Colors.white70,
                          ),
                        ),
                      if (editing && avatar != null)
                        const Positioned(
                          right: 6,
                          bottom: 6,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: Color(0xff15243b),
                            child: Icon(
                              Icons.edit_outlined,
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      letterSpacing: .2,
                      color: focus.hasFocus ? Colors.white : Colors.white60,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
