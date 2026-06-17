/// 桌面悬浮助理的形象清单（纯 Dart 常量，主 app 与 overlay isolate 共用）。
///
/// overlay isolate 由独立 FlutterEngine 运行、读不到 SharedPreferences，所以
/// 当前选中的形象 key 由主 app 通过 `FlutterOverlayWindow.shareData` 传过去，
/// overlay 再用这里的清单把 key 解析成 Lottie 资源路径。新增形象只需把 .json
/// 丢进 `assets/lottie/` 并在此列表加一行。
class DesktopAssistantAvatar {
  const DesktopAssistantAvatar({
    required this.key,
    required this.asset,
    required this.label,
  });

  /// 持久化用的稳定标识。
  final String key;

  /// Lottie 资源路径（需在 pubspec assets 注册）。
  final String asset;

  /// 设置界面展示的名字。
  final String label;

  /// 资源是否为 Rive（.riv）；否则按 Lottie（.json）渲染。
  bool get isRive => asset.endsWith('.riv');
}

const List<DesktopAssistantAvatar> kDesktopAssistantAvatars = [
  // —— 2026-06 新增精选角色（来源与许可证见各行注释）——
  // 浅蓝微笑悬浮小机器人，3s 无缝待机循环。LottieFiles 免费动画
  // （Lottie Simple License，免费可商用、无需署名）。
  DesktopAssistantAvatar(
      key: 'cutebot', asset: 'assets/lottie/cute_bot.json', label: '波比'),
  // 圆滚滚小幽灵：漂浮+眨眼+吐舌。Google Noto Animated Emoji（CC BY 4.0，
  // 可商用，需在「关于」页署名 Google）。
  DesktopAssistantAvatar(
      key: 'ghost', asset: 'assets/lottie/ghost.json', label: '小幽'),
  // 橘色猫脸：眨眼+耳朵抖动，满画幅构图最贴圆形气泡。Google Noto Animated
  // Emoji（CC BY 4.0，同上需署名）。
  DesktopAssistantAvatar(
      key: 'cat', asset: 'assets/lottie/cat_face.json', label: '橘喵'),
  // 扁平卡通小鸡 1s 短循环舞蹈，动作幅度大、存在感强。airbnb/lottie-android
  // 样例资源（Apache-2.0）。
  DesktopAssistantAvatar(
      key: 'chicken', asset: 'assets/lottie/chicken.json', label: '跳跳鸡'),
  // 呆萌多眼小外星人：星星眼轮流闪烁，深紫主体与品牌色同色系。
  // LottieFiles/dotlottie-web 测试资源（MIT）。
  DesktopAssistantAvatar(
      key: 'alien', asset: 'assets/lottie/alien.json', label: '星宝'),
  // —— 旧形象 ——
  DesktopAssistantAvatar(
      key: 'robot', asset: 'assets/lottie/assistant.json', label: '小安'),
  DesktopAssistantAvatar(
      key: 'doudou', asset: 'assets/lottie/char_1.json', label: '豆豆'),
  DesktopAssistantAvatar(
      key: 'bobo', asset: 'assets/lottie/char_2.json', label: '波波'),
  DesktopAssistantAvatar(
      key: 'momo', asset: 'assets/lottie/char_3.json', label: 'Momo'),
  DesktopAssistantAvatar(
      key: 'mimi', asset: 'assets/lottie/char_4.json', label: '咪咪'),
  // Rive 角色（.riv，矢量 + 可互动）。当前是官方 example 角色，用于验证
  // Rive 在悬浮窗的渲染；二次元角色待替换为用户提供的 .riv。
  DesktopAssistantAvatar(
      key: 'coyote', asset: 'assets/rive/coyote.riv', label: '土狼·Rive'),
  DesktopAssistantAvatar(
      key: 'machine',
      asset: 'assets/rive/little_machine.riv',
      label: '小机·Rive'),
];

/// 默认形象 key。
const String kDefaultDesktopAssistantAvatar = 'cutebot';

/// 「不显示形象」哨兵 key。
///
/// 当前选中 agent 关闭了「显示虚拟形象」、或没有可用 agent 时，主 app 把这个 key
/// 经 shareData 推给 overlay，桌宠据此退回极简图标、不渲染角色动画。它不在
/// [kDesktopAssistantAvatars] 里，[desktopAssistantAvatarByKey] 解析它会回退到首个
/// 形象——所以渲染前必须先判 `key == kHiddenAvatarKey`，不要直接拿去解析。
const String kHiddenAvatarKey = '__none__';

/// 按 key 取形象；找不到回退到第一个。
DesktopAssistantAvatar desktopAssistantAvatarByKey(String? key) {
  for (final a in kDesktopAssistantAvatars) {
    if (a.key == key) return a;
  }
  return kDesktopAssistantAvatars.first;
}
