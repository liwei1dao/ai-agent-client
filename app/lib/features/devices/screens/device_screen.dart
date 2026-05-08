import 'dart:async';

import 'package:device_manager/device_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/services/config_service.dart';
import '../../../core/services/device_service.dart';
import '../../../shared/themes/app_theme.dart';

class DeviceScreen extends ConsumerStatefulWidget {
  const DeviceScreen({super.key});

  @override
  ConsumerState<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends ConsumerState<DeviceScreen> {
  bool _scanning = false;
  String? _connectingId;

  Future<void> _toggleScan() async {
    final manager = ref.read(deviceManagerProvider);
    if (_scanning) {
      await manager.stopScan();
      if (mounted) setState(() => _scanning = false);
      return;
    }
    if (!await _ensurePermissions()) return;
    try {
      final cfg = ref.read(configServiceProvider);
      await manager.startScan(
        filter: DeviceScanFilter(
          nameList: cfg.scanNameList,
          serviceUuids: cfg.scanUuidList,
          skipUnnamed: cfg.scanSkipUnnamed,
        ),
        timeout: const Duration(seconds: 30),
      );
      if (mounted) setState(() => _scanning = true);
    } on DeviceException catch (e) {
      _toast('扫描失败：${e.code}');
    } catch (e) {
      _toast('扫描失败：$e');
    }
  }

  Future<void> _openScanFilter() async {
    final cfg = ref.read(configServiceProvider);
    final result = await showModalBottomSheet<_ScanFilterResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ScanFilterSheet(
        initialNameList: cfg.scanNameList,
        initialUuidList: cfg.scanUuidList,
        initialSkipUnnamed: cfg.scanSkipUnnamed,
      ),
    );
    if (result == null || !mounted) return;
    await ref.read(configServiceProvider.notifier).setScanFilter(
          nameList: result.nameList,
          uuidList: result.uuidList,
          skipUnnamed: result.skipUnnamed,
        );
    if (!mounted) return;
    _toast('已更新扫描过滤');
    // 正在扫描时让新的过滤立刻生效
    if (_scanning) {
      final manager = ref.read(deviceManagerProvider);
      await manager.stopScan();
      try {
        await manager.startScan(
          filter: DeviceScanFilter(
            nameList: result.nameList,
            serviceUuids: result.uuidList,
            skipUnnamed: result.skipUnnamed,
          ),
          timeout: const Duration(seconds: 30),
        );
      } on DeviceException catch (e) {
        if (mounted) _toast('扫描失败：${e.code}');
      }
    }
  }

  Future<bool> _ensurePermissions() async {
    final perms = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];
    final res = await perms.request();

    // 收集被拒/永久拒绝的权限
    final denied = <Permission>[];
    final permanentlyDenied = <Permission>[];
    res.forEach((p, s) {
      if (s.isPermanentlyDenied) {
        permanentlyDenied.add(p);
      } else if (!s.isGranted && !s.isLimited) {
        denied.add(p);
      }
    });

    if (denied.isEmpty && permanentlyDenied.isEmpty) return true;
    if (!mounted) return false;

    // 永久拒绝必须去系统设置；普通拒绝先弹一次重试 / 跳设置
    final goSettings = permanentlyDenied.isNotEmpty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要蓝牙 / 定位权限',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          goSettings
              ? '蓝牙扫描 / 连接 / 定位权限已被永久拒绝。'
                '请前往系统设置手动开启，否则无法搜索/连接耳机。'
              : '需要授予蓝牙扫描 / 连接 / 定位权限才能搜索耳机。'
                '\n\n点击"前往设置"打开系统授权页，或点击"重试"再次申请。',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          if (!goSettings)
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('重试'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary),
            child: const Text('前往设置'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await openAppSettings();
      // 用户从设置返回后再校验一次
      if (!mounted) return false;
      final after = await Future.wait(perms.map((p) => p.status));
      return after.every((s) => s.isGranted || s.isLimited);
    }
    if (ok == null) {
      // 重试：递归调一次（仅限非 permanentlyDenied 路径）
      return _ensurePermissions();
    }
    return false;
  }

  Future<void> _connect(DiscoveredDevice d) async {
    final manager = ref.read(deviceManagerProvider);
    setState(() => _connectingId = d.id);
    try {
      await manager.stopScan();
      final cfg = ref.read(configServiceProvider);
      final connectWayOverride = cfg.deviceVendor == 'jieli'
          ? cfg.jieliConnectWay.protocolTypeValue
          : null;
      await manager.connect(
        d.id,
        options: DeviceConnectOptions(extra: {
          'name': d.name,
          ...d.metadata,
          if (connectWayOverride != null) 'connectWay': connectWayOverride,
        }),
      );
      // 记下来用于自动重连，并通知守护重置计数。
      await ref
          .read(configServiceProvider.notifier)
          .setLastDevice(id: d.id, name: d.name);
      ref.read(deviceAutoReconnectProvider).onConnectSuccess();
      if (mounted) _toast('已连接 ${d.name}');
    } on DeviceException catch (e) {
      if (mounted) _toast('连接失败：${e.code}');
    } catch (e) {
      if (mounted) _toast('连接失败：$e');
    } finally {
      if (mounted) setState(() => _connectingId = null);
    }
  }

  Future<void> _disconnect() async {
    // 用户主动断开 —— 抑制自动重连。
    ref.read(deviceAutoReconnectProvider).markUserInitiatedDisconnect();
    await ref.read(deviceManagerProvider).disconnect();
    // 同时清掉 lastDevice，避免下次启动还在尝试自动连。
    await ref
        .read(configServiceProvider.notifier)
        .setLastDevice(id: null, name: null);
    if (mounted) _toast('已断开');
  }

  void _showDeviceInfo(DiscoveredDevice d) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _DeviceInfoDialog(device: d),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final config = ref.watch(configServiceProvider);
    final scanResults = ref.watch(deviceScanResultsProvider);
    final session = ref.watch(activeDeviceSessionProvider).valueOrNull;
    final deviceInfo = ref.watch(activeDeviceInfoProvider).valueOrNull;
    final btEnabled = ref.watch(bluetoothEnabledProvider).valueOrNull ?? true;
    final connectedId = session?.deviceId;

    final vendor = config.deviceVendor;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '设备管理',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (vendor != null) ...[
            _ScanFilterButton(
              nameCount: config.scanNameList.length,
              uuidCount: config.scanUuidList.length,
              onPressed: _openScanFilter,
            ),
            IconButton(
              icon: Icon(_scanning ? Icons.stop_circle_outlined : Icons.search,
                  color: AppTheme.primary),
              tooltip: _scanning ? '停止扫描' : '开始扫描',
              onPressed: _toggleScan,
            ),
          ],
        ],
      ),
      body: vendor == null
          ? _buildVendorEmpty(colors)
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                if (!btEnabled) _buildBluetoothOffBanner(colors),
                _buildVendorBanner(vendor, colors),
                if (session != null) ...[
                  const _SectionLabel('已连接'),
                  _ConnectedTile(
                    session: session,
                    info: deviceInfo,
                    onDisconnect: _disconnect,
                  ),
                ],
                const _SectionLabel('扫描结果'),
                scanResults.when(
                  data: (list) {
                    final visible = connectedId == null
                        ? list
                        : list.where((d) => d.id != connectedId).toList();
                    if (visible.isEmpty) {
                      return _ScanEmpty(scanning: _scanning);
                    }
                    return Column(
                      children: visible.map((d) {
                        final isConnecting = _connectingId == d.id;
                        return _ScanTile(
                          device: d,
                          connecting: isConnecting,
                          onTap: () => _showDeviceInfo(d),
                          onConnect: isConnecting ? null : () => _connect(d),
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('错误：$e',
                        style: const TextStyle(color: Color(0xFFEF4444))),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }

  Widget _buildBluetoothOffBanner(AppColors colors) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_disabled,
              color: Color(0xFFEF4444), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '蓝牙未开启，无法扫描或连接耳机。请在系统设置中打开蓝牙。',
              style: TextStyle(fontSize: 12, color: colors.text1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorEmpty(AppColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.headset_off_outlined, size: 48, color: colors.text2),
            const SizedBox(height: 12),
            Text('尚未选择设备厂商',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.text1)),
            const SizedBox(height: 6),
            Text('请前往「设置 → 设备」选择杰理 / 恒玄 / 高通 等厂商',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: colors.text2)),
          ],
        ),
      ),
    );
  }

  Widget _buildVendorBanner(String key, AppColors colors) {
    final label = kDeviceVendorOptions
        .firstWhere((o) => o.key == key,
            orElse: () => DeviceVendorOption(
                key: key, label: key, descriptor: null))
        .label;
    final status = ref.watch(deviceVendorStatusProvider);
    final isError = status != null && status.startsWith('error:');
    final isPending = status == 'pending';
    final bgColor = isError
        ? const Color(0xFFEF4444).withValues(alpha: 0.10)
        : AppTheme.primary.withValues(alpha: 0.08);
    final iconColor = isError ? const Color(0xFFEF4444) : AppTheme.primary;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          if (isPending)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              isError ? Icons.error_outline : Icons.bolt_outlined,
              color: iconColor,
              size: 20,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前厂商：$label',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.text1)),
                if (status != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    isPending
                        ? '正在初始化插件…'
                        : isError
                            ? '初始化失败：${status.substring(7)}'
                            : '插件已就绪',
                    style: TextStyle(
                      fontSize: 11,
                      color: isError
                          ? const Color(0xFFEF4444)
                          : colors.text2,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectedTile extends ConsumerStatefulWidget {
  const _ConnectedTile({
    required this.session,
    required this.info,
    required this.onDisconnect,
  });
  final DeviceSession session;
  final DeviceInfo? info;
  final VoidCallback onDisconnect;

  @override
  ConsumerState<_ConnectedTile> createState() => _ConnectedTileState();
}

class _ConnectedTileState extends ConsumerState<_ConnectedTile> {
  late DeviceConnectionState _state;
  StreamSubscription<DeviceSessionEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _state = widget.session.state;
    _sub = widget.session.eventStream.listen((evt) {
      if (!mounted) return;
      if (evt.type == DeviceSessionEventType.connectionStateChanged &&
          evt.connectionState != null) {
        setState(() => _state = evt.connectionState!);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _ConnectedTile old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      _sub?.cancel();
      _state = widget.session.state;
      _sub = widget.session.eventStream.listen((evt) {
        if (!mounted) return;
        if (evt.type == DeviceSessionEventType.connectionStateChanged &&
            evt.connectionState != null) {
          setState(() => _state = evt.connectionState!);
        }
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final session = widget.session;
    final info = widget.info;
    final name = (info?.name.isNotEmpty ?? false)
        ? info!.name
        : (session.info.name.isEmpty ? '设备' : session.info.name);
    final activeInfo = info ?? session.info;
    final batteryLeft = activeInfo.batteryLeft;
    final batteryRight = activeInfo.batteryRight;
    final batteryCase = activeInfo.batteryCase;
    final hasMulti = [batteryLeft, batteryRight, batteryCase]
            .where((e) => e != null)
            .length >
        1;
    final fw = info?.firmwareVersion ?? session.info.firmwareVersion;
    final (statusLabel, statusColor) = switch (_state) {
      DeviceConnectionState.connecting => ('正在连接…', AppTheme.primary),
      DeviceConnectionState.linkConnected => ('握手中…', AppTheme.primary),
      DeviceConnectionState.ready => ('已就绪', const Color(0xFF22C55E)),
      DeviceConnectionState.disconnecting =>
        ('正在断开…', const Color(0xFFF59E0B)),
      DeviceConnectionState.disconnected =>
        ('已断开', const Color(0xFFEF4444)),
    };
    final transitional = _state == DeviceConnectionState.connecting ||
        _state == DeviceConnectionState.linkConnected ||
        _state == DeviceConnectionState.disconnecting;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            transitional
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.headset_mic,
                    color: AppTheme.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.text1),
                  ),
                  const SizedBox(height: 2),
                  Text(session.deviceId,
                      style: TextStyle(fontSize: 11, color: colors.text2)),
                  const SizedBox(height: 4),
                  // Wrap 而非 Row：状态 chip / 电量 / FW 三段在窄屏（带升级+断开
                  // 两个按钮）时会 overflow，自动换行更稳。
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(statusLabel,
                            style: TextStyle(
                                fontSize: 10,
                                color: statusColor,
                                fontWeight: FontWeight.w600)),
                      ),
                      if (batteryLeft != null)
                        _BatteryChip(
                          percent: batteryLeft,
                          charging: activeInfo.chargingLeft,
                          // 单一电量设备（眼镜/手环）不展示位置标签
                          label: hasMulti ? 'L' : null,
                        ),
                      if (batteryRight != null)
                        _BatteryChip(
                          percent: batteryRight,
                          charging: activeInfo.chargingRight,
                          label: 'R',
                        ),
                      if (batteryCase != null)
                        _BatteryChip(
                          percent: batteryCase,
                          charging: activeInfo.chargingCase,
                          label: '仓',
                        ),
                      if (fw != null && fw.isNotEmpty)
                        Text('FW $fw',
                            style: TextStyle(
                                fontSize: 10, color: colors.text2)),
                    ],
                  ),
                ],
              ),
            ),
            // 按钮列竖排：横向放两个 TextButton 在窄屏会进一步挤压
            // 信息列；垂直 IconButton 既省横向空间，又让动作更醒目。
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_state == DeviceConnectionState.ready &&
                    session.capabilities.contains(DeviceCapability.ota))
                  IconButton(
                    onPressed: () => context.push('/devices/ota'),
                    tooltip: '固件升级',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.system_update,
                        size: 22, color: AppTheme.primary),
                  ),
                IconButton(
                  onPressed: widget.onDisconnect,
                  tooltip: '断开',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.link_off,
                      size: 22, color: Color(0xFFEF4444)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BatteryChip extends StatelessWidget {
  const _BatteryChip({
    required this.percent,
    this.charging = false,
    this.label,
  });
  final int percent;
  final bool charging;

  /// 多电量位时的位置标签（L / R / 仓）；单一电量设备传 null。
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final clamped = percent.clamp(0, 100);
    final IconData icon;
    final Color color;
    if (charging) {
      icon = Icons.battery_charging_full;
      color = const Color(0xFF22C55E);
    } else if (clamped <= 15) {
      icon = Icons.battery_alert;
      color = const Color(0xFFEF4444);
    } else if (clamped <= 40) {
      icon = Icons.battery_3_bar;
      color = const Color(0xFFF59E0B);
    } else if (clamped <= 80) {
      icon = Icons.battery_5_bar;
      color = colors.text2;
    } else {
      icon = Icons.battery_full;
      color = AppTheme.primary;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!,
              style: TextStyle(
                  fontSize: 10,
                  color: colors.text2,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 2),
        ],
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        Text('$clamped%',
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ScanTile extends StatelessWidget {
  const _ScanTile({
    required this.device,
    required this.connecting,
    required this.onTap,
    required this.onConnect,
  });
  final DiscoveredDevice device;
  final bool connecting;
  final VoidCallback? onTap;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: Icon(Icons.bluetooth_outlined,
            color: connecting ? colors.text2 : AppTheme.primary),
        title: Text(device.name.isEmpty ? '(未命名)' : device.name,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.text1)),
        subtitle: Text(
          [
            device.id,
            if (device.rssi != null) '${device.rssi} dBm',
          ].join(' · '),
          style: TextStyle(fontSize: 11, color: colors.text2),
        ),
        trailing: connecting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : FilledButton(
                onPressed: onConnect,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  minimumSize: const Size(0, 32),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                child: const Text('连接'),
              ),
        onTap: onTap,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 设备广播信息对话框（仿 BLE 调试助手样式）
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceInfoDialog extends StatelessWidget {
  const _DeviceInfoDialog({required this.device});
  final DiscoveredDevice device;

  /// 按 BLE 规范解析 AD Type 0x01 Flags 位，生成与 BLE 调试助手一致的描述。
  static String _flagsDesc(int flags) {
    final parts = <String>[];
    if (flags & 0x01 != 0) parts.add('LE Limited Discoverable Mode');
    if (flags & 0x02 != 0) parts.add('LE General Discoverable Mode');
    // bit 2: 0 = BR/EDR Supported；1 = BR/EDR Not Supported
    if (flags & 0x04 != 0) {
      parts.add('BR/EDR Not Supported');
    } else {
      parts.add('BR/EDR Supported');
    }
    if (flags & 0x08 != 0) parts.add('LE and BR/EDR Controller');
    if (flags & 0x10 != 0) parts.add('LE and BR/EDR host');
    return parts.join('; ');
  }

  /// 从 Flags 推断设备类型字符串。
  static String _deviceType(int flags) {
    final edrSupported = flags & 0x04 == 0;
    // bit 0/1 = LE discoverable；bit 3/4 = 同时支持 LE+EDR
    final leCapable = (flags & 0x03 != 0) || (flags & 0x18 != 0);
    if (edrSupported && leCapable) return 'BR/EDR/LE';
    if (leCapable) return 'LE Only';
    return 'BR/EDR';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final m = device.metadata;
    final rawAdv = m['rawAdv'] as String?;
    final advFlags = m['advFlags'] as int?;
    final serviceUuids = (m['serviceUuids'] as List?)?.cast<String>() ?? [];
    final companyId = m['manufacturerCompanyId'] as int?;
    final mfrData = m['manufacturerData'] as String?;
    final advRecords = (m['advRecords'] as List?)
            ?.whereType<Map>()
            .map((e) => e.cast<String, String>())
            .toList() ??
        [];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 标题栏 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
              child: Row(
                children: [
                  Text('广播包:',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.text1)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),
            // ── 滚动内容区 ──
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── 1. 原始广播数据包（始终置顶）──
                    if (rawAdv != null && rawAdv.isNotEmpty) ...[
                      Text('原始广播数据:',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.text1)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.primary, width: 1.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: SelectableText(
                          '0x$rawAdv',
                          style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: colors.text1,
                              height: 1.5),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // ── 2. 广播包明细表（Len | Type | Data）──
                    if (advRecords.isNotEmpty) ...[
                      Text('广播包解析:',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.text1)),
                      const SizedBox(height: 6),
                      _AdvTable(records: advRecords),
                      const SizedBox(height: 12),
                    ],

                    // ── 3. 解析摘要（有数据时显示，解析不到则不显示）──
                    if (advFlags != null) ...[
                      _AdvInfoLine(
                        label: 'Device type',
                        value: _deviceType(advFlags),
                        primary: true,
                      ),
                      _AdvInfoLine(
                        label: 'Advertising type',
                        value: 'Legacy',
                        primary: true,
                      ),
                      _AdvInfoLine(
                        label: 'Flags',
                        value: _flagsDesc(advFlags),
                        primary: true,
                      ),
                    ],

                    if (companyId != null) ...[
                      const SizedBox(height: 6),
                      Text('Manufacturer data:',
                          style: TextStyle(fontSize: 12, color: colors.text1)),
                      const SizedBox(height: 2),
                      Text(
                        'Company:Reserved ID'
                        '<0x${companyId.toRadixString(16).toUpperCase().padLeft(4, '0')}>',
                        style: TextStyle(fontSize: 12, color: colors.text1),
                      ),
                      if (mfrData != null && mfrData.isNotEmpty)
                        SelectableText(
                          '0x$mfrData',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.primary,
                              fontFamily: 'monospace',
                              height: 1.5),
                        ),
                    ],

                    if (serviceUuids.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Service UUIDs:',
                          style: TextStyle(fontSize: 12, color: colors.text1)),
                      const SizedBox(height: 2),
                      ...serviceUuids.map((u) => SelectableText(
                            u,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.primary,
                                fontFamily: 'monospace'),
                          )),
                    ],

                    // ── 4. 基本设备信息 ──
                    const SizedBox(height: 8),
                    _AdvInfoLine(
                      label: 'Device name',
                      value: device.name.isEmpty ? '(未命名)' : device.name,
                    ),
                    _AdvInfoLine(label: 'MAC address', value: device.id),
                    if (device.rssi != null)
                      _AdvInfoLine(label: 'RSSI', value: '${device.rssi} dBm'),

                    const SizedBox(height: 10),
                    RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 11, color: colors.text2),
                        children: const [
                          TextSpan(text: 'Further information see: '),
                          TextSpan(
                            text:
                                'https://www.bluetooth.com/specifications/assigned-numbers/generic-access-profile/',
                            style: TextStyle(
                                color: AppTheme.primary,
                                decoration: TextDecoration.underline),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            // ── OK 按钮 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('OK',
                      style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Label: Value" 内联行，与 BLE 调试助手截图格式一致。
class _AdvInfoLine extends StatelessWidget {
  const _AdvInfoLine({
    required this.label,
    required this.value,
    this.primary = false,
  });
  final String label;
  final String value;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 12, color: colors.text1, height: 1.5),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: TextStyle(
                color: primary ? AppTheme.primary : colors.text1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Len / Type / Data 广播包明细表。
/// Data 列使用 [Text] + softWrap 确保长 hex 字符串完整换行显示。
class _AdvTable extends StatelessWidget {
  const _AdvTable({required this.records});
  final List<Map<String, String>> records;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    const colStyle =
        TextStyle(fontSize: 11, color: AppTheme.primary, fontFamily: 'monospace');
    final headerStyle = TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: colors.text1);
    const divider = Color(0xFFE5E7EB);

    Widget cell(String text, {TextStyle? style, bool header = false}) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Text(
            text,
            style: style ?? (header ? headerStyle : colStyle),
            softWrap: true,
          ),
        );

    // 使用 Column + Row 代替 Table，避免 Table 对 Text wrap 的限制
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: divider, width: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 表头
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 40, child: cell('Len', header: true)),
                Container(width: 0.5, color: divider),
                SizedBox(width: 56, child: cell('Type', header: true)),
                Container(width: 0.5, color: divider),
                Expanded(child: cell('Data', header: true)),
              ],
            ),
          ),
          Container(height: 0.5, color: divider),
          // 数据行
          for (int i = 0; i < records.length; i++) ...[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 40, child: cell(records[i]['len'] ?? '')),
                  Container(width: 0.5, color: divider),
                  SizedBox(width: 56, child: cell(records[i]['type'] ?? '')),
                  Container(width: 0.5, color: divider),
                  Expanded(child: cell(records[i]['data'] ?? '')),
                ],
              ),
            ),
            if (i < records.length - 1)
              Container(height: 0.5, color: divider),
          ],
        ],
      ),
    );
  }
}

class _ScanEmpty extends StatelessWidget {
  const _ScanEmpty({required this.scanning});
  final bool scanning;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          scanning ? '扫描中…' : '点击右上角图标开始扫描',
          style:
              TextStyle(fontSize: 13, color: context.appColors.text2),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);
  final String title;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(title,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.appColors.text2)),
    );
  }
}

class _ScanFilterResult {
  const _ScanFilterResult({
    required this.nameList,
    required this.uuidList,
    required this.skipUnnamed,
  });
  final List<String> nameList;
  final List<String> uuidList;
  final bool skipUnnamed;
}

class _ScanFilterButton extends StatelessWidget {
  const _ScanFilterButton({
    required this.nameCount,
    required this.uuidCount,
    required this.onPressed,
  });
  final int nameCount;
  final int uuidCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final active = nameCount + uuidCount > 0;
    return IconButton(
      tooltip: active ? '扫描过滤（${nameCount + uuidCount}）' : '扫描过滤',
      onPressed: onPressed,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            active ? Icons.filter_alt : Icons.filter_alt_outlined,
            color: AppTheme.primary,
          ),
          if (active)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${nameCount + uuidCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScanFilterSheet extends StatefulWidget {
  const _ScanFilterSheet({
    required this.initialNameList,
    required this.initialUuidList,
    required this.initialSkipUnnamed,
  });
  final List<String> initialNameList;
  final List<String> initialUuidList;
  final bool initialSkipUnnamed;

  @override
  State<_ScanFilterSheet> createState() => _ScanFilterSheetState();
}

class _ScanFilterSheetState extends State<_ScanFilterSheet> {
  late final TextEditingController _nameCtl;
  late final TextEditingController _uuidCtl;
  late bool _skipUnnamed;

  @override
  void initState() {
    super.initState();
    _nameCtl = TextEditingController(text: widget.initialNameList.join('\n'));
    _uuidCtl = TextEditingController(text: widget.initialUuidList.join('\n'));
    _skipUnnamed = widget.initialSkipUnnamed;
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _uuidCtl.dispose();
    super.dispose();
  }

  List<String> _parse(String raw) => raw
      .split(RegExp(r'[\n,，;；\s]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  void _save() {
    Navigator.of(context).pop(_ScanFilterResult(
      nameList: _parse(_nameCtl.text),
      uuidList: _parse(_uuidCtl.text),
      skipUnnamed: _skipUnnamed,
    ));
  }

  void _clear() {
    Navigator.of(context).pop(_ScanFilterResult(
      nameList: const <String>[],
      uuidList: const <String>[],
      skipUnnamed: _skipUnnamed,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: colors.text2.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('扫描过滤',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.text1)),
            const SizedBox(height: 4),
            Text(
              '设备名 / UUID 留空则不过滤；多个值用换行、逗号或空格分隔。两组同时设置时按 (名称 AND UUID) 命中才上报。',
              style: TextStyle(fontSize: 11, color: colors.text2),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _skipUnnamed,
              onChanged: (v) => setState(() => _skipUnnamed = v),
              title: Text('跳过未命名设备',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.text1)),
              subtitle: Text('过滤掉广播里没有 name 的环境 BLE 噪声',
                  style: TextStyle(fontSize: 11, color: colors.text2)),
              activeColor: AppTheme.primary,
            ),
            const SizedBox(height: 6),
            Text('设备名（精确匹配）',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.text1)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtl,
              maxLines: 3,
              minLines: 1,
              style: TextStyle(fontSize: 13, color: colors.text1),
              decoration: InputDecoration(
                hintText: 'JL_Earphone\nMyDevice-01',
                hintStyle: TextStyle(fontSize: 12, color: colors.text2),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
            const SizedBox(height: 12),
            Text('UUID（广播 flagContent contains）',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.text1)),
            const SizedBox(height: 6),
            TextField(
              controller: _uuidCtl,
              maxLines: 3,
              minLines: 1,
              style: TextStyle(fontSize: 13, color: colors.text1),
              decoration: InputDecoration(
                hintText: '0000180D-0000-1000-8000-00805F9B34FB',
                hintStyle: TextStyle(fontSize: 12, color: colors.text2),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clear,
                    child: const Text('清除过滤'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary),
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
