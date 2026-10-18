import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_scope.dart';
import 'theme/app_theme.dart';
import '../widgets/common.dart';

/// Shows a locked screen to non-admins while the admin's "Maintenance mode" is on (live).
class MaintenanceGate extends StatefulWidget {
  final Widget child;
  const MaintenanceGate({super.key, required this.child});
  @override
  State<MaintenanceGate> createState() => _MaintenanceGateState();
}

class _MaintenanceGateState extends State<MaintenanceGate> {
  final db = Supabase.instance.client;
  bool _on = false;
  RealtimeChannel? _ch;

  @override
  void initState() {
    super.initState();
    _load();
    _ch = db
        .channel(
          'app_settings_maintenance:${DateTime.now().millisecondsSinceEpoch}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_settings',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  Future<void> _load() async {
    try {
      final r = await db
          .from('app_settings')
          .select('value')
          .eq('key', 'maintenance_mode')
          .maybeSingle();
      if (mounted) setState(() => _on = r?['value'] == true);
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_ch != null) db.removeChannel(_ch!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        if (!_on || !auth.isSignedIn || auth.isAdmin) return widget.child;
        return Material(
          color: context.tr.bg,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const EmptyState(
                icon: Icons.construction_rounded,
                title: 'Down for maintenance',
                subtitle: "TR MATRIX is being updated. We'll be back soon.",
              ),
              TextButton(
                onPressed: auth.signOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
        );
      },
    );
  }
}
