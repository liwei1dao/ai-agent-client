import 'dart:async';

import 'package:device_plugin_interface/device_plugin_interface.dart';
import 'package:flutter/services.dart';

export 'package:device_plugin_interface/device_plugin_interface.dart';

/// # device_manager（Flutter facade）
///
/// 设备管理在本项目里走「native-driven」架构。核心规则只有三条，所有改动都
/// 必须遵守：
///
/// 1. **数据/状态归属于 native**。设备名称、mac、电量、固件、连接态、
///    capabilities 等"显示数据"的真相都在
///    `com.aiagent.device_manager.DefaultNativeDeviceManager` 里，由具体
///    厂商插件（如 `device_jieli` 的 `JieliNativeDeviceSession`）维护，
///    device_manager native 把它聚合成一份完整 `sessionSnapshot` 推上来。
///    Dart 侧只做镜像，**绝不**根据事件字段做状态机推导（参见
///    `DeviceSnapshot` 设计；详见 `lib/core/services/device_service.dart`）。
///
/// 2. **通信 vs 显示分离**。
///    - 显示路径（snapshot）：`activeSession.state` / `activeSession.info` /
///      `activeSession.capabilities` 都从 `sessionSnapshot` 整体覆盖来，业务
///      读 UI 状态请走 [DeviceSnapshot]，**不要**订阅 `session.eventStream`
///      自己拼字段。
///    - 通信路径（events / commands）：method channel 上的 [connect] /
///      [disconnect] / [DeviceSession.invokeFeature] / [DeviceSession.refreshInfo]
///      等是「动作管道」；[agentTriggers] 是设备主动触发流（PTT / 翻译键 /
///      挂断）；session.eventStream 上保留的 `feature` / `error` / `raw` 等
///      是"瞬时通信事件"，跟 UI state 无关。
///
/// 3. **Flutter 不直接持有会话对象做状态读**。`DeviceSession` 句柄存在的
///    意义是给业务层（translate_server / agents / settings）调动作用，
///    *不应该* 读它的 `state` / `info` 来驱动 UI（用 [DeviceSnapshot] 代替）。
///    新增 vendor 时不需要写新的 Dart 实现 —— 在 native 侧
///    `NativeDevicePluginRegistry.register` 注册即可。
///
/// ## Channel 协议
///
/// - `device_manager/method` —— 动作入口
///   - 厂商：`listVendors` / `useVendor` / `clearVendor` / `activeVendor` /
///     `activeCapabilities`
///   - 扫描：`startScan` / `stopScan` / `bondedDevices` / `isBluetoothEnabled`
///   - 连接：`connect` / `disconnect` / `activeSession`
///   - Session 动作（路由到 active session）：`readBattery` / `readRssi` /
///     `refreshInfo` / `invokeFeature`
///
/// - `device_manager/events` —— 聚合事件（每个事件可能携带最新 `sessionSnapshot`）
///   - `manager_ready`
///   - `vendor_changed` / `bluetooth_state_changed` / `scan_started` /
///     `scan_stopped` / `device_discovered`
///   - `active_session_changed` / `session_event` / `snapshot_updated`
///   - `error`
///
/// - `device_manager/triggers` —— 设备本地按键 / 唤醒（PTT / 翻译键 / 挂断键）
///
/// ## 事件 vs Snapshot 的处理顺序
///
/// 同一变更可能产生多条事件 + 一份 snapshot：
/// - method channel 与 event channel 是两条独立流，到达顺序不保证，因此
///   [connect] 在 method future resolve 后会主动派一次本地 `snapshotUpdated`，
///   保证 provider 至少能读到最新引用；
/// - `_routeEvent` 收到任何带 `sessionSnapshot` 字段的事件都把
///   `_activeSession` 整体重置为最新快照，**不**根据 `connectionState` /
///   `deviceInfo` 等字段单独累加；
/// - `session.eventStream` 仍然把原始 session_event 转发给低层订阅者
///   （比如 _ConnectedTile 监听 `connection_state_changed` 做 spinner），但
///   这只是"瞬时通知"——业务真要 UI 状态请读 [DeviceSnapshot]。
///
/// ## 错误处理
///
/// 所有 method channel 调用统一把 `PlatformException` 转成 [DeviceException]，
/// 错误码沿用 native 的 `device.*` 命名空间（[DeviceErrorCode]）。错误事件
/// **不**关闭流，业务侧根据 code 决定是否提示 / 重试。
///
/// 进程级 native singleton 跨多次 Dart 启动复用，所以 [initialize] 会主动
/// 拉一次 `activeVendor` / `activeSession`，避免热重启 / 退出再进时 UI
/// 误以为没连过设备。
class MethodChannelDeviceManager implements DeviceManager {
  MethodChannelDeviceManager() {
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (raw) => _routeEvent(raw as Map),
      onError: (e, _) {
        if (!_eventCtrl.isClosed) {
          _eventCtrl.add(DeviceManagerEvent(
            type: DeviceManagerEventType.error,
            errorCode: 'device.event_channel_error',
            errorMessage: '$e',
          ));
        }
      },
    );
    _triggerSub = _triggerChannel.receiveBroadcastStream().listen(
      (raw) => _routeTrigger(raw as Map),
    );
  }

  static const _method = MethodChannel('device_manager/method');
  static const _eventChannel = EventChannel('device_manager/events');
  static const _triggerChannel = EventChannel('device_manager/triggers');
  static const _otaChannel = EventChannel('device_manager/ota');

  StreamSubscription<dynamic>? _eventSub;
  StreamSubscription<dynamic>? _triggerSub;

  final _eventCtrl = StreamController<DeviceManagerEvent>.broadcast();
  final _triggerCtrl = StreamController<DeviceAgentTrigger>.broadcast();

  /// 本地 vendor 注册表（仅 UI 层做下拉时使用——真正的 vendor 工厂在 native）。
  /// 调用 [registerVendor] 只是把 descriptor 缓存到这里，native 不需要。
  final Map<String, DevicePluginDescriptor> _vendors = {};

  String? _activeVendor;
  Set<DeviceCapability> _activeCapabilities = const {};
  _MethodChannelSession? _activeSession;
  bool _disposed = false;
  bool _initialized = false;

  // ─── DeviceManager 接口 ────────────────────────────────────────────────

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
  Set<DeviceCapability> get activeCapabilities => _activeCapabilities;

  @override
  Future<void> useVendor(String vendorKey, DevicePluginConfig config) async {
    _checkAlive();
    try {
      await _method.invokeMethod('useVendor', {
        'vendor': vendorKey,
        'config': {
          'appKey': config.appKey,
          'appSecret': config.appSecret,
          'extra': config.extra,
        },
      });
      _activeVendor = vendorKey;
      _activeCapabilities = _vendors[vendorKey]?.declaredCapabilities ?? {};
      // useVendor 在 native 侧若同 vendor 是 no-op，已有 session 仍存活；
      // 这里把它拉回 Dart 缓存，否则 facade 重建后看不到 active session。
      await _hydrateFromNative();
    } on PlatformException catch (e) {
      throw DeviceException(
        e.code.startsWith('device.') ? e.code : DeviceErrorCode.notSupported,
        e.message ?? '$e',
      );
    }
  }

  @override
  Future<void> clearVendor() async {
    _checkAlive();
    try {
      await _method.invokeMethod('clearVendor');
    } on PlatformException catch (e) {
      throw DeviceException(
        e.code.startsWith('device.') ? e.code : DeviceErrorCode.notSupported,
        e.message ?? '$e',
      );
    }
    // native 在 clearVendor 内部会派发 active_session_changed(null) + vendor_changed，
    // _routeEvent 会负责清 _activeSession；这里只把 vendor 缓存归零。
    _activeVendor = null;
    _activeCapabilities = const {};
  }

  @override
  Future<void> startScan({
    DeviceScanFilter? filter,
    Duration? timeout,
  }) async {
    _checkAlive();
    try {
      await _method.invokeMethod('startScan', {
        if (filter != null)
          'filter': {
            if (filter.namePrefix != null) 'namePrefix': filter.namePrefix,
            if (filter.serviceUuids != null)
              'serviceUuids': filter.serviceUuids,
            if (filter.vendor != null) 'vendor': filter.vendor,
            if (filter.minRssi != null) 'minRssi': filter.minRssi,
          },
        if (timeout != null) 'timeoutMs': timeout.inMilliseconds,
      });
    } on PlatformException catch (e) {
      throw DeviceException(
        e.code.startsWith('device.') ? e.code : DeviceErrorCode.notSupported,
        e.message,
      );
    }
  }

  @override
  Future<void> stopScan() async {
    if (_disposed) return;
    try {
      await _method.invokeMethod('stopScan');
    } on PlatformException catch (_) {/* best effort */}
  }

  @override
  Future<bool> isBluetoothEnabled() async {
    if (_disposed) return false;
    try {
      return await _method.invokeMethod<bool>('isBluetoothEnabled') ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  @override
  Future<List<DiscoveredDevice>> bondedDevices() async {
    _checkAlive();
    try {
      final raw = await _method.invokeListMethod<Map>('bondedDevices')
          ?? const [];
      return raw.map(_parseDiscovered).toList(growable: false);
    } on PlatformException catch (e) {
      throw DeviceException(
        e.code.startsWith('device.') ? e.code : DeviceErrorCode.notSupported,
        e.message,
      );
    }
  }

  @override
  Future<DeviceSession> connect(
    String deviceId, {
    DeviceConnectOptions? options,
  }) async {
    _checkAlive();
    try {
      final raw = await _method.invokeMapMethod<String, dynamic>(
        'connect',
        {
          'deviceId': deviceId,
          if (options != null)
            'options': {
              'timeoutMs': options.timeout.inMilliseconds,
              'extra': options.extra,
            },
        },
      );
      if (raw == null) {
        throw DeviceException(DeviceErrorCode.connectFailed, 'native returned null');
      }
      // 直接以 method 返回的快照同步一次 _activeSession：保证 await 后立刻能
      // 拿到 ready 状态，不必等 EventChannel 推到（两条 channel 顺序不保证）。
      _applySnapshotFromNative(raw);
      // 同时主动派一次 snapshotUpdated 给 provider，让监听者立即重读
      // manager.activeSession（避免 EventChannel 端的 snapshot 还没到达）。
      if (!_eventCtrl.isClosed) {
        _eventCtrl.add(DeviceManagerEvent(
          type: DeviceManagerEventType.snapshotUpdated,
          sessionSnapshot: raw.cast<String, Object?>(),
        ));
      }
      return _activeSession!;
    } on PlatformException catch (e) {
      throw DeviceException(
        e.code.startsWith('device.')
            ? e.code
            : DeviceErrorCode.connectFailed,
        e.message,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    if (_disposed) return;
    try {
      await _method.invokeMethod('disconnect');
    } on PlatformException catch (_) {/* best effort */}
  }

  @override
  DeviceSession? get activeSession => _activeSession;

  @override
  Stream<DeviceAgentTrigger> get agentTriggers => _triggerCtrl.stream;

  @override
  Stream<DeviceManagerEvent> get eventStream => _eventCtrl.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    // 进程级 native singleton 可能跨多次 Dart 启动复用 —— 上次 useVendor / connect
    // 留下的 vendor 与 active session 在 native 侧仍然存活，本 facade 是新对象，
    // 必须主动从 native 拉一次状态，不然 UI 会以为没连过设备。
    await _hydrateFromNative();
  }

  /// 从 native 侧拉一次：activeVendor / activeCapabilities / activeSession。
  /// 失败一律静默——这只是缓存预热，不该让 facade 初始化失败。
  Future<void> _hydrateFromNative() async {
    if (_disposed) return;
    try {
      final vendor = await _method.invokeMethod<String>('activeVendor');
      _activeVendor = vendor;
      if (vendor != null) {
        final caps = await _method.invokeListMethod<String>('activeCapabilities')
            ?? const [];
        _activeCapabilities = caps
            .map(_MethodChannelSession._parseCapability)
            .whereType<DeviceCapability>()
            .toSet();
      } else {
        _activeCapabilities = const {};
      }

      final raw = await _method.invokeMapMethod<String, dynamic>('activeSession');
      // raw == null 时清缓存；非 null 时整体落地。
      _applySnapshotFromNative(raw);
      if (!_eventCtrl.isClosed) {
        _eventCtrl.add(DeviceManagerEvent(
          type: DeviceManagerEventType.snapshotUpdated,
          sessionSnapshot: raw?.cast<String, Object?>(),
        ));
      }
    } on PlatformException catch (_) {
      // best effort
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventSub?.cancel();
    await _triggerSub?.cancel();
    await _eventCtrl.close();
    await _triggerCtrl.close();
  }

  // ─── 内部 ───────────────────────────────────────────────────────────────

  void _checkAlive() {
    if (_disposed) throw StateError('DeviceManager already disposed');
  }

  void _routeEvent(Map raw) {
    if (_eventCtrl.isClosed) return;
    final type = raw['type'] as String? ?? '';
    final snapshotRaw = raw['sessionSnapshot'];
    // null 与"字段不存在"语义不同：null 表示当前没 active session（应清空缓存），
    // 缺字段表示该事件不携带快照（保留缓存）。
    final hasSnapshotField = raw.containsKey('sessionSnapshot');
    final snapshotMap = snapshotRaw is Map ? snapshotRaw : null;

    final evt = switch (type) {
      'manager_ready' =>
        const DeviceManagerEvent(type: DeviceManagerEventType.managerReady),
      'vendor_changed' => DeviceManagerEvent(
          type: DeviceManagerEventType.vendorChanged,
          vendorKey: raw['vendorKey'] as String?,
          sessionSnapshot: snapshotMap?.cast<String, Object?>(),
        ),
      'bluetooth_state_changed' => DeviceManagerEvent(
          type: DeviceManagerEventType.bluetoothStateChanged,
          bluetoothEnabled: raw['bluetoothEnabled'] as bool?,
        ),
      'scan_started' =>
        const DeviceManagerEvent(type: DeviceManagerEventType.scanStarted),
      'scan_stopped' =>
        const DeviceManagerEvent(type: DeviceManagerEventType.scanStopped),
      'device_discovered' => DeviceManagerEvent(
          type: DeviceManagerEventType.deviceDiscovered,
          discovered: raw['discovered'] is Map
              ? _parseDiscovered(raw['discovered'] as Map)
              : null,
        ),
      'active_session_changed' => DeviceManagerEvent(
          type: DeviceManagerEventType.activeSessionChanged,
          activeDeviceId: raw['activeDeviceId'] as String?,
          sessionSnapshot: snapshotMap?.cast<String, Object?>(),
        ),
      'session_event' => _parseSessionEvent(raw, snapshotMap),
      'snapshot_updated' => DeviceManagerEvent(
          type: DeviceManagerEventType.snapshotUpdated,
          sessionSnapshot: snapshotMap?.cast<String, Object?>(),
        ),
      'error' => DeviceManagerEvent(
          type: DeviceManagerEventType.error,
          errorCode: raw['errorCode'] as String?,
          errorMessage: raw['errorMessage'] as String?,
        ),
      _ => null,
    };

    // 单一真相：只要事件携带 sessionSnapshot 字段，就用它整体重置 _activeSession。
    // session_event 里不再单独拆 connectionState / deviceInfo —— state 已在
    // snapshot 里给到，避免 Dart 侧做任何 diff。
    if (hasSnapshotField) {
      _applySnapshotFromNative(snapshotMap);
    }

    // session_event 仍然把原始事件转发给底层订阅者（_ConnectedTile 等监听
    // connectionStateChanged 做 spinner / 错误信息），只是不再据此变更 _state。
    if (type == 'session_event' && _activeSession != null) {
      _activeSession!._forwardSessionEvent(raw['sessionEvent'] as Map?);
    }

    if (evt != null) _eventCtrl.add(evt);
  }

  /// 把 native 推上来的快照原样落到 _activeSession：null = 没 session（清缓存），
  /// 同 deviceId = 复用旧 session 引用并刷新字段，不同 deviceId = 标旧的为断开 + 新建。
  void _applySnapshotFromNative(Map? snapshotMap) {
    if (snapshotMap == null) {
      final old = _activeSession;
      if (old != null) {
        _activeSession = null;
        old._markDisconnected();
      }
      return;
    }
    final deviceId = (snapshotMap['deviceId'] as String?) ?? '';
    if (deviceId.isEmpty) return;
    var session = _activeSession;
    if (session == null || session.deviceId != deviceId) {
      session?._markDisconnected();
      session = _MethodChannelSession(deviceId: deviceId, manager: this);
      _activeSession = session;
    }
    session._applySnapshot(snapshotMap);
  }

  DeviceManagerEvent _parseSessionEvent(Map raw, Map? snapshotMap) {
    final s = raw['sessionEvent'] as Map?;
    final sEvt = s == null ? null : _parseSessionEventInner(s);
    return DeviceManagerEvent(
      type: DeviceManagerEventType.sessionEvent,
      sessionEvent: sEvt,
      sessionSnapshot: snapshotMap?.cast<String, Object?>(),
    );
  }

  DeviceSessionEvent? _parseSessionEventInner(Map s) {
    final t = (s['type'] as String?) ?? '';
    final type = switch (t) {
      'connection_state_changed' =>
        DeviceSessionEventType.connectionStateChanged,
      'device_info_updated' => DeviceSessionEventType.deviceInfoUpdated,
      'feature' => DeviceSessionEventType.feature,
      'rssi_updated' => DeviceSessionEventType.rssiUpdated,
      'raw' => DeviceSessionEventType.raw,
      'error' => DeviceSessionEventType.error,
      _ => null,
    };
    if (type == null) return null;
    return DeviceSessionEvent(
      type: type,
      deviceId: (s['deviceId'] as String?) ?? '',
      connectionState: _parseConnectionState(s['connectionState'] as String?),
      deviceInfo: s['deviceInfo'] is Map
          ? _parseDeviceInfo(s['deviceInfo'] as Map)
          : null,
      feature: s['feature'] is Map
          ? _parseFeature(s['feature'] as Map)
          : null,
      rssi: (s['rssi'] as num?)?.toInt(),
      raw: (s['raw'] as Map?)?.cast<String, Object?>(),
      errorCode: s['errorCode'] as String?,
      errorMessage: s['errorMessage'] as String?,
    );
  }

  void _routeTrigger(Map raw) {
    if (_triggerCtrl.isClosed) return;
    final kindStr = raw['kind'] as String?;
    final kind = switch (kindStr) {
      'chat' => DeviceAgentTriggerKind.chat,
      'translate' => DeviceAgentTriggerKind.translate,
      'stop' => DeviceAgentTriggerKind.stop,
      _ => null,
    };
    if (kind == null) return;
    _triggerCtrl.add(DeviceAgentTrigger(
      deviceId: (raw['deviceId'] as String?) ?? '',
      kind: kind,
      payload: ((raw['payload'] as Map?) ?? const {})
          .cast<String, Object?>(),
    ));
  }

  // ─── helpers ────────────────────────────────────────────────────────────

  static DiscoveredDevice _parseDiscovered(Map m) => DiscoveredDevice(
        id: (m['id'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        rssi: (m['rssi'] as num?)?.toInt(),
        vendor: m['vendor'] as String?,
        metadata: ((m['metadata'] as Map?) ?? const {})
            .cast<String, Object?>(),
      );

  static DeviceInfo _parseDeviceInfo(Map m) => DeviceInfo(
        id: (m['id'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        vendor: (m['vendor'] as String?) ?? '',
        firmwareVersion: m['firmwareVersion'] as String?,
        hardwareVersion: m['hardwareVersion'] as String?,
        serialNumber: m['serialNumber'] as String?,
        manufacturer: m['manufacturer'] as String?,
        model: m['model'] as String?,
        batteryPercent: (m['batteryPercent'] as num?)?.toInt(),
        metadata: ((m['metadata'] as Map?) ?? const {})
            .cast<String, Object?>(),
      );

  static DeviceFeatureEvent _parseFeature(Map m) => DeviceFeatureEvent(
        key: (m['key'] as String?) ?? '',
        data: ((m['data'] as Map?) ?? const {}).cast<String, Object?>(),
      );

  /// 字段缺失时返回 null —— 这点很关键：session_event 里 device_info_updated /
  /// feature / rssi_updated 等都不带 connectionState 字段，旧实现会 fallback 到
  /// disconnected，把已 ready 的 session 错误地"打回"未连接，home / call_translate
  /// 等读 `session.state` 的页面就显示"未链接 / 未就绪"。
  static DeviceConnectionState? _parseConnectionState(String? s) =>
      switch (s) {
        null => null,
        'DISCONNECTED' => DeviceConnectionState.disconnected,
        'CONNECTING' => DeviceConnectionState.connecting,
        'LINK_CONNECTED' => DeviceConnectionState.linkConnected,
        'READY' => DeviceConnectionState.ready,
        'DISCONNECTING' => DeviceConnectionState.disconnecting,
        _ => DeviceConnectionState.disconnected,
      };
}

/// MethodChannel 视角的 [DeviceSession]。
///
/// 仅作为 native sessionSnapshot 在 Dart 侧的不可变镜像 + 动作转发器：
/// state / info / capabilities **只能**通过 [_applySnapshot] 整体覆盖，
/// 不允许从 session_event 的字段拼凑（避免 diff 漏字段把 ready 打回 disconnected）。
class _MethodChannelSession implements DeviceSession {
  _MethodChannelSession({
    required this.deviceId,
    required this.manager,
  });

  final MethodChannelDeviceManager manager;

  @override
  final String deviceId;

  String _vendor = '';
  DeviceInfo _info = const DeviceInfo(id: '', name: '', vendor: '');
  DeviceConnectionState _state = DeviceConnectionState.connecting;
  Set<DeviceCapability> _capabilities = const {};
  final _evtCtrl = StreamController<DeviceSessionEvent>.broadcast();
  bool _disposed = false;

  @override
  String get vendor => _vendor;

  @override
  DeviceInfo get info => _info;

  @override
  DeviceConnectionState get state => _state;

  @override
  Set<DeviceCapability> get capabilities => _capabilities;

  @override
  Stream<DeviceSessionEvent> get eventStream => _evtCtrl.stream;

  void _applySnapshot(Map raw) {
    _vendor = (raw['vendor'] as String?) ?? _vendor;
    final stateStr = raw['state'] as String?;
    final parsed =
        MethodChannelDeviceManager._parseConnectionState(stateStr);
    if (parsed != null) _state = parsed;
    if (raw['info'] is Map) {
      _info = MethodChannelDeviceManager._parseDeviceInfo(raw['info'] as Map);
    }
    final caps = (raw['capabilities'] as List?)?.cast<String>() ?? const [];
    _capabilities = caps
        .map(_parseCapability)
        .whereType<DeviceCapability>()
        .toSet();
  }

  /// 把 native 推上来的 session_event 原样转发给低层订阅者（_ConnectedTile
  /// 等监听 connectionStateChanged / feature 等做 UI 反馈）。**state / info
  /// 不在这里更新**——它们一律以 sessionSnapshot 落地的字段为准。
  void _forwardSessionEvent(Map? rawEvt) {
    if (_evtCtrl.isClosed || rawEvt == null) return;
    final evt = manager._parseSessionEventInner(rawEvt);
    if (evt == null) return;
    _evtCtrl.add(evt);
  }

  void _markDisconnected() {
    if (_disposed) return;
    _state = DeviceConnectionState.disconnected;
    if (!_evtCtrl.isClosed) {
      _evtCtrl.add(DeviceSessionEvent(
        type: DeviceSessionEventType.connectionStateChanged,
        deviceId: deviceId,
        connectionState: DeviceConnectionState.disconnected,
      ));
      _evtCtrl.close();
    }
    _disposeOtaPort();
    _disposed = true;
  }

  // ─── DeviceSession 接口 ────────────────────────────────────────────────

  @override
  Future<int> readRssi() async {
    try {
      final v = await MethodChannelDeviceManager._method
          .invokeMethod<int>('readRssi');
      return v ?? 0;
    } on PlatformException catch (e) {
      throw DeviceException(
        e.code.startsWith('device.') ? e.code : DeviceErrorCode.notSupported,
        e.message,
      );
    }
  }

  @override
  Future<int?> readBattery() async {
    try {
      return await MethodChannelDeviceManager._method
          .invokeMethod<int>('readBattery');
    } on PlatformException catch (e) {
      throw DeviceException(
        e.code.startsWith('device.') ? e.code : DeviceErrorCode.notSupported,
        e.message,
      );
    }
  }

  @override
  Future<DeviceInfo> refreshInfo() async {
    try {
      final raw = await MethodChannelDeviceManager._method
          .invokeMapMethod<String, dynamic>('refreshInfo');
      if (raw != null) {
        _info = MethodChannelDeviceManager._parseDeviceInfo(raw);
      }
      return _info;
    } on PlatformException catch (e) {
      throw DeviceException(
        e.code.startsWith('device.') ? e.code : DeviceErrorCode.notSupported,
        e.message,
      );
    }
  }

  @override
  Future<Map<String, Object?>> invokeFeature(
    String featureKey, [
    Map<String, Object?> args = const {},
  ]) async {
    try {
      final raw = await MethodChannelDeviceManager._method
          .invokeMapMethod<String, dynamic>('invokeFeature', {
        'key': featureKey,
        'args': _normalizeArgs(args),
      });
      return raw?.cast<String, Object?>() ?? const {};
    } on PlatformException catch (e) {
      throw DeviceException(
        e.code.startsWith('device.') ? e.code : DeviceErrorCode.notSupported,
        e.message,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    await manager.disconnect();
  }

  static Map<String, Object?> _normalizeArgs(Map<String, Object?> args) {
    // PlatformChannel 不接受 Uint8List 之外的二进制类型；这里做轻量校验。
    final out = <String, Object?>{};
    args.forEach((k, v) {
      if (v is List<int> && v is! Uint8List) {
        out[k] = Uint8List.fromList(v);
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  @override
  DeviceOtaPort? otaPort() {
    if (_disposed) return null;
    if (!_capabilities.contains(DeviceCapability.ota)) return null;
    return _otaPort ??= _MethodChannelOtaPort();
  }

  _MethodChannelOtaPort? _otaPort;

  void _disposeOtaPort() {
    _otaPort?._dispose();
    _otaPort = null;
  }

  static DeviceCapability? _parseCapability(String s) => switch (s) {
        'SCAN' => DeviceCapability.scan,
        'CONNECT' => DeviceCapability.connect,
        'BOND' => DeviceCapability.bond,
        'BATTERY' => DeviceCapability.battery,
        'RSSI' => DeviceCapability.rssi,
        'OTA' => DeviceCapability.ota,
        'EQ' => DeviceCapability.eq,
        'ANC' => DeviceCapability.anc,
        'KEY_MAPPING' => DeviceCapability.keyMapping,
        'WEAR_DETECTION' => DeviceCapability.wearDetection,
        'MIC_UPLINK' => DeviceCapability.micUplink,
        'SPEAKER_DOWNLINK' => DeviceCapability.speakerDownlink,
        'WAKE_WORD' => DeviceCapability.wakeWord,
        'ON_DEVICE_CALL_TRANSLATION' =>
          DeviceCapability.onDeviceCallTranslation,
        'ON_DEVICE_FACE_TO_FACE_TRANSLATION' =>
          DeviceCapability.onDeviceFaceToFaceTranslation,
        'ON_DEVICE_RECORDING_TRANSLATION' =>
          DeviceCapability.onDeviceRecordingTranslation,
        'CUSTOM_COMMAND' => DeviceCapability.customCommand,
        _ => null,
      };
}

/// MethodChannel 视角的 [DeviceOtaPort]。
///
/// - `start` / `cancel` 走 method channel；
/// - 进度走专属 [MethodChannelDeviceManager._otaChannel]，每次 listen 时由
///   native 重新绑定到当前 active session 的端口（session 切换 / 断开时上层
///   会 cancel 流，新 session 再订阅一次即可）；
/// - `isRunning` 走同步 method channel 查询，避免本地缓存与 native 不一致。
class _MethodChannelOtaPort implements DeviceOtaPort {
  _MethodChannelOtaPort() {
    _sub =
        MethodChannelDeviceManager._otaChannel.receiveBroadcastStream().listen(
      (raw) {
        if (raw is! Map) return;
        final p = _parse(raw);
        if (p != null && !_ctrl.isClosed) _ctrl.add(p);
      },
      onError: (_) {/* native 端 channel 错误不致命，丢一次进度而已 */},
    );
  }

  final _ctrl = StreamController<DeviceOtaProgress>.broadcast();
  StreamSubscription<dynamic>? _sub;
  bool _disposed = false;

  @override
  Stream<DeviceOtaProgress> get progressStream => _ctrl.stream;

  @override
  bool get isRunning {
    // 同步 getter 不能 await；保留一份本地标记，由 progress 流推动。
    return _localRunning;
  }

  bool _localRunning = false;

  @override
  Future<void> start(DeviceOtaRequest request) async {
    if (_disposed) {
      throw DeviceException(
          DeviceErrorCode.noActiveSession, 'session disposed');
    }
    try {
      _localRunning = true;
      await MethodChannelDeviceManager._method.invokeMethod('otaStart', {
        'request': _serializeRequest(request),
      });
    } on PlatformException catch (e) {
      _localRunning = false;
      throw DeviceException(
        e.code.startsWith('device.') ? e.code : DeviceErrorCode.featureFailed,
        e.message,
      );
    }
  }

  @override
  Future<void> cancel() async {
    if (_disposed) return;
    try {
      await MethodChannelDeviceManager._method.invokeMethod('otaCancel');
    } on PlatformException catch (_) {/* best effort */}
  }

  void _dispose() {
    if (_disposed) return;
    _disposed = true;
    _sub?.cancel();
    _sub = null;
    if (!_ctrl.isClosed) _ctrl.close();
  }

  // ─── helpers ─────────────────────────────────────────────────────────────

  Map<String, Object?> _serializeRequest(DeviceOtaRequest req) {
    final base = <String, Object?>{
      if (req.blockSize != null) 'blockSize': req.blockSize,
      if (req.timeout != null) 'timeoutMs': req.timeout!.inMilliseconds,
    };
    return switch (req) {
      DeviceOtaFileRequest(:final filePath) => {
          ...base,
          'kind': 'file',
          'filePath': filePath,
        },
      DeviceOtaBytesRequest(:final bytes) => {
          ...base,
          'kind': 'bytes',
          'bytes': bytes,
        },
      DeviceOtaUrlRequest(:final url, :final headers) => {
          ...base,
          'kind': 'url',
          'url': url,
          'headers': headers,
        },
      DeviceOtaVendorRequest(:final vendorKey, :final payload) => {
          ...base,
          'kind': 'vendor',
          'vendorKey': vendorKey,
          'payload': payload,
        },
    };
  }

  DeviceOtaProgress? _parse(Map raw) {
    final state = _parseState(raw['state'] as String?);
    if (state == null) return null;
    final p = DeviceOtaProgress(
      state: state,
      sentBytes: (raw['sentBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (raw['totalBytes'] as num?)?.toInt() ?? 0,
      percent: (raw['percent'] as num?)?.toInt() ?? -1,
      tsMs: (raw['tsMs'] as num?)?.toInt() ?? 0,
      errorCode: raw['errorCode'] as String?,
      errorMessage: raw['errorMessage'] as String?,
    );
    if (p.isTerminal) _localRunning = false;
    return p;
  }

  static DeviceOtaState? _parseState(String? s) => switch (s) {
        'IDLE' => DeviceOtaState.idle,
        'DOWNLOADING' => DeviceOtaState.downloading,
        'INQUIRING' => DeviceOtaState.inquiring,
        'NOTIFYING_SIZE' => DeviceOtaState.notifyingSize,
        'ENTERING' => DeviceOtaState.entering,
        'TRANSFERRING' => DeviceOtaState.transferring,
        'VERIFYING' => DeviceOtaState.verifying,
        'REBOOTING' => DeviceOtaState.rebooting,
        'DONE' => DeviceOtaState.done,
        'FAILED' => DeviceOtaState.failed,
        'CANCELLED' => DeviceOtaState.cancelled,
        _ => null,
      };
}
