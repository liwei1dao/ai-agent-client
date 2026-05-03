import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// 取设备指纹 (phonemac) 和型号 (phonemodel)，与源项目协议对齐：
///
/// - Android：使用 `androidInfo.id` 作为指纹，`androidInfo.model` 作为型号
/// - iOS：以 `utsname.machine + systemVersion` 做 md5 作为指纹（避免重装应用 UUID 改变），
///   `utsname.machine` 作为型号
class DeviceInfoService {
  DeviceInfoService._();
  static final DeviceInfoService instance = DeviceInfoService._();

  String _deviceId = '';
  String _deviceModel = '';
  bool _ready = false;

  String get deviceId => _deviceId;
  String get deviceModel => _deviceModel;

  Future<void> ensureReady() async {
    if (_ready) return;
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        _deviceId = info.id;
        _deviceModel = info.model;
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        final machine = info.utsname.machine.toLowerCase();
        final release = info.utsname.release;
        final fp = '$machine|$release';
        _deviceId = md5.convert(utf8.encode(fp)).toString();
        _deviceModel = machine;
      } else {
        _deviceId = 'desktop';
        _deviceModel = Platform.operatingSystem;
      }
    } catch (_) {
      _deviceId = 'unknown';
      _deviceModel = 'unknown';
    }
    _ready = true;
  }
}
