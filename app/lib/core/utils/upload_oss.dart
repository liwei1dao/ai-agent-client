import 'dart:async';
import 'dart:math';

import 'package:common_utils/common_utils.dart';
import 'package:dio/dio.dart';
import 'package:get_storage/get_storage.dart';
import 'package:tencentcloud_cos_sdk_plugin/cos.dart';
import 'package:tencentcloud_cos_sdk_plugin/cos_transfer_manger.dart';
import 'package:tencentcloud_cos_sdk_plugin/pigeon.dart';

import '../../data/models/appconfig.dart';

class UploadOss {
  static final UploadOss _shared = UploadOss._internal();
  factory UploadOss() => _shared;

  static String bucket = '';
  static String region = '';
  static String secretId = '';
  static String secretKey = '';
  static String userId = '';

  static CosTransferManger? _cosTransferManger;

  UploadOss._internal();

  static initOss() {
    // 兼容老路径：先尝试从 legacy `AppConfig` 拿（源工程行为），
    // 但 ai-agent-client 没初始化它，所以一般会直接走外部
    // [configure] 注入的值。
    try {
      bucket = AppConfig.env('COS_BUCKET_NAME') ?? bucket;
      region = AppConfig.env('COS_REGION') ?? region;
      secretId = AppConfig.env('COS_SECRET_ID') ?? secretId;
      secretKey = AppConfig.env('COS_SECRET_KEY') ?? secretKey;
    } catch (_) {
      // legacy AppConfig 未初始化，保留 configure() 已注入的值。
    }

    if (userId.isEmpty) {
      try {
        final Map? userInfo = GetStorage().read("user_info");
        if (userInfo != null) {
          userId = (userInfo['user']?['uid'] ?? userInfo['uid'] ?? '')
              .toString();
        }
      } catch (_) {}
    }
  }

  /// 由 ai-agent-client 的 auth/appconfig 流程在登录成功 + AppConfig 刷新
  /// 后调用，把腾讯云 COS 凭据 + 当前用户 uid 灌进来。设置完之后清掉
  /// `_cosTransferManger` 缓存以便下一次上传按新 region 重建。
  static void configure({
    required String bucket,
    required String region,
    required String secretId,
    required String secretKey,
    required String userId,
  }) {
    UploadOss.bucket = bucket;
    UploadOss.region = region;
    UploadOss.secretId = secretId;
    UploadOss.secretKey = secretKey;
    UploadOss.userId = userId;
    _cosTransferManger = null;
  }

  static Future<CosTransferManger> getTransferManger() async {
    if (_cosTransferManger == null) {
      await Cos().initWithPlainSecret(secretId, secretKey);
      if (Cos().hasTransferManger(region)) {
        _cosTransferManger = Cos().getTransferManger(region);
      } else {
        CosXmlServiceConfig serviceConfig = CosXmlServiceConfig(
          region: region,
          isHttps: true,
        );
        _cosTransferManger = await Cos().registerTransferManger(
            region, serviceConfig..region = region, TransferConfig());
      }
    }
    return _cosTransferManger!;
  }

  static Future<String> upload({
    String? filepath,
    String rootDir = 'file',
    String? fileType,
    Function? callback,
    ProgressCallback? onSendProgress,
  }) async {
    if (bucket.isEmpty ||
        region.isEmpty ||
        secretId.isEmpty ||
        secretKey.isEmpty ||
        userId.isEmpty) {
      initOss();
    }
    String pathName = userId.isNotEmpty
        ? 'User/$userId/$rootDir/${getDate()}/${getRandom(12)}.${fileType ?? getFileType(filepath!)}'
        : 'User/$rootDir/${getDate()}/${getRandom(12)}.${fileType ?? getFileType(filepath!)}';
    CosTransferManger cosTransferManger = await getTransferManger();
    final completer = Completer<String>();
    await cosTransferManger.upload(
      bucket,
      pathName,
      filePath: filepath,
      progressCallBack: onSendProgress,
      resultListener: ResultListener(
        (Map<String?, String?>? header, CosXmlResult? result) {
          final url = result?.accessUrl ??
              'https://$bucket.cos.$region.myqcloud.com/$pathName';
          completer.complete(url);
        },
        (clientException, serviceException) {
          completer.completeError(clientException ??
              serviceException ??
              Exception('Unknown error'));
        },
      ),
    );
    return completer.future;
  }

  static String getDate() {
    DateTime now = DateTime.now();
    return DateUtil.formatDate(now, format: 'yyyy/MM/dd');
  }

  static String getRandom(int num) {
    String alphabet = 'qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM';
    String left = '';
    for (var i = 0; i < num; i++) {
      left = left + alphabet[Random().nextInt(alphabet.length)];
    }
    return left;
  }

  static String getFileType(String path) {
    List<String> array = path.split('.');
    return array[array.length - 1];
  }
}
