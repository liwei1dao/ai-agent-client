import 'dart:async';

import 'package:device_manager/device_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      await manager.startScan(timeout: const Duration(seconds: 30));
      if (mounted) setState(() => _scanning = true);
    } on DeviceException catch (e) {
      _toast('扫描失败：${e.code}');
    } catch (e) {
      _toast('扫描失败：$e');
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
          if (vendor != null)
            IconButton(
              icon: Icon(_scanning ? Icons.stop_circle_outlined : Icons.search,
                  color: AppTheme.primary),
              tooltip: _scanning ? '停止扫描' : '开始扫描',
              onPressed: _toggleScan,
            ),
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
                          onTap: isConnecting ? null : () => _connect(d),
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
    final battery = info?.batteryPercent ?? session.info.batteryPercent;
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
                  Row(
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
                      if (battery != null) ...[
                        const SizedBox(width: 8),
                        _BatteryChip(percent: battery),
                      ],
                      if (fw != null && fw.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text('FW $fw',
                            style: TextStyle(
                                fontSize: 10, color: colors.text2)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: widget.onDisconnect,
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444)),
              child: const Text('断开'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatteryChip extends StatelessWidget {
  const _BatteryChip({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final clamped = percent.clamp(0, 100);
    final IconData icon;
    final Color color;
    if (clamped <= 15) {
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
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
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
  });
  final DiscoveredDevice device;
  final bool connecting;
  final VoidCallback? onTap;

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
            : const Icon(Icons.chevron_right),
        onTap: onTap,
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
