# 配置中心服务（configcenter）

给客户端提供**公开、免登录**的服务端配置读取接口。返回内容**整包 AES-256-GCM 加密**，
客户端用同一密钥解密。数据源是 console 后台配置的表（只读）。

## 接口

```
GET|POST  /config/api/getappconfig      # 公开，无需鉴权
GET       /config/api/health            # 健康检查
```

返回：

```json
{ "code": 0, "msg": "ok", "data": { "enc": "BASE64(nonce|ciphertext|tag)" } }
```

`enc` 解密后是完整配置 JSON：

```json
{
  "services": [ { "id","name","categories","description","fields":[{ "key","def_value","encrypted","sort" }] } ],
  "agents":   [ { "agent_id","name","type","description","avatar_url","supported_languages","variables","llm_svc_id","tts_svc_id" } ],
  "mcps":     [ { "id","name","transport","endpoint","tool_count" } ],
  "globals":  { "<key>": "<value>" }
}
```

只下发 `enable=true` 的服务/Agent/MCP。

## 加密方案（客户端按此解密）

- `key32 = SHA-256(密钥字符串)`，密钥来自环境变量 `CONFIG_SECRET_KEY`，服务端/客户端必须一致
- `nonce = 12 字节随机`
- `ciphertext = AES-256-GCM.Seal(plaintext)`（尾部含 16 字节 tag）
- `enc = Base64Std( nonce(12) || ciphertext )`

解密：`raw = base64decode(enc)` → `nonce = raw[:12]` → `ct = raw[12:]` → `plain = AES-256-GCM.Open(key32, nonce, ct)`。

### Dart 解密参照（pointycastle）

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart' as crypto;

Map<String, dynamic> decryptConfig(String enc, String secret) {
  final key = Uint8List.fromList(crypto.sha256.convert(utf8.encode(secret)).bytes);
  final raw = base64.decode(enc);
  final nonce = raw.sublist(0, 12);
  final ct = raw.sublist(12); // 含 GCM tag
  final gcm = GCMBlockCipher(AESEngine())
    ..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
  final out = gcm.process(Uint8List.fromList(ct));
  return jsonDecode(utf8.decode(out)) as Map<String, dynamic>;
}
```

> 算法正确性见 `modules/configcenter/crypto_test.go`（加密→解密 round-trip 通过，错误密钥认证失败）。

## 启动

```bash
export CONFIG_SECRET_KEY=<与客户端一致的密钥>
cd apps/services/services/configcenter
go run . -conf ./conf/configcenter.yaml      # 监听 :8091
```
