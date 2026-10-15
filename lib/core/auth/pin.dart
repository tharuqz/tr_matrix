/// Port of src/lib/auth/pin.ts — username + PIN mapped to the backend's
/// email/password sign-in exactly like the website, so the same accounts work.
class Pin {
  static const emailDomain = 'trmatrix-app.com';
  static const fallbackEmailDomain = 'trmatrix-fallback.com';
  static const legacyEmailDomains = ['trmatrix.local', 'trmatrix.immediate.local'];
  static const pinSalt = 'trmatrix.pin.v1';
  static final usernameRegex = RegExp(r'^[a-zA-Z0-9_]{3,20}$');
  static const adminUsernames = ['tharuka', 'trmain'];

  static String normalize(String u) => u.trim().toLowerCase();
  static String pseudoEmail(String u) => '${normalize(u)}@$emailDomain';

  static List<String> loginEmails(String u) {
    final n = normalize(u);
    return [
      '$n@$emailDomain',
      '$n@$fallbackEmailDomain',
      ...legacyEmailDomains.map((d) => '$n@$d'),
    ];
  }

  static String padPin(String pin) => '$pin$pinSalt';

  /// Try PIN-padded and raw encodings, same as the website.
  static List<String> candidatePasswords(String value) {
    final out = <String>{};
    if (RegExp(r'^\d{4,6}$').hasMatch(value)) out.add(padPin(value));
    if (value.length >= 6) out.add(value);
    return out.toList();
  }

  static bool isValidPin(String p) => RegExp(r'^\d{4,6}$').hasMatch(p);
  static bool isValidUsername(String u) => usernameRegex.hasMatch(u);
}
