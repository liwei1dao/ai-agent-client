import 'dart:async';
import 'dart:math';

import 'package:tencentcloud_cos_sdk_plugin/cos.dart';
import 'package:tencentcloud_cos_sdk_plugin/cos_transfer_manger.dart';
import 'package:tencentcloud_cos_sdk_plugin/pigeon.dart';

import '../../auth/services/app_config_service.dart';

typedef CosUploadProgress = void Function(int sent, int total);

/// Wrapper around `tencentcloud_cos_sdk_plugin`. Init from
/// [RemoteAppConfig.env] —— bucket / region / secretId / secretKey.
///
/// 上传后会回调 [onProgress] 流，最终 future 返回 access URL。
class CosUploader {
  CosUploader(this._appConfig);

  final AppConfigService _appConfig;

  bool _initialized = false;
  CosTransferManger? _transferManger;
  String _initializedRegion = '';
  String _initializedSecretId = '';

  bool get isReady => _appConfig.current.hasCos;

  Future<void> _ensureInitialized() async {
    final cfg = _appConfig.current;
    if (!cfg.hasCos) {
      throw const CosUploaderException(
          'cos_not_configured', 'COS 配置缺失，请重新登录或检查后端配置');
    }
    final keyChanged = _initialized &&
        (_initializedRegion != cfg.cosRegion ||
            _initializedSecretId != cfg.cosSecretId);
    if (_initialized && !keyChanged) return;

    await Cos().initWithPlainSecret(cfg.cosSecretId, cfg.cosSecretKey);
    if (Cos().hasTransferManger(cfg.cosRegion)) {
      _transferManger = Cos().getTransferManger(cfg.cosRegion);
    } else {
      final svcCfg = CosXmlServiceConfig(
        region: cfg.cosRegion,
        isHttps: true,
      );
      _transferManger = await Cos().registerTransferManger(
          cfg.cosRegion, svcCfg..region = cfg.cosRegion, TransferConfig());
    }
    _initialized = true;
    _initializedRegion = cfg.cosRegion;
    _initializedSecretId = cfg.cosSecretId;
  }

  /// 上传 [filePath] 到 COS，返回 access URL。
  ///
  /// [rootDir]: 桶内子目录，源项目用 `'LocalAudio'` / `'ExternalAudio'`，
  ///   通话翻译录音类用 `'CallAudio'`。
  /// [userId]: 服务端用户 id（用于 path 隔离），可空。
  /// [fileExtension]: 强制覆盖文件后缀；不传则按 [filePath] 自动取。
  Future<String> upload({
    required String filePath,
    required String rootDir,
    String? userId,
    String? fileExtension,
    CosUploadProgress? onProgress,
  }) async {
    await _ensureInitialized();
    final cfg = _appConfig.current;
    final ext = fileExtension ?? _extOf(filePath);
    final today = _yyyymmdd();
    final rand = _random(12);
    final pathName = userId != null && userId.isNotEmpty
        ? 'User/$userId/$rootDir/$today/$rand.$ext'
        : 'User/$rootDir/$today/$rand.$ext';

    final completer = Completer<String>();
    await _transferManger!.upload(
      cfg.cosBucket,
      pathName,
      filePath: filePath,
      progressCallBack: onProgress == null ? null : (sent, total) => onProgress(sent, total),
      resultListener: ResultListener(
        (header, result) {
          final url = result?.accessUrl ??
              'https://${cfg.cosBucket}.cos.${cfg.cosRegion}.myqcloud.com/$pathName';
          if (!completer.isCompleted) completer.complete(url);
        },
        (clientException, serviceException) {
          if (!completer.isCompleted) {
            completer.completeError(CosUploaderException(
              'upload_failed',
              clientException?.message ??
                  serviceException?.errorMessage ??
                  serviceException?.httpMsg ??
                  '上传失败',
            ));
          }
        },
      ),
    );
    return completer.future;
  }

  static String _extOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'bin';
    return path.substring(dot + 1).toLowerCase();
  }

  static String _yyyymmdd() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  static String _random(int n) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
  }
}

class CosUploaderException implements Exception {
  const CosUploaderException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'CosUploaderException($code, $message)';
}
