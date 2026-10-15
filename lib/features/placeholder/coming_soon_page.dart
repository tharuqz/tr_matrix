import 'package:flutter/material.dart';
import '../../widgets/common.dart';

/// Placeholder for sections delivered in later parts.
class ComingSoonPage extends StatelessWidget {
  final String title;
  final IconData icon;
  final String part;
  const ComingSoonPage({super.key, required this.title, required this.icon, required this.part});
  @override
  Widget build(BuildContext context) =>
      EmptyState(icon: icon, title: title, subtitle: 'This section arrives in $part.');
}
