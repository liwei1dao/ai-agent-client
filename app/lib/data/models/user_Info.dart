import 'package:get_storage/get_storage.dart';
import 'package:get/get.dart';
import '../../../core/utils/logger.dart';

class User {
  // 单例实例
  static User? _instance;

  /// 全局刷新信号（当用户信息更新时 +1，用于驱动UI重建）
  static final RxInt refreshTick = 0.obs;

  /// 安全地检查用户是否已经登录（即单例是否已初始化）
  static bool isLoggedIn() {
    return _instance != null;
  }

  // 单例访问器（增加空安全保护）
  static User get instance {
    if (_instance == null) {
      throw Exception("User must be initialized first");
    }
    return _instance!;
  }

  // --- 新增 ---
  /// 清理所有与用户会话相关的数据
  static Future<void> clearUserSession() async {
    final GetStorage storage = GetStorage();
    // 1. 清理本地存储
    await storage.remove('logintoken');
    await storage.remove('user_info');
    // 2. 清理内存中的单例
    _instance = null;
    Logger.i("User", "用户会话数据已安全清理。");
  }

  // 最终属性（不可变）
  String name;
  String uid;
  String avatar;
  String language;
  String token;
  String mail;
  String phone;
  String phonemac;
  String password;
  int viplv = 0; //添加会员等级字段,0表示普通用户
  int vipexptime = 0; // 会员到期/剩余时间（秒/毫秒，按后端定义）
  int aichatintegral = 0; // ai聊天积分
  int aichattotalintegral = 0; // ai聊天总积分
  int tradeintegral = 0; // 翻译积分
  int tradetotalintegral = 0; // 翻译总积分
  int meetintegral = 0; // 会议积分
  int meettotalintegral = 0; // 会议总积分
  int gender = 0; // 性别: 0=未设置, 1=男, 2=女

  List<UserDevice> devices;

  // 私有构造函数
  User._({
    required this.name,
    required this.uid,
    required this.avatar,
    required this.language,
    required this.token,
    required this.mail,
    required this.phone,
    required this.phonemac,
    required this.password,
    required this.viplv,
    required this.vipexptime,
    required this.aichatintegral,
    required this.aichattotalintegral,
    required this.tradeintegral,
    required this.tradetotalintegral,
    required this.meetintegral,
    required this.meettotalintegral,
    required this.gender,
    required this.devices,
  });

  /// 空用户对象（用于未登录态占位）
  factory User.empty() {
    return User._(
      name: '',
      uid: '',
      avatar: '',
      language: 'en',
      token: '',
      mail: '',
      phone: '',
      phonemac: '',
      password: '',
      viplv: 0,
      vipexptime: 0,
      aichatintegral: 0,
      aichattotalintegral: 0,
      tradeintegral: 0,
      tradetotalintegral: 0,
      meetintegral: 0,
      meettotalintegral: 0,
      gender: 0,
      devices: const [],
    );
  }

  factory User.fromJson(Map<String, dynamic> json) {
    // 修复1：安全获取嵌套的 user 字段
    final userData = json['user'] as Map<String, dynamic>?; // 允许空值
    final devicesData = json['devices'] as List<dynamic>?; // 允许空值
    //final token = json['data']['token'] as String? ?? '';
    //final token = '';
    final u = User._(
      token: '',
      name: (userData?['name'] as String?) ?? '默认名称',
      uid: (userData?['uid'] as String?) ?? '',
      avatar: (userData?['avatar'] as String?) ?? '',
      language: (userData?['language'] as String?) ?? 'en',
      mail: (userData?['mail'] as String?) ?? '',
      phone: (userData?['phone'] as String?) ?? '',
      phonemac: (userData?['phonemac'] as String?) ?? '',
      password: (userData?['password'] as String?) ?? '',
      viplv: (userData?['viplv'] as int?) ?? 0, // 提供默认值
      vipexptime: (userData?['vipexptime'] as int?) ?? 0, // 提供默认值

      aichatintegral: (userData?['aichatintegral'] as int?) ?? 0,
      aichattotalintegral: (userData?['aichattotalintegral'] as int?) ?? 0,
      tradeintegral: (userData?['tradeintegral'] as int?) ?? 0,
      tradetotalintegral: (userData?['tradetotalintegral'] as int?) ?? 0,
      meetintegral: (userData?['meetintegral'] as int?) ?? 0,
      meettotalintegral: (userData?['meettotalintegral'] as int?) ?? 0,
      gender: (userData?['gender'] as int?) ?? 0,
      devices: devicesData
              ?.map((e) => UserDevice.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
    _instance = u;
    Logger.i("User",
        "初始化用户: uid=${u.uid}, name=${u.name}, gender=${u.gender}, viplv=${u.viplv}, vipexptime=${u.vipexptime}, ai聊天=${u.aichatintegral}/${u.aichattotalintegral}, 翻译=${u.tradeintegral}/${u.tradetotalintegral}, 会议=${u.meetintegral}/${u.meettotalintegral}");
    return u;
  }

  factory User.fronTokenJson(Map<String, dynamic> json) {
    // 修复1：安全获取嵌套的 user 字段
    final userData = json['user'] as Map<String, dynamic>?; // 允许空值
    final devicesData = json['devices'] as List<dynamic>?; // 允许空值
    Logger.d("User",
        "fronTokenJson: user=$userData, devices=${devicesData?.length ?? 0}");
    final u = User._(
      token: '',
      name: (userData?['name'] as String?) ?? '默认名称',
      uid: (userData?['uid'] as String?) ?? '',
      avatar: (userData?['avatar'] as String?) ?? '',
      language: (userData?['language'] as String?) ?? 'en',
      mail: (userData?['mail'] as String?) ?? '',
      phone: (userData?['phone'] as String?) ?? '',
      phonemac: (userData?['phonemac'] as String?) ?? '',
      password: (userData?['password'] as String?) ?? '',
      viplv: (userData?['viplv'] as int?) ?? 0, // 提供默认值
      vipexptime: (userData?['vipexptime'] as int?) ?? 0, // 提供默认值
      aichatintegral: (userData?['aichatintegral'] as int?) ?? 0,
      aichattotalintegral: (userData?['aichattotalintegral'] as int?) ?? 0,
      tradeintegral: (userData?['tradeintegral'] as int?) ?? 0,
      tradetotalintegral: (userData?['tradetotalintegral'] as int?) ?? 0,
      meetintegral: (userData?['meetintegral'] as int?) ?? 0,
      meettotalintegral: (userData?['meettotalintegral'] as int?) ?? 0,
      gender: (userData?['gender'] as int?) ?? 0,
      devices: devicesData != null
          ? (devicesData)
              .map((e) => UserDevice.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
    );
    _instance = u;
    Logger.i("User",
        "初始化用户(token): uid=${u.uid}, name=${u.name}, gender=${u.gender}, viplv=${u.viplv}, vipexptime=${u.vipexptime}, ai聊天=${u.aichatintegral}/${u.aichattotalintegral}, 翻译=${u.tradeintegral}/${u.tradetotalintegral}, 会议=${u.meetintegral}/${u.meettotalintegral}");
    return u;
  }

  updateUserInfo(Map<String, dynamic> user) {
    name = user['name'] as String? ?? name;
    uid = user['uid'] as String? ?? uid;
    avatar = user['avatar'] as String? ?? avatar;
    language = user['language'] as String? ?? language;
    token = user['token'] as String? ?? token;
    mail = user['mail'] as String? ?? mail;
    phone = user['phone'] as String? ?? phone;
    phonemac = user['phonemac'] as String? ?? phonemac;
    password = user['password'] as String? ?? password;
    viplv = user['viplv'] as int? ?? viplv;
    vipexptime = user['vipexptime'] as int? ?? vipexptime;
    aichatintegral = user['aichatintegral'] as int? ?? aichatintegral;
    aichattotalintegral =
        user['aichattotalintegral'] as int? ?? aichattotalintegral;
    tradeintegral = user['tradeintegral'] as int? ?? tradeintegral;
    tradetotalintegral =
        user['tradetotalintegral'] as int? ?? tradetotalintegral;
    meetintegral = user['meetintegral'] as int? ?? meetintegral;
    meettotalintegral = user['meettotalintegral'] as int? ?? meettotalintegral;
    gender = user['gender'] as int? ?? gender;

    // 触发全局刷新信号，驱动依赖UI重建
    refreshTick.value++;
  }

  // 完整的JSON序列化
  Map<String, dynamic> toJson() => {
        'user': {
          'name': name,
          'uid': uid,
          'avatar': avatar,
          'language': language,
          'token': token,
          'mail': mail,
          'phone': phone,
          'phonemac': phonemac,
          'password': password,
          'viplv': viplv,
          'vipexptime': vipexptime,
          'aichatintegral': aichatintegral,
          'aichattotalintegral': aichattotalintegral,
          'tradeintegral': tradeintegral,
          'tradetotalintegral': tradetotalintegral,
          'meetintegral': meetintegral,
          'meettotalintegral': meettotalintegral,
          'gender': gender,
          'devices': devices.map((device) => device.toJson()).toList(),
        },
      };

  // 添加设备
  addUserDevice(UserDevice device) {
    devices.add(device);
  }

  // 查找设备
  removeUserDevice(int id) {
    devices.removeWhere((device) => device.id == id);
  }
}

class UserDevice {
  int id;
  String uid;
  int productid;
  int devicetype;
  String devicename;
  String devicemac;
  String license;
  String cmei;
  UserDevice({
    required this.id,
    required this.uid,
    required this.productid,
    required this.devicetype,
    required this.devicename,
    required this.devicemac,
    required this.license,
    this.cmei = '',
  });

  factory UserDevice.fromJson(Map<String, dynamic> json) => UserDevice(
        id: json['id'] as int,
        uid: json['uid'] as String,
        productid: (json['productid'] as num).toInt(),
        devicetype: (json['devicetype'] as num).toInt(),
        devicename: json['devicename'] as String,
        devicemac: json['devicemac'] as String,
        license: json['license'] as String,
        cmei: json['cmei'] as String? ?? '',
      );

  toJson() => {
        'id': id,
        'uid': uid,
        'productid': productid,
        'devicetype': devicetype,
        'devicename': devicename,
        'devicemac': devicemac,
        'license': license,
        'cmei': cmei,
      };
}
