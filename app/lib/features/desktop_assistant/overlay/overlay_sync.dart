/// 主 app（AssistantScreen）↔ 悬浮窗桌宠之间的轻量**会话状态同步协议**。
///
/// 两者跑在不同 isolate，没有共享内存；唯一的实时跨 isolate 通道是
/// `FlutterOverlayWindow.shareData` / `overlayListener`（单向发往对端、对端
/// 的 listener 收到，不回声）。本协议把"谁在通话 / 处于什么状态 / 请求挂断"
/// 编码成字符串消息在这条通道上传递，从而让两边的「连接 / 挂断」状态保持同步。
///
/// 注意：形象 key 仍以**裸字符串**（无前缀，如 `robot` / `cutebot`）在同一条
/// 通道上传输；本协议的所有消息一律带前缀（`sess:` / `cmd:`）以便与形象 key
/// 区分，收到消息时**先判前缀**，不匹配再当作形象 key 处理。
library;

/// 会话粗粒度状态（够用于驱动「通话/挂断」按钮与桌宠光环，不传逐字文本）。
enum OverlaySessionState { idle, starting, active }

/// 协议消息的编解码。
class OverlaySyncMsg {
  static const _statePrefix = 'sess:';

  /// 命令：请求对端挂断它持有的会话。
  static const hangup = 'cmd:hangup';

  /// 命令：请求对端立即回播一次当前状态（新打开的一方用它补齐初始状态）。
  static const syncRequest = 'cmd:sync';

  /// 把状态编码为消息字符串。
  static String state(OverlaySessionState s) => '$_statePrefix${s.name}';

  /// 解析状态消息；非状态消息返回 null。
  static OverlaySessionState? parseState(String msg) {
    if (!msg.startsWith(_statePrefix)) return null;
    final name = msg.substring(_statePrefix.length);
    for (final s in OverlaySessionState.values) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// 是否是本协议的控制消息（用于和形象 key 区分）。
  static bool isProtocol(String msg) =>
      msg.startsWith(_statePrefix) ||
      msg == hangup ||
      msg == syncRequest;
}
