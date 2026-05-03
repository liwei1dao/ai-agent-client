import 'dio_manager.dart';
import 'nw_method.dart';
import 'package:get/get.dart';

class Api {
  static String _normalizeTemplateLanguageTag(String value) {
    final normalized = value.trim().replaceAll('_', '-');
    if (normalized.isEmpty) {
      return 'en-US';
    }
    final parts = normalized.split('-').where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) {
      return 'en-US';
    }
    if (parts.length == 1) {
      return parts.first.toLowerCase();
    }
    return '${parts[0].toLowerCase()}-${parts[1].toUpperCase()}';
  }

  static String _currentTemplateLanguageParam() {
    final locale = Get.locale ?? Get.deviceLocale;
    final languageCode = locale?.languageCode.toLowerCase();
    if (languageCode == null || languageCode.isEmpty) {
      return 'en-US';
    }

    final countryCode = locale?.countryCode?.toUpperCase();
    if (countryCode != null && countryCode.isNotEmpty) {
      return '$languageCode-$countryCode';
    }

    switch (languageCode) {
      case 'zh':
        return 'zh-CN';
      case 'en':
        return 'en-US';
      case 'ja':
        return 'ja-JP';
      case 'ko':
        return 'ko-KR';
      case 'fr':
        return 'fr-FR';
      case 'de':
        return 'de-DE';
      case 'es':
        return 'es-ES';
      case 'it':
        return 'it-IT';
      case 'pt':
        return 'pt-BR';
      case 'ru':
        return 'ru-RU';
      case 'ar':
        return 'ar-SA';
      case 'hi':
        return 'hi-IN';
      default:
        return 'en-US';
    }
  }

  // 登录
  static login([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/user_sgin',
      params: params,
    );
  }

  // 获取验证码
  static getCode([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/user_verification',
      params: params,
    );
  }

  static tokenlogin([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/user_getinfo',
      params: params,
    );
  }

  // 获取阿里token
  static getAliToken([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/auth_alitoken',
      params: params,
    );
  }

  //更新用户设置
  static updateUserSetting([dynamic params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/user_setting',
      params: params,
    );
  }

  //注销账号
  static deleteUser([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/user_del',
      params: params,
    );
  }

  //用户反馈
  static feedback([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/user_feedback',
      params: params,
    );
  }

  //app配置
  static getappconfig([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/user_getappconfig',
      params: params,
    );
  }

  //app获取设备信息
  static getproduct([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/user_getproduct',
      params: params,
    );
  }

  //app获取设备信息
  static getproducts([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/user_getproducts',
      params: params,
    );
  }

  //举报AI内容
  static reportAiContent([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/user_reportaicontent',
      params: params,
    );
  }

  //获取音乐连接
  static getMusicUrl([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/music_getmusicurl',
      params: params,
    );
  }

  // 上传会议助手操作记录
  static putOperationRecord([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/echomeet_putrecords',
      params: params,
    );
  }

  // 获取会议助手数据
  static getOperationAllRecord([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/echomeet_getallrecords',
      params: params,
    );
  }

  // 轮询多条会议助手转写结果
  static getMultitermRecord([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/echomeet_getrecords',
      params: params,
    );
  }

  //获取渠道包信息
  static getChannelApp([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/user_getchannelapp',
      params: params,
    );
  }

  //获取所有渠道包信息
  static getChannelApps() {
    return DioManager().request(
      NWMethod.post,
      '/api/home/user_getchannelapps',
      //params: params,
    );
  }

  //绑定设备
  static binddevice([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/user_binddevice',
      params: params,
    );
  }

  //解绑定设备
  static unbinddevice([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/user_unbinddevice',
      params: params,
    );
  }

  // 获取验证码
  static getdevices([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/user_getdevices',
      params: params,
    );
  }

  //绑定设备
  static bindauthcode([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/user_bindauthcode',
      params: params,
    );
  }

  //创建支付订单
  static paycreateorder([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/pay_createorder',
      params: params,
    );
  }

  //询问订单
  static payverifyorder([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/pay_verifyorder',
      params: params,
    );
  }

  //获取模版数据
  static getEchomeetTemplates([dynamic params, String? language]) {
    final resolvedLanguage = _normalizeTemplateLanguageTag(
        language ?? _currentTemplateLanguageParam());
    final Map<String, dynamic> data = {};
    if (params is Map) {
      data.addAll(Map<String, dynamic>.from(params));
    }
    data['language'] = resolvedLanguage;
    return DioManager().request(
      NWMethod.post,
      '/api/home/echomeet_gettemplates',
      params: data,
    );
  }

  //添加模版数据
  static addEchomeetTemplates([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/echomeet_addtemplate',
      params: params,
    );
  }

  //修改模版数据
  static updateEchomeetTemplates([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/echomeet_updatetemplate',
      params: params,
    );
  }

  //删除模版数据
  static delEchomeetTemplates([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/echomeet_deltemplate',
      params: params,
    );
  }

  //获取商品列表
  static getGoods([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/pay_getgoodss',
      params: params,
    );
  }

  /// 资源使用/用量上报接口（`/api/home/user_usages`）
  ///
  /// 用途：上报翻译（Translation）和会议（Meet）的用量，服务端据此统计并回传最新余额/积分。
  ///
  /// 当前在 Dart 侧的使用场景：
  /// - 会议助手 ASR：`UsageStatsService._reportMeetingUsageToServer`
  /// - 翻译/同传 ASR：`UsageStatsService._reportAsrUsageToServer`
  ///
  /// 参数（`params`）结构：
  /// - `usagetype`：`int` 类型，使用场景类型（对应 `UsageType.toInt`），目前仅使用：
  ///   - `1`：翻译（Translation）
  ///   - `2`：会议（Meet）
  /// - `usages`：`Map<String, int>`，各项指标的键值对，例如：
  ///   - `MEETING_ASR_AUDIO_SECONDS`：会议识别音频时长（秒）
  ///   - `TRANSLATION_MODE_{mode}`：某翻译模式下累计有效识别秒数
  ///   - `TRANSLATION_ASR_LANGUAGE_{language}`：某语言/语言对下的调用次数
  ///
  /// 返回：
  /// - 经过 `AuthInterceptor` 处理后，本方法返回值即为服务端响应体中的 `data` 字段。
  /// - 若上报成功，`data['usages']` 为 `Map<String, int>`，内部各键的含义与积分/余额更新规则由服务端约定。
  ///
  /// 使用示例（Dart）：
  /// ```dart
  /// final params = {
  ///   'usagetype': UsageType.Meet.toInt,
  ///   'usages': {
  ///     'MEETING_ASR_AUDIO_SECONDS': 120,
  ///   }
  /// };
  /// final data = await Api.usagesResPoints(params);
  /// final usages = (data['usages'] as Map?)?.cast<String, dynamic>();
  /// ```
  static usagesResPoints([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/user_usages',
      params: params,
    );
  }

  static getwakeupvoices([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/user_getwakeupvoices',
      params: params,
    );
  }

  static addRecordEchomeet([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/echomeet_addrecord',
      params: params,
    );
  }

  static upRecordEchomeet([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/echomeet_uprecord',
      params: params,
    );
  }

  static startTaskEchomeet([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/echomeet_starttask',
      params: params,
    );
  }

  static refreshTaskEchomeet([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/echomeet_summary',
      params: params,
    );
  }

  static readRecordEchomeet([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/echomeet_readrecord',
      params: params,
    );
  }

  static delRecordEchomeet([params]) {
    return DioManager().request(
      NWMethod.post,
      '/api/home/echomeet_delrecords',
      params: params,
    );
  }

  static modifyRecordEchomeet([params]) {
    Map data = {
      'title': 'NULL',
      'address': 'NULL',
      'personnel': 'NULL',
      'translate': 'NULL',
      'summary': 'NULL',
    };
    data.addAll(params);
    return DioManager().request(
      NWMethod.post,
      '/api/home/echomeet_modifyrecords',
      params: data,
    );
  }
}
