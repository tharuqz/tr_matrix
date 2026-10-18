import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A user-made chat folder (name + the chats inside it).
class ChatFolder {
  final String id;
  final String name;
  final List<String> chatIds;
  const ChatFolder({
    required this.id,
    required this.name,
    this.chatIds = const [],
  });

  ChatFolder copyWith({String? name, List<String>? chatIds}) => ChatFolder(
        id: id,
        name: name ?? this.name,
        chatIds: chatIds ?? this.chatIds,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'chat_ids': chatIds,
      };
  factory ChatFolder.fromJson(Map<String, dynamic> j) => ChatFolder(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        chatIds: [
          for (final c in (j['chat_ids'] as List? ?? const [])) c.toString(),
        ],
      );
}

/// Custom chat folders, saved on this device (`trmatrix:chat_folders:v1`).
/// Works offline; falls back to memory when storage is unavailable.
class ChatFoldersStore {
  static const key = 'trmatrix:chat_folders:v1';
  static const maxNameLength = 24;

  final _controller = StreamController<List<ChatFolder>>.broadcast();
  List<ChatFolder> _folders = [];
  bool _loaded = false;

  Stream<List<ChatFolder>> get stream => _controller.stream;
  List<ChatFolder> get folders => List.unmodifiable(_folders);

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        _folders = [
          for (final f in (jsonDecode(raw) as List))
            ChatFolder.fromJson(Map<String, dynamic>.from(f as Map)),
        ];
      }
    } catch (_) {}
    _loaded = true;
    _emit();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(folders);
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        jsonEncode([for (final f in _folders) f.toJson()]),
      );
    } catch (_) {}
    _emit();
  }

  /// Returns null when the name is empty or already used.
  Future<ChatFolder?> create(String name, List<String> chatIds) async {
    await load();
    final n = _clean(name);
    if (n.isEmpty || _taken(n)) return null;
    final f = ChatFolder(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: n,
      chatIds: chatIds.toSet().toList(),
    );
    _folders = [..._folders, f];
    await _save();
    return f;
  }

  Future<bool> rename(String id, String name) async {
    await load();
    final n = _clean(name);
    if (n.isEmpty || _taken(n, except: id)) return false;
    _folders = [for (final f in _folders) f.id == id ? f.copyWith(name: n) : f];
    await _save();
    return true;
  }

  Future<void> setChats(String id, List<String> chatIds) async {
    await load();
    _folders = [
      for (final f in _folders)
        f.id == id ? f.copyWith(chatIds: chatIds.toSet().toList()) : f,
    ];
    await _save();
  }

  Future<void> toggleChat(String id, String chatId) async {
    final f = _folders.where((f) => f.id == id).firstOrNull;
    if (f == null) return;
    final ids = [...f.chatIds];
    ids.contains(chatId) ? ids.remove(chatId) : ids.add(chatId);
    await setChats(id, ids);
  }

  Future<void> delete(String id) async {
    await load();
    _folders = _folders.where((f) => f.id != id).toList();
    await _save();
  }

  /// Test helper.
  void debugReset() {
    _folders = [];
    _loaded = false;
  }

  static String _clean(String s) {
    final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length > maxNameLength ? t.substring(0, maxNameLength) : t;
  }

  /// Built-in names can't be reused.
  bool _taken(String n, {String? except}) {
    final l = n.toLowerCase();
    if (const ['all', 'hives', 'archived'].contains(l)) return true;
    return _folders.any((f) => f.id != except && f.name.toLowerCase() == l);
  }
}

final chatFoldersStore = ChatFoldersStore();
