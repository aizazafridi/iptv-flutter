import 'package:flutter/material.dart';

/// A TV silhouette keeps channel selection distinct from the programme list.
class ChannelListIcon extends StatelessWidget {
  final double? size;
  const ChannelListIcon({super.key, this.size});
  @override
  Widget build(BuildContext context) => Icon(Icons.tv_outlined, size: size);
}
