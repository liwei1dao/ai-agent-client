/// 商品类型
/// 0: 普通产品 normal
/// 1: 会员产品 member
import 'dart:convert';

// 使用量类型（与后端/Proto枚举对应）
enum UsageType {
  /// 未知使用量类型
  UsageNull, // 0
  /// 翻译
  Translation, // 1
  /// 会议
  Meet, // 2
  /// 智能体
  AI, // 3
  /// 智能体
  Vip; // 4
  /// Vip

  // 解析支持 int 或 string（大小写不敏感）
  static UsageType from(dynamic value) {
    if (value is int) {
      switch (value) {
        case 0:
          return UsageType.UsageNull;
        case 1:
          return UsageType.Translation;
        case 2:
          return UsageType.Meet;
        case 3:
          return UsageType.AI;
        case 4:
          return UsageType.Vip;
        default:
          return UsageType.UsageNull;
      }
    }
    if (value is String) {
      final v = int.tryParse(value.trim());
      if (v != null) return UsageType.from(v);
      switch (value.trim().toLowerCase()) {
        case 'usagenull':
        case 'null':
        case 'unknown':
          return UsageType.UsageNull;
        case 'translation':
          return UsageType.Translation;
        case 'meet':
        case 'meeting':
          return UsageType.Meet;
        case 'ai':
          return UsageType.AI;
        case 'vip':
          return UsageType.Vip;
        default:
          return UsageType.UsageNull;
      }
    }
    return UsageType.UsageNull;
  }

  int get toInt {
    switch (this) {
      case UsageType.UsageNull:
        return 0;
      case UsageType.Translation:
        return 1;
      case UsageType.Meet:
        return 2;
      case UsageType.AI:
        return 3;
      case UsageType.Vip:
        return 4;
    }
  }

  String get name {
    switch (this) {
      case UsageType.UsageNull:
        return 'UsageNull';
      case UsageType.Translation:
        return 'Translation';
      case UsageType.Meet:
        return 'Meet';
      case UsageType.AI:
        return 'AI';
      case UsageType.Vip:
        return 'Vip';
    }
  }
}

/// 支付商品模型，与后端 DBGoods 对应
/// - id: 产品id
/// - enable: 是否启用
/// - name: 产品名称
/// - desc: 产品描述
/// - price: 产品价格（建议单位：分）
/// - usagetype: 产品类型 0:普通产品 1:会员产品
/// - usagenum: 使用量（时长/次数/额度等）
class DBGoods {
  final String id;
  final bool enable;
  final String name;
  final String localname;
  final int price; // 建议单位：分
  final UsageType usagetype;
  final int usagenum;

  const DBGoods({
    required this.id,
    required this.enable,
    required this.name,
    required this.localname,
    required this.price,
    required this.usagetype,
    required this.usagenum,
  });

  /// 解析后端 JSON
  factory DBGoods.fromJson(Map<String, dynamic> json) {
    String _asString(dynamic v) {
      if (v == null) return '';
      return v is String ? v : v.toString();
    }

    bool _asBool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.trim().toLowerCase();
        return s == 'true' || s == '1';
      }
      return false;
    }

    int _asInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return DBGoods(
      id: _asString(json['id']),
      enable: _asBool(json['enable']),
      name: _asString(json['name']),
      localname: _asString(json['localname']),
      price: _asInt(json['price']),
      usagetype: UsageType.from(json['usagetype']),
      usagenum: _asInt(json['usagenum']),
    );
  }

  /// 编码为后端 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'enable': enable,
      'name': name,
      'localname': localname,
      'price': price,
      'usagetype': usagetype.toInt,
      'usagenum': usagenum,
    };
  }

  /// 列表解析
  static List<DBGoods> listFromJson(dynamic data) {
    if (data == null) return const [];
    if (data is List) {
      return data
          .map((e) => DBGoods.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    // 某些接口返回 { list: [...] } 或 { data: [...] }
    if (data is Map<String, dynamic>) {
      final list = data['list'] ?? data['data'] ?? data['items'];
      if (list is List) {
        return list
            .map((e) => DBGoods.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    return const [];
  }

  /// 价格换算：分 -> 元（仅当 price 单位为分时使用）
  double get priceYuan => price / 100.0;

  /// 用于支付创建订单的金额（分）
  int get payAmountCents => price;

  DBGoods copyWith({
    String? id,
    bool? enable,
    String? name,
    String? localname,
    int? price,
    UsageType? usagetype,
    int? usagenum,
  }) {
    return DBGoods(
      id: id ?? this.id,
      enable: enable ?? this.enable,
      name: name ?? this.name,
      localname: localname ?? this.localname,
      price: price ?? this.price,
      usagetype: usagetype ?? this.usagetype,
      usagenum: usagenum ?? this.usagenum,
    );
  }

  @override
  String toString() {
    return 'DBGoods(id: $id, enable: $enable, name: $name, price: $price, usagetype: ${usagetype.name}, usagenum: $usagenum)';
  }

  Map<String, dynamic>? get _localnameMap {
    if (localname.isEmpty) return null;
    try {
      final v = jsonDecode(localname);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> localInfo(String tag) {
    final m = _localnameMap;
    if (m == null) return const {};
    final key1 = tag;
    final key2 = tag.replaceAll('_', '-');
    final key3 = tag.replaceAll('-', '_');
    dynamic e = m[key1] ?? m[key2] ?? m[key3];
    if (e == null && m.isNotEmpty) e = m.values.first;
    return e is Map<String, dynamic> ? e as Map<String, dynamic> : const {};
  }
}
