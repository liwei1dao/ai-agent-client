import 'dart:async';

import 'package:device_manager/device_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config_service.dart';
import 'log_service.dart';

/// 已注册的设备厂商列表（设置 UI 渲染下拉项时直接消费）。
///
/// 列表里"敬请期待"的项保留 [factory] 为 null，UI 据此置灰。
class DeviceVendorOption {
  const DeviceVendorOption({
    required this.key,
    required this.label,
    required this.descriptor,
  });

  final String key;
  final String label;

  /// null 表示该厂商插件尚未集成，仅占位。
  final DevicePluginDescriptor? descriptor;

  /// 是否可选：descriptor 注册过、或 [kAvailableVendorKeys] 白名单命中。
  /// native-driven 架构下 descriptor 一直是 null，靠白名单决定是否可选。
  bool get available => descriptor != null || kAvailableVendorKeys.contains(key);
}

const List<DeviceVendorOption> kDeviceVendorOptions = [
  DeviceVendorOption(
    key: 'jieli',
    label: '杰理 (JieLi)',
    descriptor: null, // 在 _buildVendorOptions 内填入真实 descriptor
  ),
  DeviceVendorOption(
    key: 'bes',
    label: '恒玄 (BES)',
    descriptor: null,
  ),
  DeviceVendorOption(
    key: 'qcc',
    label: '高通 (QCC)',
    descriptor: null,
  ),
  DeviceVendorOption(
    key: 'bluetrum',
    label: '中科蓝讯 (Bluetrum)',
    descriptor: null,
  ),
];

/// 真实可选项。
///
/// 在 native-driven 架构下，vendor 工厂注册发生在 native 侧
/// （`JielihomePlugin.onAttachedToEngine` → `NativeDevicePluginRegistry.register`）；
/// Dart 这里的 [DevicePluginDescriptor] 现在不再被 facade 消费，UI 用
/// [DeviceVendorOption.available] 判断由 [kAvailableVendorKeys] 白名单决定。
List<DeviceVendorOption> buildVendorOptions() {
  return kDeviceVendorOptions;
}

/// 当前已在 native 注册（可用）的 vendor key 集合。
/// V1 简单硬编码；后续可改成从 `MethodChannelDeviceManager.listVendors()` 拉取。
const Set<String> kAvailableVendorKeys = {'jieli'};

/// 当前 vendor 切换状态：null = 闲置 / `pending` / `ready` / `error: <msg>`。
/// 任何 [_switchVendor] 调用都会更新它，UI 据此显示。
final deviceVendorStatusProvider = StateProvider<String?>((_) => null);

/// 全局 [DeviceManager] provider。
///
/// 走 [MethodChannelDeviceManager] —— 编排逻辑全部在 native
/// (`com.aiagent.device_manager.DefaultNativeDeviceManager`)。Vendor 工厂由各
/// 厂商插件（如 `device_jieli` 的 `JieliNativeDevicePlugin`）在 onAttachedToEngine
/// 时自注册到 native `NativeDevicePluginRegistry`，Dart 侧不再需要 registerVendor。
///
/// 启动时仅做两件事：
/// 1. 创建 facade + initialize；
/// 2. 跟随 `configServiceProvider.deviceVendor` 切换 vendor。
final deviceManagerProvider = Provider<DeviceManager>((ref) {
  final manager = MethodChannelDeviceManager();
  manager.initialize();

  ref.listen<AppConfig>(configServiceProvider, (prev, next) {
    final prevVendor = prev?.deviceVendor;
    final newVendor = next.deviceVendor;
    if (prevVendor == newVendor) return;
    _switchVendor(ref, manager, newVendor);
  }, fireImmediately: true);

  ref.onDispose(() => manager.dispose());
  return manager;
});

Future<void> _switchVendor(
    Ref ref, DeviceManager manager, String? vendor) async {
  void setStatus(String? s) {
    try {
      ref.read(deviceVendorStatusProvider.notifier).state = s;
    } catch (_) {}
  }

  try {
    if (vendor == null) {
      debugPrint('[device_service] vendor cleared → clearVendor');
      setStatus(null);
      // 必须 clearVendor，不能只 disconnect —— 后者只断 session，native 仍握着旧
      // plugin，下次 useVendor 才能切换；clearVendor 会一并 dispose plugin。
      await manager.clearVendor();
      return;
    }
    debugPrint('[device_service] switching vendor → $vendor');
    setStatus('pending');
    await manager.useVendor(vendor, const DevicePluginConfig());
    debugPrint('[device_service] useVendor($vendor) ok');
    setStatus('ready');
    LogService.instance.talker.info('[device] active vendor: $vendor');
  } catch (e, st) {
    final msg = e.toString();
    debugPrint('[device_service] useVendor($vendor) FAILED: $msg');
    debugPrint('$st');
    setStatus('error: $msg');
    LogService.instance.talker.handle(e, st, '[device] useVendor failed');
  }
}

/// 全局设备快照（透传 native 的 sessionSnapshot）。
///
/// **数据 / 状态归属于 native**——`DefaultNativeDeviceManager` 在任何字段（连接
/// 态、电量、固件、active session 切换）变化时都会推一份完整 snapshot，本对象
/// 是 Dart 侧的不可变镜像。Flutter 层所有页面 / 业务都从 [deviceSnapshotProvider]
/// 读，**不要**自己合并字段或做状态机推导。
class DeviceSnapshot {
  const DeviceSnapshot({
    required this.deviceId,
    required this.vendor,
    required this.state,
    required this.info,
    required this.capabilities,
  });

  /// 设备 mac / id（与扫描结果的 [DiscoveredDevice.id] 一致）。
  final String deviceId;
  final String vendor;
  final DeviceConnectionState state;
  final DeviceInfo info;
  final Set<DeviceCapability> capabilities;

  String get name => info.name;
  String get mac => deviceId;
  int? get battery => info.batteryPercent;
  String? get firmwareVersion => info.firmwareVersion;
  String? get hardwareVersion => info.hardwareVersion;
  String? get serialNumber => info.serialNumber;
  bool get isReady => state == DeviceConnectionState.ready;
  bool get isConnecting =>
      state == DeviceConnectionState.connecting ||
      state == DeviceConnectionState.linkConnected;
  bool get isDisconnected => state == DeviceConnectionState.disconnected;

  static DeviceSnapshot? fromSession(DeviceSession? session) {
    if (session == null) return null;
    return DeviceSnapshot(
      deviceId: session.deviceId,
      vendor: session.vendor,
      state: session.state,
      info: session.info,
      capabilities: session.capabilities,
    );
  }
}

/// 全局设备快照——所有上层业务（home / call_translate / chat / agents...）
/// 都从这里读。它只是 native sessionSnapshot 的透传镜像，本身不存任何业务
/// 逻辑；快照变了就重发一次。
final deviceSnapshotProvider = StreamProvider<DeviceSnapshot?>((ref) {
  final manager = ref.watch(deviceManagerProvider);
  final ctrl = StreamController<DeviceSnapshot?>();
  ctrl.add(DeviceSnapshot.fromSession(manager.activeSession));

  final sub = manager.eventStream.listen((evt) {
    // native 在以下事件里附带 sessionSnapshot：snapshotUpdated /
    // activeSessionChanged / sessionEvent / vendorChanged。任何一个到达都
    // 重发一次最新镜像，UI 只关心最近一次值。
    switch (evt.type) {
      case DeviceManagerEventType.snapshotUpdated:
      case DeviceManagerEventType.activeSessionChanged:
      case DeviceManagerEventType.sessionEvent:
      case DeviceManagerEventType.vendorChanged:
        ctrl.add(DeviceSnapshot.fromSession(manager.activeSession));
      default:
        break;
    }
  });

  ref.onDispose(() {
    sub.cancel();
    ctrl.close();
  });
  return ctrl.stream;
});

/// 当前 active session 的 reactive provider —— 业务侧需要 session 句柄
/// （invokeFeature / 音频通道 / disconnect）时用，仅做引用同步，不参与 UI 状态。
/// UI 一律读 [deviceSnapshotProvider]。
final activeDeviceSessionProvider = StreamProvider<DeviceSession?>((ref) {
  final manager = ref.watch(deviceManagerProvider);
  final ctrl = StreamController<DeviceSession?>();
  ctrl.add(manager.activeSession);

  final sub = manager.eventStream.listen((evt) {
    switch (evt.type) {
      case DeviceManagerEventType.snapshotUpdated:
      case DeviceManagerEventType.activeSessionChanged:
      case DeviceManagerEventType.vendorChanged:
        ctrl.add(manager.activeSession);
      default:
        break;
    }
  });

  ref.onDispose(() {
    sub.cancel();
    ctrl.close();
  });
  return ctrl.stream;
});

/// 已连接设备的实时 [DeviceInfo]——直接从 [deviceSnapshotProvider] 派生。
///
/// 订阅时主动调用一次 `session.refreshInfo()`（部分厂商 SDK 不主动推电量）。
final activeDeviceInfoProvider = StreamProvider<DeviceInfo?>((ref) {
  final snapshot = ref.watch(deviceSnapshotProvider).valueOrNull;
  if (snapshot == null) return Stream.value(null);
  // 顺便触发一次 refreshInfo（best-effort）。
  Future.microtask(() async {
    try {
      await ref.read(deviceManagerProvider).activeSession?.refreshInfo();
    } catch (e) {
      debugPrint('[device_service] refreshInfo failed: $e');
    }
  });
  return Stream.value(snapshot.info);
});

/// 实时扫描结果（设备扫描页订阅）。
final deviceScanResultsProvider =
    StreamProvider.autoDispose<List<DiscoveredDevice>>((ref) async* {
  final manager = ref.watch(deviceManagerProvider);
  final list = <DiscoveredDevice>[];
  final byId = <String, int>{};
  yield list;
  await for (final evt in manager.eventStream) {
    if (evt.type == DeviceManagerEventType.deviceDiscovered &&
        evt.discovered != null) {
      final d = evt.discovered!;
      final idx = byId[d.id];
      if (idx != null) {
        list[idx] = d;
      } else {
        byId[d.id] = list.length;
        list.add(d);
      }
      yield List.unmodifiable(list);
    } else if (evt.type == DeviceManagerEventType.scanStarted) {
      list.clear();
      byId.clear();
      yield List.unmodifiable(list);
    }
  }
});

/// 当前蓝牙开关状态。启动时主动查一次 native，之后跟随
/// `bluetoothStateChanged` 事件刷新。
final bluetoothEnabledProvider = StreamProvider<bool>((ref) async* {
  final manager = ref.watch(deviceManagerProvider);
  // 首次主动查询 —— 否则只能等系统事件触发。
  yield await manager.isBluetoothEnabled();
  await for (final evt in manager.eventStream) {
    if (evt.type == DeviceManagerEventType.bluetoothStateChanged &&
        evt.bluetoothEnabled != null) {
      yield evt.bluetoothEnabled!;
    }
  }
});

/// 自动重连守护：监听 active session 的远端断开事件，自动尝试重连
/// `config.lastDeviceId`。
///
/// 触发条件：
/// - vendor 已就绪、蓝牙开启；
/// - 当前没有 active session（包括：用户手动断开后再触发，由 [_userInitiated] 抑制）；
/// - 上次连接过 `lastDeviceId`。
///
/// 每次最多重试 3 次（指数退避 2s/4s/8s），成功或用户介入即重置。
final deviceAutoReconnectProvider = Provider<DeviceAutoReconnect>((ref) {
  final guard = DeviceAutoReconnect(ref);
  ref.onDispose(guard.dispose);
  return guard;
});

class DeviceAutoReconnect {
  DeviceAutoReconnect(this._ref) {
    _evtSub = _ref
        .read(deviceManagerProvider)
        .eventStream
        .listen(_onEvent, onError: (Object e) {
      debugPrint('[device_service] auto-reconnect listen error: $e');
    });
  }

  final Ref _ref;
  StreamSubscription<DeviceManagerEvent>? _evtSub;
  Timer? _retryTimer;
  int _retryCount = 0;
  bool _userInitiatedDisconnect = false;
  bool _disposed = false;

  /// UI 调用断开前先打这个标记，避免守护把它当远端断开。
  void markUserInitiatedDisconnect() {
    _userInitiatedDisconnect = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryCount = 0;
  }

  /// 用户主动 connect 成功后调一次，清空 retry 计数。
  void onConnectSuccess() {
    _userInitiatedDisconnect = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryCount = 0;
  }

  void _onEvent(DeviceManagerEvent evt) {
    if (_disposed) return;
    if (evt.type != DeviceManagerEventType.activeSessionChanged) return;
    if (evt.activeDeviceId != null) {
      // 重新连上了 —— reset。
      _retryCount = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
      return;
    }
    if (_userInitiatedDisconnect) {
      _userInitiatedDisconnect = false; // 一次性
      return;
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    if (_retryCount >= 3) {
      debugPrint('[device_service] auto-reconnect: gave up after 3 retries');
      return;
    }
    final delay = Duration(seconds: 2 << _retryCount); // 2s / 4s / 8s
    _retryCount++;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, _attemptReconnect);
  }

  Future<void> _attemptReconnect() async {
    if (_disposed) return;
    final cfg = _ref.read(configServiceProvider);
    final manager = _ref.read(deviceManagerProvider);
    final lastId = cfg.lastDeviceId;
    if (lastId == null || lastId.isEmpty) return;
    if (manager.activeVendor == null) return;
    final btOn = await manager.isBluetoothEnabled();
    if (!btOn) {
      debugPrint('[device_service] auto-reconnect: bluetooth off, abort');
      return;
    }
    if (manager.activeSession != null) return; // 已经又连上了
    debugPrint('[device_service] auto-reconnect attempt $_retryCount → $lastId');
    final connectWayOverride = cfg.deviceVendor == 'jieli'
        ? cfg.jieliConnectWay.protocolTypeValue
        : null;
    try {
      await manager.connect(
        lastId,
        options: DeviceConnectOptions(extra: {
          if (cfg.lastDeviceName != null) 'name': cfg.lastDeviceName,
          if (connectWayOverride != null) 'connectWay': connectWayOverride,
        }),
      );
      onConnectSuccess();
      LogService.instance.talker.info(
          '[device] auto-reconnect succeeded: $lastId (attempt $_retryCount)');
    } catch (e) {
      debugPrint('[device_service] auto-reconnect failed: $e');
      _scheduleReconnect();
    }
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _evtSub?.cancel();
    _evtSub = null;
  }
}
