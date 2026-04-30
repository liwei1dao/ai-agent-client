import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/macs/hmac.dart';

/// 配置导入/导出加密格式：
///
/// ```
/// {
///   "format": "ai-agent-export-v2",
///   "encrypted": true,
///   "kdf": "pbkdf2-sha256",
///   "iterations": 100000,
///   "salt": "...", "iv": "...", "ciphertext": "...", "mac": "...",
///   "meta": { "agents": N, "services": M }
/// }
/// ```
///
/// AES-256-CBC（PKCS7） + HMAC-SHA256（encrypt-then-MAC）。
/// PBKDF2-HMAC-SHA256 派生 64 字节，前 32 字节为 AES 密钥，后 32 字节为 MAC 密钥。
///
/// PBKDF2 计算量较大，所有 API 都通过 [compute] 在后台 isolate 执行，避免阻塞 UI。
class ConfigCrypto {
  static const String formatTag = 'ai-agent-export-v2';
  static const int _iterations = 50000;
  static const int _saltLen = 16;
  static const int _ivLen = 16;

  static final _rng = Random.secure();

  /// 加密任意 JSON 文本，返回加密后的 JSON 字符串。
  static Future<String> encryptJson(
    String plainJson,
    String password, {
    Map<String, dynamic>? meta,
  }) async {
    if (password.isEmpty) {
      throw ArgumentError('password must not be empty');
    }
    final salt = _randomBytes(_saltLen);
    final iv = _randomBytes(_ivLen);
    return compute(_encryptInIsolate, _EncryptArgs(
      plainJson: plainJson,
      password: password,
      salt: salt,
      iv: iv,
      iterations: _iterations,
      meta: meta,
    ));
  }

  /// 探测是否为加密格式（同步，无需 isolate）。
  static bool isEncrypted(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr);
      if (data is! Map) return false;
      return data['encrypted'] == true && data['format'] == formatTag;
    } catch (_) {
      return false;
    }
  }

  /// 解密加密的 JSON，密码错误或文件被篡改时抛出 [ConfigCryptoException]。
  static Future<String> decryptJson(
      String encryptedJson, String password) async {
    final result = await compute(
      _decryptInIsolate,
      _DecryptArgs(encryptedJson: encryptedJson, password: password),
    );
    if (result.error != null) {
      throw ConfigCryptoException(result.error!);
    }
    return result.plain!;
  }

  static Uint8List _randomBytes(int n) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = _rng.nextInt(256);
    }
    return out;
  }
}

class ConfigCryptoException implements Exception {
  final String message;
  ConfigCryptoException(this.message);
  @override
  String toString() => message;
}

// ── isolate entrypoints ──────────────────────────────────────────────────────

class _EncryptArgs {
  final String plainJson;
  final String password;
  final Uint8List salt;
  final Uint8List iv;
  final int iterations;
  final Map<String, dynamic>? meta;
  _EncryptArgs({
    required this.plainJson,
    required this.password,
    required this.salt,
    required this.iv,
    required this.iterations,
    required this.meta,
  });
}

class _DecryptArgs {
  final String encryptedJson;
  final String password;
  _DecryptArgs({required this.encryptedJson, required this.password});
}

class _DecryptResult {
  final String? plain;
  final String? error;
  _DecryptResult.ok(this.plain) : error = null;
  _DecryptResult.err(this.error) : plain = null;
}

String _encryptInIsolate(_EncryptArgs a) {
  final keys = _deriveKeys(a.password, a.salt, a.iterations);
  final encKey = keys.sublist(0, 32);
  final macKey = keys.sublist(32, 64);

  final encrypter = enc.Encrypter(
    enc.AES(enc.Key(encKey), mode: enc.AESMode.cbc, padding: 'PKCS7'),
  );
  final cipherBytes = encrypter
      .encrypt(a.plainJson, iv: enc.IV(a.iv))
      .bytes;

  final macInput = Uint8List.fromList([
    ...a.salt,
    ...a.iv,
    ...cipherBytes,
  ]);
  final mac = crypto.Hmac(crypto.sha256, macKey).convert(macInput).bytes;

  return jsonEncode({
    'format': ConfigCrypto.formatTag,
    'encrypted': true,
    'kdf': 'pbkdf2-sha256',
    'iterations': a.iterations,
    'salt': base64Encode(a.salt),
    'iv': base64Encode(a.iv),
    'ciphertext': base64Encode(cipherBytes),
    'mac': base64Encode(mac),
    if (a.meta != null) 'meta': a.meta,
  });
}

_DecryptResult _decryptInIsolate(_DecryptArgs a) {
  final Map<String, dynamic> data;
  try {
    data = jsonDecode(a.encryptedJson) as Map<String, dynamic>;
  } catch (_) {
    return _DecryptResult.err('文件不是有效的 JSON');
  }
  if (data['format'] != ConfigCrypto.formatTag || data['encrypted'] != true) {
    return _DecryptResult.err('文件不是加密格式');
  }
  final iterations = (data['iterations'] as num?)?.toInt() ?? 50000;
  final salt = _decodeB64(data['salt']);
  final iv = _decodeB64(data['iv']);
  final cipherBytes = _decodeB64(data['ciphertext']);
  final mac = _decodeB64(data['mac']);
  if (salt == null || iv == null || cipherBytes == null || mac == null) {
    return _DecryptResult.err('文件字段缺失或格式错误');
  }

  final keys = _deriveKeys(a.password, salt, iterations);
  final encKey = keys.sublist(0, 32);
  final macKey = keys.sublist(32, 64);

  final macInput = Uint8List.fromList([
    ...salt,
    ...iv,
    ...cipherBytes,
  ]);
  final expectedMac =
      crypto.Hmac(crypto.sha256, macKey).convert(macInput).bytes;
  if (!_constantTimeEq(expectedMac, mac)) {
    return _DecryptResult.err('密码错误，或文件已损坏');
  }

  try {
    final encrypter = enc.Encrypter(
      enc.AES(enc.Key(encKey), mode: enc.AESMode.cbc, padding: 'PKCS7'),
    );
    final plain =
        encrypter.decrypt(enc.Encrypted(cipherBytes), iv: enc.IV(iv));
    return _DecryptResult.ok(plain);
  } catch (_) {
    return _DecryptResult.err('解密失败，密码可能不正确');
  }
}

Uint8List _deriveKeys(String password, Uint8List salt, int iterations) {
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, iterations, 64));
  return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
}

Uint8List? _decodeB64(dynamic v) {
  if (v is! String) return null;
  try {
    return base64Decode(v);
  } catch (_) {
    return null;
  }
}

bool _constantTimeEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
