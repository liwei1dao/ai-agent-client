import 'dart:async';

import 'package:device_plugin_interface/device_plugin_interface.dart';

/// 纯 Dart 的 [DeviceManager] 编排实现。
///
/// 与 `MethodChannelDeviceManager`（native-driven，Android 用）相对：本实现
/// 在 **Dart 侧** 编排厂商 [DevicePlugin]，用于 native 容器缺位的平台。
///
/// 当前用于 **iOS** —— `device_manager` 的 iOS 端只是个 stub
/// （`DeviceManagerPlugin.swift`，`isBluetoothEnabled` 写死返回 false、事件通道
/// 永不 emit），真正的杰理实现 `device_jieli` 走独立的 `device_jieli/*` 通道、
/// 由其 Dart `DevicePlugin` 适配器 `JieliDevicePlugin` 接管。本编排器把
/// `JieliDevicePlugin` 这类 [DevicePlugin] 桥接到通用 [DeviceManager] 契约上，
/// 让上层 `device_service.dart` 的各 provider 无需区分平台。
///
/// 编排规则对齐 Android `DefaultNativeDeviceManager`：
/// - 单 vendor / 单 active session；
/// - [useVendor] 原子切换：断开旧 session → dispose 旧 plugin → 创建并
///   initialize 新 plugin → 派发 `vendorChanged`；
/// - 厂商 [DevicePluginEvent] 与会话 [DeviceSessionEvent] 聚合成
///   [DeviceManagerEvent] 对外派发，类型语义与 native 容器一致。
class DefaultDeviceManager implements DeviceManager {
  final Map<String, DevicePluginDescriptor> _vendors = {};
  final _eventCtrl = StreamController<DeviceManagerEvent>.broadcast();
  final _triggerCtrl = StreamController<DeviceAgentTrigger>.broadcast();

  DevicePlugin? _plugin;
  String? _activeVendor;
  StreamSubscription<DevicePluginEvent>? _pluginSub;

  DeviceSession? _session;
  StreamSubscription<DeviceSessionEvent>? _sessionSub;

  /// 蓝牙开关状态。[DeviceManager.isBluetoothEnabled] 约定 pure-Dart 默认
  /// 返回 true（避免设备页误报"蓝牙未开启"横幅），之后跟随厂商插件的
  /// `bluetoothStateChanged` 事件刷新为真实状态。
  bool _btEnabled = true;

  bool _switching = false;
  bool _disposed = false;

  // ─── 厂商管理 ─────────────────────────────────────────────────────────────

  @override
  Map<String, DevicePluginDescriptor> get registeredVendors =>
      Map.unmodifiable(_vendors);

  @override
  void registerVendor(
    DevicePluginDescriptor descriptor, {
    bool replace = false,
  }) {
    _checkAlive();
    if (_vendors.containsKey(descriptor.vendorKey) && !replace) {
      throw DeviceException(
        DeviceErrorCode.invalidArgument,
        'vendor "${descriptor.vendorKey}" already registered',
      );
    }
    _vendors[descriptor.vendorKey] = descriptor;
  }

  @override
  String? get activeVendor => _activeVendor;

  @override
  Set<DeviceCapability> get activeCapabilities =>
      _plugin?.capabilities ??
      _vendors[_activeVendor]?.declaredCapabilities ??
      const {};

  @override
  Future<void> useVendor(String vendorKey, DevicePluginConfig config) async {
    _checkAlive();
    if (_switching) {
      throw DeviceException(
          DeviceErrorCode.vendorSwitching, 'vendor switch in progress');
    }
    // 同 vendor 已激活 —— 幂等：保留现有 plugin / session。
    if (_activeVendor == vendorKey && _plugin != null) return;
    final descriptor = _vendors[vendorKey];
    if (descriptor == null) {
      throw DeviceException(
        DeviceErrorCode.notSupported,
        'vendor "$vendorKey" not registered',
      );
    }
    _switching = true;
    try {
      await _teardownPlugin();
      final plugin = descriptor.factory();
      // initialize 失败：plugin 未挂上，_activeVendor 保持旧值（null），
      // 异常向上抛由 _switchVendor 标记 error 状态。
      await plugin.initialize(config);
      _plugin = plugin;
      _activeVendor = vendorKey;
      _pluginSub = plugin.eventStream.listen(
        _onPluginEvent,
        onError: (Object e) => _emitError('device.event_error', '$e'),
      );
      _emit(DeviceManagerEvent(
        type: DeviceManagerEventType.vendorChanged,
        vendorKey: vendorKey,
      ));
    } finally {
      _switching = false;
    }
  }

  @override
  Future<void> clearVendor() async {
    _checkAlive();
    if (_plugin == null) {
      _activeVendor = null;
      return;
    }
    _switching = true;
    try {
      await _teardownPlugin();
      _activeVendor = null;
      // vendorChanged(null) 会让 deviceSnapshotProvider 重读 activeSession(=null)，
      // 不额外派 activeSessionChanged，避免触发自动重连守护。
      _emit(const DeviceManagerEvent(
        type: DeviceManagerEventType.vendorChanged,
        vendorKey: null,
      ));
    } finally {
      _switching = false;
    }
  }

  // ─── 扫描 / 连接 ──────────────────────────────────────────────────────────

  @override
  Future<void> startScan({DeviceScanFilter? filter, Duration? timeout}) async {
    _checkAlive();
    if (_switching) {
      throw DeviceException(
          DeviceErrorCode.vendorSwitching, 'vendor switch in progress');
    }
    await _requirePlugin().startScan(filter: filter, timeout: timeout);
  }

  @override
  Future<void> stopScan() async {
    if (_disposed) return;
    try {
      await _plugin?.stopScan();
    } catch (_) {/* best effort */}
  }

  @override
  Future<bool> isBluetoothEnabled() async => _btEnabled;

  @override
  Future<List<DiscoveredDevice>> bondedDevices() async {
    _checkAlive();
    return _requirePlugin().bondedDevices();
  }

  @override
  Future<DeviceSession> connect(
    String deviceId, {
    DeviceConnectOptions? options,
  }) async {
    _checkAlive();
    if (_switching) {
      throw DeviceException(
          DeviceErrorCode.vendorSwitching, 'vendor switch in progress');
    }
    final plugin = _requirePlugin();
    // 已有 session —— 静默断开旧的（先撤订阅，避免旧 session 的关闭事件被
    // 当成"远端断开"触发自动重连），再连新设备。
    final old = _session;
    if (old != null) {
      await _sessionSub?.cancel();
      _sessionSub = null;
      _session = null;
      try {
        await old.disconnect();
      } catch (_) {}
    }
    final session = await plugin.connect(deviceId, options: options);
    _session = session;
    _sessionSub = session.eventStream.listen(
      _onSessionEvent,
      onError: (Object e) => _emitError('device.session_error', '$e'),
      onDone: _onSessionDone,
    );
    _emit(DeviceManagerEvent(
      type: DeviceManagerEventType.activeSessionChanged,
      activeDeviceId: deviceId,
    ));
    _emit(const DeviceManagerEvent(
      type: DeviceManagerEventType.snapshotUpdated,
    ));
    return session;
  }

  @override
  Future<void> disconnect() async {
    if (_disposed) return;
    final session = _session;
    if (session == null) return;
    // session.disconnect() 会派 connectionStateChanged 事件并 close 事件流，
    // 收尾（清 _session + activeSessionChanged(null)）统一交给 _onSessionDone。
    try {
      await session.disconnect();
    } catch (_) {/* best effort */}
  }

  @override
  DeviceSession? get activeSession => _session;

  // ─── agent 协调 / 事件流 ──────────────────────────────────────────────────

  @override
  Stream<DeviceAgentTrigger> get agentTriggers => _triggerCtrl.stream;

  @override
  Stream<DeviceManagerEvent> get eventStream => _eventCtrl.stream;

  // ─── 生命周期 ─────────────────────────────────────────────────────────────

  @override
  Future<void> initialize() async {
    // pure-Dart 编排器无 native 单例可对账，无需预热。
  }

  @override
  Future<void> refresh() async {
    // 无 native SDK 可对账；扫描页的 refresh 在本编排器下退化为 no-op。
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _teardownPlugin();
    await _eventCtrl.close();
    await _triggerCtrl.close();
  }

  // ─── 内部 ─────────────────────────────────────────────────────────────────

  void _checkAlive() {
    if (_disposed) throw StateError('DeviceManager already disposed');
  }

  DevicePlugin _requirePlugin() {
    final p = _plugin;
    if (p == null) {
      throw DeviceException(
          DeviceErrorCode.notSupported, 'no active vendor');
    }
    return p;
  }

  /// 撤掉当前 plugin + session 的订阅并 dispose plugin。**不派任何事件** ——
  /// 调用方（useVendor / clearVendor）负责派 `vendorChanged`。
  Future<void> _teardownPlugin() async {
    await _sessionSub?.cancel();
    _sessionSub = null;
    _session = null;
    await _pluginSub?.cancel();
    _pluginSub = null;
    final old = _plugin;
    _plugin = null;
    if (old != null) {
      try {
        await old.stopScan();
      } catch (_) {}
      // plugin.dispose() 内部会断开其 active session。
      try {
        await old.dispose();
      } catch (_) {}
    }
  }

  void _onPluginEvent(DevicePluginEvent e) {
    switch (e.type) {
      case DevicePluginEventType.pluginReady:
        _emit(const DeviceManagerEvent(
            type: DeviceManagerEventType.managerReady));
      case DevicePluginEventType.bluetoothStateChanged:
        if (e.bluetoothEnabled != null) _btEnabled = e.bluetoothEnabled!;
        _emit(DeviceManagerEvent(
          type: DeviceManagerEventType.bluetoothStateChanged,
          bluetoothEnabled: e.bluetoothEnabled,
        ));
      case DevicePluginEventType.scanStarted:
        _emit(const DeviceManagerEvent(
            type: DeviceManagerEventType.scanStarted));
      case DevicePluginEventType.scanStopped:
        _emit(const DeviceManagerEvent(
            type: DeviceManagerEventType.scanStopped));
      case DevicePluginEventType.deviceDiscovered:
        _emit(DeviceManagerEvent(
          type: DeviceManagerEventType.deviceDiscovered,
          discovered: e.discovered,
        ));
      case DevicePluginEventType.wakeTriggered:
        final w = e.wake;
        if (w != null && !_triggerCtrl.isClosed) {
          _triggerCtrl.add(_toTrigger(w));
        }
      case DevicePluginEventType.error:
        _emit(DeviceManagerEvent(
          type: DeviceManagerEventType.error,
          errorCode: e.errorCode,
          errorMessage: e.errorMessage,
        ));
      // 连接态 / 设备信息走 session.eventStream；其余容器层不转发。
      case DevicePluginEventType.connectionStateChanged:
      case DevicePluginEventType.deviceInfoUpdated:
      case DevicePluginEventType.bondStateChanged:
      case DevicePluginEventType.customEvent:
      case DevicePluginEventType.pluginDisposed:
        break;
    }
  }

  void _onSessionEvent(DeviceSessionEvent e) {
    final session = _session;
    if (session == null) return;
    // 类型携带 sessionEvent 即可——上层 provider 收到 sessionEvent 就重读
    // manager.activeSession（live 对象，state/info 已是最新），不依赖快照 map。
    _emit(DeviceManagerEvent(
      type: DeviceManagerEventType.sessionEvent,
      sessionEvent: e,
    ));
  }

  void _onSessionDone() {
    _sessionSub = null;
    if (_session == null) return;
    _session = null;
    // 会话事件流关闭 = 设备断开。派 activeSessionChanged(null)：UI 重读快照、
    // 自动重连守护据此决定是否重连（用户主动断开时守护已被 markUserInitiated 抑制）。
    _emit(const DeviceManagerEvent(
      type: DeviceManagerEventType.activeSessionChanged,
      activeDeviceId: null,
    ));
  }

  DeviceAgentTrigger _toTrigger(DeviceWakeEvent w) {
    final kind = switch (w.reason) {
      WakeReason.ptt || WakeReason.voiceWake => DeviceAgentTriggerKind.chat,
      WakeReason.translateKey => DeviceAgentTriggerKind.translate,
      WakeReason.hangup => DeviceAgentTriggerKind.stop,
    };
    return DeviceAgentTrigger(
      deviceId: w.deviceId,
      kind: kind,
      payload: w.payload,
    );
  }

  void _emit(DeviceManagerEvent e) {
    if (!_eventCtrl.isClosed) _eventCtrl.add(e);
  }

  void _emitError(String code, String message) {
    _emit(DeviceManagerEvent(
      type: DeviceManagerEventType.error,
      errorCode: code,
      errorMessage: message,
    ));
  }
}
