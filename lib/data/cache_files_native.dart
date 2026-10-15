import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Private app-support files with a recoverable atomic replacement.
class CacheFiles {
  final Directory directory;
  CacheFiles._(this.directory);
  static Future<CacheFiles> create() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/offline-v1');
    await directory.create(recursive: true);
    return CacheFiles._(directory);
  }

  File _file(String uid, [String suffix = '']) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(uid))
      throw ArgumentError('Invalid cache identity');
    return File('${directory.path}/$uid.cache$suffix');
  }

  Future<String?> read(String uid) async {
    final file = _file(uid);
    if (await file.exists()) return file.readAsString();
    final backup = _file(uid, '.bak');
    if (await backup.exists()) {
      await backup.rename(file.path);
      return file.readAsString();
    }
    return null;
  }

  Future<void> write(String uid, String? value) async {
    final file = _file(uid),
        temporary = _file(uid, '.new'),
        backup = _file(uid, '.bak');
    if (value == null) {
      for (final entry in [file, temporary, backup]) {
        if (await entry.exists()) await entry.delete();
      }
      return;
    }
    await temporary.writeAsString(value, flush: true);
    if (await backup.exists()) await backup.delete();
    if (await file.exists()) await file.rename(backup.path);
    try {
      await temporary.rename(file.path);
    } catch (_) {
      if (await backup.exists()) await backup.rename(file.path);
      rethrow;
    }
    if (await backup.exists()) {
      try {
        await backup.delete();
      } catch (_) {}
    }
  }
}
