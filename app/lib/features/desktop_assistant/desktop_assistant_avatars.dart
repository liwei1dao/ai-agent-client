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
const String kDefaultDesktopAssistantAvatar = 'robot';

/// 按 key 取形象；找不到回退到第一个。
DesktopAssistantAvatar desktopAssistantAvatarByKey(String? key) {
  for (final a in kDesktopAssistantAvatars) {
    if (a.key == key) return a;
  }
  return kDesktopAssistantAvatars.first;
}
