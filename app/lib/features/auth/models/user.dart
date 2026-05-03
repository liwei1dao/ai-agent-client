import 'dart:convert';

class User {
  const User({
    required this.id,
    required this.token,
    this.phone,
    this.email,
    this.name,
    this.avatar,
    this.countryCode,
    this.loginType = LoginType.phone,
  });

  final String id;
  final String token;
  final String? phone;
  final String? email;
  final String? name;
  final String? avatar;
  final String? countryCode;
  final LoginType loginType;

  Map<String, dynamic> toJson() => {
        'id': id,
        'token': token,
        'phone': phone,
        'email': email,
        'name': name,
        'avatar': avatar,
        'country_code': countryCode,
        'login_type': loginType.name,
      };

  factory User.fromJson(Map<String, dynamic> json) {
    // login_type 兼容三种格式：数字 code、name 字符串、缺省
    LoginType lt;
    final raw = json['login_type'];
    if (raw is num) {
      lt = LoginType.fromCode(raw.toInt());
    } else if (raw is String) {
      lt = LoginType.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => LoginType.phone,
      );
    } else {
      lt = LoginType.phone;
    }
    return User(
      id: json['id'] as String,
      token: json['token'] as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      name: json['name'] as String?,
      avatar: json['avatar'] as String?,
      countryCode: json['country_code'] as String?,
      loginType: lt,
    );
  }

  String encode() => jsonEncode(toJson());
  static User decode(String s) =>
      User.fromJson(jsonDecode(s) as Map<String, dynamic>);

  User copyWith({
    String? name,
    String? avatar,
  }) =>
      User(
        id: id,
        token: token,
        phone: phone,
        email: email,
        name: name ?? this.name,
        avatar: avatar ?? this.avatar,
        countryCode: countryCode,
        loginType: loginType,
      );
}

/// 登录类型 — 严格与服务端 `stype` 字段对齐：
/// 0=邮箱，1=手机号，3=Google，4=Facebook，5=Apple，6=游客
///
/// 注：2=微信 已暂时移除。
enum LoginType {
  email(0),
  phone(1),
  google(3),
  facebook(4),
  apple(5),
  guest(6);

  const LoginType(this.code);
  final int code;

  static LoginType fromCode(int? code) => switch (code) {
        0 => LoginType.email,
        1 => LoginType.phone,
        3 => LoginType.google,
        4 => LoginType.facebook,
        5 => LoginType.apple,
        6 => LoginType.guest,
        _ => LoginType.phone,
      };
}
