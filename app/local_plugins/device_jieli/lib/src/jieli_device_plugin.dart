import 'dart:async';

import 'package:device_plugin_interface/device_plugin_interface.dart';

import '../device_jieli.dart';

/// Jieli (杰里) `DevicePlugin` 适配。
///
/// - 复用底层 [Jielihome] 单例（保留原 dart API 给调试 UI 用）；
/// - 把 [JieliEvent] 翻译为 [DevicePluginEvent]；
/// - 当前不暴露麦克风上行 / 扬声器下行 (kotlin 侧尚未接 PCM/Opus 通道)，
///   能力集合先不声明 `micUplink` / `speakerDownlink`；
/// - 通话翻译 / 面对面翻译走 `invokeFeature('jieli.translation.start', ...)`，
///   设备端自行处理音频。
class JieliDevicePlugin implements DevicePlugin {
  JieliDevicePlugin();

  static const String kVendor = 'jieli';

  final Jielihome _home = Jielihome.instance;

  StreamSubscription<JieliEvent>? _sub;
  StreamController<DevicePluginEvent>? _ctrl;
  JieliDeviceSession? _activeSession;

  bool _initialized = false;
  bool _disposed = false;
  bool _scanning = false;

  @override
  String get vendorKey => kVendor;

  @override
  String get displayName => 'JieLi (杰理)';

  @override
  Set<DeviceCapability> get capabilities => const {
        DeviceCapability.scan,
        DeviceCapability.connect,
        DeviceCapability.bond,
        DeviceCapability.customCommand,
        DeviceCapability.onDeviceCallTranslation,
        DeviceCapability.onDeviceFaceToFaceTranslation,
        DeviceCapability.onDeviceRecordingTranslation,
      };

  @override
  DevicePluginConfigSchema get configSchema => const DevicePluginConfigSchema(
        fields: [
          DevicePluginConfigField(
            key: 'multiDevice',
            label: '多设备模式',
            defaultValue: false,
            helpText: '关闭以遵循 device_manager 单设备约束',
          ),
          DevicePluginConfigField(
            key: 'skipNoNameDev',
            label: '跳过无名设备',
            defaultValue: false,
          ),
          DevicePluginConfigField(
            key: 'enableLog',
            label: '启用 SDK 日志',
            defaultValue: false,
          ),
        ],
      );

  @override
  DeviceSession? get activeSession => _activeSession;

  @override
  Stream<DevicePluginEvent> get eventStream =>
      _ctrl?.stream ?? const Stream.empty();

  @override
  Future<void> initialize(DevicePluginConfig config) async {
    _checkAlive();
    if (_initialized) return;
    _ctrl ??= StreamController<DevicePluginEvent>.broadcast();
    await _home.initialize(
      multiDevice: (config.extra['multiDevice'] as bool?) ?? false,
      skipNoNameDev: (config.extra['skipNoNameDev'] as bool?) ?? false,
      enableLog: (config.extra['enableLog'] as bool?) ?? false,
    );
    _sub = _home.events.listen(_onJieliEvent);
    _initialized = true;
    _emit(const DevicePluginEvent(type: DevicePluginEventType.pluginReady));
  }

  @override
  Future<void> startScan({DeviceScanFilter? filter, Duration? timeout}) async {
    _requireInit();
    await _home.startScan(timeout: timeout ?? const Duration(seconds: 30));
    _scanning = true;
    _emit(const DevicePluginEvent(type: DevicePluginEventType.scanStarted));
  }

  @override
  Future<void> stopScan() async {
    if (!_initialized) return;
    await _home.stopScan();
    _scanning = false;
    _emit(const DevicePluginEvent(type: DevicePluginEventType.scanStopped));
  }

  @override
  Future<bool> isScanning() async {
    if (!_initialized) return false;
    return _scanning || await _home.isScanning();
  }

  @override
  Future<List<DiscoveredDevice>> bondedDevices() async {
    // Jielihome 当前未暴露已配对列表，留给后续 native 扩展。
    return const [];
  }

  @override
  Future<DeviceSession> connect(
    String deviceId, {
    DeviceConnectOptions? options,
  }) async {
    _requireInit();
    final extra = options?.extra ?? const {};
    final jl = JieliDevice(
      name: (extra['name'] as String?) ?? '',
      address: deviceId,
      edrAddr: extra['edrAddr'] as String?,
      deviceType: extra['deviceType'] as int?,
      connectWay: extra['connectWay'] as int?,
    );
    await _home.connect(jl);

    final session = JieliDeviceSession(
      home: _home,
      deviceId: deviceId,
      vendor: kVendor,
      capabilities: capabilities,
      initialName: jl.name,
      onClosed: () {
        if (identical(_activeSession, _activeSessionRef())) {
          _activeSession = null;
        }
      },
    );
    _activeSession = session;
    return session.waitReady(timeout: options?.timeout ?? const Duration(seconds: 15));
  }

  JieliDeviceSession? _activeSessionRef() => _activeSession;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _sub?.cancel();
    _sub = null;
    final s = _activeSession;
    _activeSession = null;
    if (s != null) {
      try {
        await s.disconnect();
      } catch (_) {}
    }
    _emit(const DevicePluginEvent(type: DevicePluginEventType.pluginDisposed));
    await _ctrl?.close();
    _ctrl = null;
    _initialized = false;
  }

  // -------- 内部 --------

  void _checkAlive() {
    if (_disposed) throw StateError('JieliDevicePlugin already disposed');
  }

  void _requireInit() {
    _checkAlive();
    if (!_initialized) {
      throw DeviceException(DeviceErrorCode.pluginNotInitialized);
    }
  }

  void _emit(DevicePluginEvent e) {
    final c = _ctrl;
    if (c == null || c.isClosed) return;
    c.add(e);
  }

  void _onJieliEvent(JieliEvent raw) {
    if (raw is AdapterStatusEvent) {
      _emit(DevicePluginEvent(
        type: DevicePluginEventType.bluetoothStateChanged,
        bluetoothEnabled: raw.enabled,
      ));
      return;
    }
    if (raw is DeviceFoundEvent) {
      _emit(DevicePluginEvent(
        type: DevicePluginEventType.deviceDiscovered,
        discovered: DiscoveredDevice(
          id: raw.device.address,
          name: raw.device.name,
          rssi: raw.device.rssi,
          vendor: kVendor,
          metadata: {
            if (raw.device.edrAddr != null) 'edrAddr': raw.device.edrAddr,
            if (raw.device.deviceType != null) 'deviceType': raw.device.deviceType,
            if (raw.device.connectWay != null) 'connectWay': raw.device.connectWay,
          },
        ),
      ));
      return;
    }
    if (raw is BondStatusEvent) {
      _emit(DevicePluginEvent(
        type: DevicePluginEventType.bondStateChanged,
        deviceId: raw.address,
        bondState: _mapBondStatus(raw.status),
      ));
      return;
    }
    if (raw is ConnectionStateEvent) {
      _activeSession?.updateConnectionFromRaw(raw.state);
      return;
    }
    if (raw is RcspInitEvent) {
      _activeSession?.updateRcspInit(raw.success);
      return;
    }
    // 翻译相关事件 → 通过 session.eventStream 派发给 agent 层
    // V4.2 新 SDK：原 ModeChange / SessionStart / SessionStop / RawAudio 已合并；
    // 当前对外只暴露 TranslationAudio（PCM）/ Log / Result / Error。
    if (raw is TranslationAudioEvent ||
        raw is TranslationLogEvent ||
        raw is TranslationResultEvent ||
        raw is TranslationErrorEvent) {
      _activeSession?.dispatchTranslationEvent(raw);
      return;
    }
    if (raw is ScanStatusEvent) {
      _scanning = raw.started;
      _emit(DevicePluginEvent(
        type: raw.started
            ? DevicePluginEventType.scanStarted
            : DevicePluginEventType.scanStopped,
      ));
      return;
    }
    // 其它事件（UnknownJieliEvent 等）作为 customEvent 透传，业务层一般忽略。
    _emit(DevicePluginEvent(
      type: DevicePluginEventType.customEvent,
      customKey: 'jieli.raw',
      customPayload: const {},
    ));
  }

  String _mapBondStatus(int s) {
    // android.bluetooth.BluetoothDevice 常量：10=NONE 11=BONDING 12=BONDED
    return switch (s) {
      11 => 'bonding',
      12 => 'bonded',
      _ => 'none',
    };
  }
}

/// 注册到 [DeviceManager] 的描述符（业务层只需 `manager.registerVendor(jieliDescriptor)`）。
final DevicePluginDescriptor jieliDevicePluginDescriptor = DevicePluginDescriptor(
  vendorKey: JieliDevicePlugin.kVendor,
  displayName: 'JieLi (杰理)',
  factory: JieliDevicePlugin.new,
  declaredCapabilities: const {
    DeviceCapability.scan,
    DeviceCapability.connect,
    DeviceCapability.customCommand,
    DeviceCapability.onDeviceCallTranslation,
    DeviceCapability.onDeviceFaceToFaceTranslation,
    DeviceCapability.onDeviceRecordingTranslation,
  },
);
