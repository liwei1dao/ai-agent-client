import 'dart:async';

import 'package:flutter/foundation.dart';

/// OTA 升级请求 —— 多态请求层级。
///
/// 业务层只构造其中一种子类；插件实现按 `runtimeType` 分派。
/// 厂商不支持的子类一律抛 `DeviceException(DeviceErrorCode.notSupported)`，
/// **禁止**静默退化（业务侧才有"是否回退到本地下载"的语义）。
@immutable
sealed class DeviceOtaRequest {
  const DeviceOtaRequest({this.blockSize, this.timeout});

  /// 单块大小。null = 走厂商默认（杰理 RCSP 当前 512）。
  final int? blockSize;

  /// 整段 OTA 的超时；null = 不限。
  final Duration? timeout;
}

/// 本地文件：app 自己下载好后放在沙盒里。
class DeviceOtaFileRequest extends DeviceOtaRequest {
  const DeviceOtaFileRequest({
    required this.filePath,
    super.blockSize,
    super.timeout,
  });

  final String filePath;
}

/// 内存字节流：固件已经在 dart 内存里。
///
/// 实现方可以选择直接喂给 SDK，也可以落盘后走文件路径——通过 method
/// channel 传字节较大固件不经济，建议 < 4MB 用本子类，更大的用文件请求。
class DeviceOtaBytesRequest extends DeviceOtaRequest {
  const DeviceOtaBytesRequest({
    required this.bytes,
    super.blockSize,
    super.timeout,
  });

  final Uint8List bytes;
}

/// 远程 URL：让 native 自己下载。
///
/// 厂商插件**不支持**时抛 `device.not_supported`，由调用方退回到
/// "app 端下载 → 用 [DeviceOtaFileRequest]" 路径。
class DeviceOtaUrlRequest extends DeviceOtaRequest {
  const DeviceOtaUrlRequest({
    required this.url,
    this.headers = const {},
    super.blockSize,
    super.timeout,
  });

  final String url;
  final Map<String, String> headers;
}

/// 厂商扩展逃生口（差分包 / 双备份 / fileFlag 等私有参数）。
///
/// 使用时业务层就明确放弃了"厂商无关"的承诺。`vendorKey` 必须等于当前 active
/// vendor，否则插件抛 `device.invalid_argument`。
class DeviceOtaVendorRequest extends DeviceOtaRequest {
  const DeviceOtaVendorRequest({
    required this.vendorKey,
    required this.payload,
    super.blockSize,
    super.timeout,
  });

  final String vendorKey;
  final Map<String, Object?> payload;
}

/// OTA 全局状态机。
///
/// ```
/// idle
///   → downloading        // [仅 Url 请求] 由容器层下载固件到本地，转 file 请求
///   → inquiring          // 询问设备能否升级
///   → notifyingSize      // 告知固件大小
///   → entering           // 设备进入升级模式
///   → transferring(*progress*)
///   → verifying
///   → rebooting
///   → done | failed | cancelled
/// ```
///
/// `failed` / `cancelled` 是终态，回到 idle 之前不应再派进度事件。
///
/// 注：`downloading` 由 `device_manager` 容器层产生（不在厂商插件内）——
/// Url 请求统一由容器下载到沙盒后转换为 file 请求再分派给 vendor port，
/// 厂商插件只看到 `inquiring` 起始的标准流程。
enum DeviceOtaState {
  idle,
  downloading,
  inquiring,
  notifyingSize,
  entering,
  transferring,
  verifying,
  rebooting,
  done,
  failed,
  cancelled,
}

/// OTA 进度事件。
///
/// - `transferring` 阶段进度上报频率应控制在 ≥ 5Hz / ≤ 20Hz；
/// - 非 transferring 阶段允许 sentBytes / totalBytes 不准确（可置 0），
///   UI 一律以 [state] 为主；
/// - `done` 时 [percent] = 100，`failed` / `cancelled` 时 [percent] 可能为 -1。
@immutable
class DeviceOtaProgress {
  const DeviceOtaProgress({
    required this.state,
    required this.sentBytes,
    required this.totalBytes,
    required this.percent,
    required this.tsMs,
    this.errorCode,
    this.errorMessage,
  });

  final DeviceOtaState state;
  final int sentBytes;
  final int totalBytes;

  /// 0..100；未知或非 transferring 阶段可为 -1。
  final int percent;

  /// 事件时间戳（毫秒，挂墙时间），调试用。
  final int tsMs;

  /// 终态时携带错误码（state ∈ {failed}）；其它阶段为 null。
  /// 命名空间 `device.<reason>`，参见 [DeviceErrorCode]。
  final String? errorCode;
  final String? errorMessage;

  bool get isTerminal =>
      state == DeviceOtaState.done ||
      state == DeviceOtaState.failed ||
      state == DeviceOtaState.cancelled;
}

/// OTA 端口（同 [DeviceCallTranslationPort] 的设计风格）。
///
/// 单设备 OTA 互斥：同时只能跑一个 [start]，重复 start 抛
/// `DeviceException('device.ota_busy')`。
///
/// 生命周期与铁律：
/// 1. `start` 之后 [progressStream] 必有终态（done/failed/cancelled），不得悬挂；
/// 2. 设备掉线（`disconnected*`）时端口须主动派 `failed` 收尾；
/// 3. `cancel` 后短时间内（≤ 5s）须收到 `cancelled`，超时强制收尾；
/// 4. **不**要求支持断点续传，但若实现了须在 `progress.metadata` 里给出。
abstract class DeviceOtaPort {
  /// 启动 OTA。已在跑时抛 `device.ota_busy`。
  Future<void> start(DeviceOtaRequest request);

  /// 取消当前 OTA；空跑时 no-op。
  Future<void> cancel();

  /// 当前是否在跑。
  bool get isRunning;

  /// 进度事件流（broadcast / multi-subscribe）。
  Stream<DeviceOtaProgress> get progressStream;
}
