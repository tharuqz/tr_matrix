import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'cache_files.dart';

import 'offline_store.dart';

class EncryptedCache {
  static const _vault = FlutterSecureStorage();
  static final _cipher = AesGcm.with256bits();
  static Future<OfflineStore> create() async {
    final files = await CacheFiles.create();
    Future<SecretKey> key(String uid) async {
      final stored = await _vault.read(key: 'trmatrix.cache.key.$uid');
      if (stored != null) return SecretKey(base64Decode(stored));
      final generated = await _cipher.newSecretKey();
      await _vault.write(
        key: 'trmatrix.cache.key.$uid',
        value: base64Encode(await generated.extractBytes()),
      );
      return generated;
    }

    return OfflineStore(
      read: (uid) async {
        final raw = await files.read(uid);
        if (raw == null) return null;
        final box = jsonDecode(raw) as Map;
        final clear = await _cipher.decrypt(
          SecretBox(
            base64Decode(box['body'] as String),
            nonce: base64Decode(box['nonce'] as String),
            mac: Mac(base64Decode(box['mac'] as String)),
          ),
          secretKey: await key(uid),
        );
        return utf8.decode(clear);
      },
      write: (uid, value) async {
        if (value == null) {
          await files.write(uid, null);
          await _vault.delete(key: 'trmatrix.cache.key.$uid');
          return;
        }
        final box = await _cipher.encrypt(
          utf8.encode(value),
          secretKey: await key(uid),
        );
        await files.write(
          uid,
          jsonEncode({
            'body': base64Encode(box.cipherText),
            'nonce': base64Encode(box.nonce),
            'mac': base64Encode(box.mac.bytes),
          }),
        );
      },
    );
  }
}
