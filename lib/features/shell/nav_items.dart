import 'package:flutter/material.dart';

/// Port of components/layout/nav-items.ts
class NavItem {
  final String path;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool adminOnly;
  final bool mobileOnly;
  const NavItem(this.path, this.label, this.icon, this.activeIcon, {this.adminOnly = false, this.mobileOnly = false});
}

const navItems = [
  NavItem('/app', 'Messages', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded),
  NavItem('/app/calls', 'Calls', Icons.call_outlined, Icons.call_rounded),
  NavItem('/app/hives', 'Hives', Icons.hexagon_outlined, Icons.hexagon_rounded),
  NavItem('/app/friends', 'Contacts', Icons.person_outline_rounded, Icons.person_rounded),
  NavItem('/app/profile', 'Profile', Icons.account_circle_outlined, Icons.account_circle_rounded, mobileOnly: true),
  NavItem('/app/admin', 'Security', Icons.shield_outlined, Icons.shield_rounded, adminOnly: true),
];

bool isActive(NavItem item, String location) =>
    item.path == '/app' ? (location == '/app' || location.startsWith('/app/chat')) : location.startsWith(item.path);
