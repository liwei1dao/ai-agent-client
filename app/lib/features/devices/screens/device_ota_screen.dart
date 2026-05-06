import 'dart:async';

import 'package:device_manager/device_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/device_service.dart';
import '../../../shared/themes/app_theme.dart';

/// 设备 OTA 升级界面。
///
/// 入口：连接成功的设备 tile 上的「升级」按钮（仅 capability 包含 OTA 才显示）。
///
/// 行为铁律：
/// 1. 升级**进行中**（`port.isRunning` || 当前进度非终态）期间，整个界面锁定：
///    - WillPopScope 拦截系统返回；
///    - AppBar 不显示返回箭头；
///    - 文件 / URL 输入框、升级按钮全部 disabled；
///    - 仅「取消」可用。
/// 2. 终态（done / failed / cancelled）后解锁，可以返回 / 重新选包。
/// 3. 设备掉线时 native 端会派 `failed(disconnected_remote)`，UI 会自动解锁；
///    回到设备列表后用户重连即可。
class DeviceOtaScreen extends ConsumerStatefulWidget {
  const DeviceOtaScreen({super.key});

  @override
  ConsumerState<DeviceOtaScreen> createState() => _DeviceOtaScreenState();
}

class _DeviceOtaScreenState extends ConsumerState<DeviceOtaScreen> {
  final _urlCtrl = TextEditingController();
  String? _localPath;
  String? _localName;
  int? _localSize;

  DeviceOtaPort? _port;
  StreamSubscription<DeviceOtaProgress>? _sub;
  DeviceOtaProgress? _progress;
  bool _starting = false;
  String? _toastError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bind());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _bind() {
    final session = ref.read(deviceManagerProvider).activeSession;
    final port = session?.otaPort();
    if (port == null) {
      // 进入页面但没 active session / 不支持 OTA：直接返回
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('当前设备不支持 OTA 升级')));
        context.pop();
      }
      return;
    }
    _port = port;
    _sub = port.progressStream.listen((p) {
      if (!mounted) return;
      setState(() => _progress = p);
      if (p.isTerminal) {
        _starting = false;
        _showTerminalToast(p);
      }
    });
  }

  bool get _isLocked {
    final p = _progress;
    if (_starting) return true;
    if (p == null) return false;
    return !p.isTerminal;
  }

  bool get _hasFirmware => _localPath != null || _urlCtrl.text.trim().isNotEmpty;

  Future<void> _pickFile() async {
    if (_isLocked) return;
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.single;
      if (f.path == null) {
        _toast('无法读取文件路径');
        return;
      }
      setState(() {
        _localPath = f.path;
        _localName = f.name;
        _localSize = f.size;
        _urlCtrl.clear();
      });
    } catch (e) {
      _toast('选择文件失败：$e');
    }
  }

  void _clearFile() {
    if (_isLocked) return;
    setState(() {
      _localPath = null;
      _localName = null;
      _localSize = null;
    });
  }

  Future<void> _start() async {
    final port = _port;
    if (port == null || _isLocked || !_hasFirmware) return;
    setState(() {
      _starting = true;
      _toastError = null;
      _progress = null;
    });
    try {
      await port.start(_buildRequest());
    } on DeviceException catch (e) {
      if (mounted) {
        setState(() {
          _starting = false;
          _toastError = '${e.code}: ${e.message ?? ''}';
        });
        _toast('启动失败：${e.code}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _starting = false;
          _toastError = '$e';
        });
        _toast('启动失败：$e');
      }
    }
  }

  /// 构造请求 —— 不下载、不转码，URL 直接交给容器层（device_manager native）
  /// 由其下载完转 file 请求再分派给厂商端口。Flutter 端只是个"提交者"。
  DeviceOtaRequest _buildRequest() {
    final url = _urlCtrl.text.trim();
    if (_localPath != null) {
      return DeviceOtaFileRequest(filePath: _localPath!);
    }
    if (url.isEmpty) {
      throw DeviceException(
          DeviceErrorCode.invalidArgument, 'firmware not selected');
    }
    return DeviceOtaUrlRequest(url: url);
  }

  Future<void> _cancel() async {
    final port = _port;
    if (port == null) return;
    await port.cancel();
    // 状态最终由 progress=cancelled 推过来更新；这里不本地翻转 _isLocked。
  }

  void _showTerminalToast(DeviceOtaProgress p) {
    final msg = switch (p.state) {
      DeviceOtaState.done => '升级完成，请等待设备重启',
      DeviceOtaState.cancelled => '已取消升级',
      DeviceOtaState.failed => '升级失败：${p.errorCode ?? p.errorMessage ?? "unknown"}',
      _ => null,
    };
    if (msg != null) _toast(msg);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final snapshot = ref.watch(deviceSnapshotProvider).value;
    final state = _progress?.state ?? DeviceOtaState.idle;
    final percent = _progress?.percent ?? 0;
    final showProgress = _starting || (_progress != null && !_progress!.isTerminal);

    return PopScope(
      canPop: !_isLocked,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _toast('升级进行中，请先取消或等待完成');
      },
      child: Scaffold(
        backgroundColor: colors.bg,
        appBar: AppBar(
          title: const Text('固件升级'),
          // 升级中隐藏返回箭头：用户必须先取消或等终态。
          leading: _isLocked ? const SizedBox.shrink() : null,
          automaticallyImplyLeading: !_isLocked,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (snapshot != null) _DeviceCard(snapshot: snapshot),
              const SizedBox(height: 16),
              _SectionLabel('选择固件包'),
              const SizedBox(height: 8),
              _FileTile(
                name: _localName,
                size: _localSize,
                onPick: _pickFile,
                onClear: _localPath != null ? _clearFile : null,
                disabled: _isLocked,
              ),
              const SizedBox(height: 12),
              _SectionLabel('或填写远程地址'),
              const SizedBox(height: 8),
              TextField(
                controller: _urlCtrl,
                enabled: !_isLocked && _localPath == null,
                decoration: InputDecoration(
                  hintText: 'https://example.com/firmware.ufw',
                  filled: true,
                  fillColor: colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),
              if (showProgress || state != DeviceOtaState.idle) ...[
                _ProgressCard(
                  state: state,
                  percent: percent,
                  sentBytes: _progress?.sentBytes ?? 0,
                  totalBytes: _progress?.totalBytes ?? 0,
                  errorMessage: _progress?.errorMessage,
                  errorCode: _progress?.errorCode,
                ),
                const SizedBox(height: 16),
              ],
              if (_toastError != null && _progress == null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _toastError!,
                    style: const TextStyle(color: AppTheme.danger, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _ActionRow(
                locked: _isLocked,
                canStart: !_isLocked && _hasFirmware,
                onStart: _start,
                onCancel: _cancel,
              ),
              const SizedBox(height: 24),
              Text(
                '⚠ 升级过程中请保持设备靠近手机，不要断开蓝牙连接或退出 app；'
                '升级完成后设备会自动重启，重启后可重新连接。',
                style: TextStyle(fontSize: 12, color: colors.text2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.snapshot});
  final DeviceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.headset_mic, color: AppTheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.name.isEmpty ? '设备' : snapshot.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.text1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  snapshot.deviceId,
                  style: TextStyle(fontSize: 11, color: colors.text2),
                ),
                if (snapshot.firmwareVersion != null &&
                    snapshot.firmwareVersion!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '当前固件 ${snapshot.firmwareVersion}',
                      style: TextStyle(fontSize: 11, color: colors.text2),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.name,
    required this.size,
    required this.onPick,
    required this.onClear,
    required this.disabled,
  });

  final String? name;
  final int? size;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hasFile = name != null;
    return InkWell(
      onTap: disabled ? null : onPick,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasFile ? AppTheme.primary : colors.border,
            width: hasFile ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasFile ? Icons.insert_drive_file : Icons.upload_file_outlined,
              size: 22,
              color: hasFile ? AppTheme.primary : colors.text2,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: hasFile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name!,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.text1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          size != null ? _humanSize(size!) : '',
                          style: TextStyle(fontSize: 11, color: colors.text2),
                        ),
                      ],
                    )
                  : Text(
                      '点击选择本地固件文件',
                      style: TextStyle(fontSize: 14, color: colors.text2),
                    ),
            ),
            if (hasFile && onClear != null)
              IconButton(
                icon: Icon(Icons.close, size: 18, color: colors.text2),
                onPressed: disabled ? null : onClear,
              ),
          ],
        ),
      ),
    );
  }

  static String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.state,
    required this.percent,
    required this.sentBytes,
    required this.totalBytes,
    required this.errorMessage,
    required this.errorCode,
  });

  final DeviceOtaState state;
  final int percent;
  final int sentBytes;
  final int totalBytes;
  final String? errorMessage;
  final String? errorCode;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (label, accent) = _stateMeta(state);
    final showBar = (state == DeviceOtaState.transferring ||
            state == DeviceOtaState.downloading) &&
        percent >= 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: state == DeviceOtaState.failed ||
                        state == DeviceOtaState.cancelled ||
                        state == DeviceOtaState.done
                    ? Icon(
                        state == DeviceOtaState.done
                            ? Icons.check_circle
                            : (state == DeviceOtaState.failed
                                ? Icons.error
                                : Icons.cancel),
                        color: accent,
                        size: 14,
                      )
                    : CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(accent),
                      ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
              const Spacer(),
              if (showBar)
                Text(
                  '$percent%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
            ],
          ),
          if (showBar) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent / 100.0,
                minHeight: 6,
                backgroundColor: colors.border,
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_kb(sentBytes)} / ${_kb(totalBytes)}',
              style: TextStyle(fontSize: 11, color: colors.text2),
            ),
          ],
          if (state == DeviceOtaState.failed && errorCode != null) ...[
            const SizedBox(height: 8),
            Text(
              '$errorCode${errorMessage != null ? ' — $errorMessage' : ''}',
              style: const TextStyle(fontSize: 12, color: AppTheme.danger),
            ),
          ],
        ],
      ),
    );
  }

  static String _kb(int bytes) {
    if (bytes <= 0) return '0';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  static (String, Color) _stateMeta(DeviceOtaState s) => switch (s) {
        DeviceOtaState.idle => ('待开始', AppTheme.text2),
        DeviceOtaState.downloading => ('下载固件中…', AppTheme.primary),
        DeviceOtaState.inquiring => ('询问设备…', AppTheme.primary),
        DeviceOtaState.notifyingSize => ('发送固件大小…', AppTheme.primary),
        DeviceOtaState.entering => ('设备进入升级模式…', AppTheme.primary),
        DeviceOtaState.transferring => ('传输固件中', AppTheme.primary),
        DeviceOtaState.verifying => ('校验固件…', AppTheme.primary),
        DeviceOtaState.rebooting => ('设备重启中…', AppTheme.primary),
        DeviceOtaState.done => ('升级成功', AppTheme.success),
        DeviceOtaState.failed => ('升级失败', AppTheme.danger),
        DeviceOtaState.cancelled => ('已取消', AppTheme.warning),
      };
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.locked,
    required this.canStart,
    required this.onStart,
    required this.onCancel,
  });

  final bool locked;
  final bool canStart;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (locked) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onCancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.danger,
            side: const BorderSide(color: AppTheme.danger),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('取消升级'),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: canStart ? onStart : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.primary,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: const Icon(Icons.system_update),
        label: const Text('开始升级'),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: context.appColors.text2,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
