import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';

/// Port of routes/app.friends.tsx data logic.
class ContactsRepository {
  final SupabaseClient db;
  ContactsRepository(this.db);
  String get _me => db.auth.currentUser!.id;

  Future<({List<ContactRow> friends, List<ContactRow> incoming, List<ContactRow> outgoing})> load() async {
    final rels = List<Map<String, dynamic>>.from(await db
            .from('relationships')
            .select('id, requester_id, addressee_id, status')
            .or('requester_id.eq.$_me,addressee_id.eq.$_me'))
        .map(Relationship.fromJson)
        .toList();
    final ids = rels.map((r) => r.requesterId == _me ? r.addresseeId : r.requesterId).toList();
    final byId = <String, Profile>{};
    if (ids.isNotEmpty) {
      final ps = await db.from('profiles').select('id, username, display_name, avatar_url').inFilter('id', ids);
      for (final p in List<Map<String, dynamic>>.from(ps)) {
        byId[p['id'] as String] = Profile.fromJson(p);
      }
    }
    final friends = <ContactRow>[], incoming = <ContactRow>[], outgoing = <ContactRow>[];
    for (final r in rels) {
      final p = byId[r.requesterId == _me ? r.addresseeId : r.requesterId];
      if (p == null) continue;
      if (r.status == 'accepted') {
        friends.add(ContactRow(r, p));
      } else if (r.status == 'pending') {
        (r.addresseeId == _me ? incoming : outgoing).add(ContactRow(r, p));
      }
    }
    return (friends: friends, incoming: incoming, outgoing: outgoing);
  }

  Future<List<Profile>> search(String q) async {
    final term = q.trim().toLowerCase();
    if (term.length < 2) return [];
    final rows = await db
        .from('profiles')
        .select('id, username, display_name, avatar_url')
        .or('username.ilike.%$term%,display_name.ilike.%$term%')
        .neq('id', _me)
        .limit(20);
    return List<Map<String, dynamic>>.from(rows).map(Profile.fromJson).toList();
  }

  Future<void> sendRequest(String otherId) =>
      db.from('relationships').insert({'requester_id': _me, 'addressee_id': otherId, 'status': 'pending'});
  Future<void> setStatus(String relId, String status) =>
      db.from('relationships').update({'status': status}).eq('id', relId);
  Future<void> remove(String relId) => db.from('relationships').delete().eq('id', relId);
}
