import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:talker_flutter/talker_flutter.dart';

/// 统一日志服务：
/// - Dart 侧：Talker 接管 `print` / `debugPrint` / `FlutterError` / `PlatformDispatcher.onError`
/// - 原生侧：Android 通过 EventChannel 推送 logcat；iOS 推送 OSLogStore + stderr 重定向
/// - 所有日志落盘到 `<docs>/logs/app-YYYY-MM-DD.log`，按天滚动，默认保留 7 天
class LogService {
  LogService._();
  static final LogService instance = LogService._();

  static const _channel = EventChannel('ai_agent_client/log/native');
  static const _retainDays = 7;

  late final Talker talker;
  Directory? _logDir;
  IOSink? _sink;
  String? _currentDate;
  StreamSubscription<dynamic>? _nativeSub;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    talker = Talker(
      settings: TalkerSettings(
        maxHistoryItems: 2000,
        useConsoleLogs: kDebugMode,
      ),
    );

    await _initFileSink();
    _hookFlutterErrors();
    _hookZonedPrint();
    _listenNative();

    talker.info('LogService initialized');
  }

  Future<void> _initFileSink() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/logs');
      if (!await dir.exists()) await dir.create(recursive: true);
      _logDir = dir;
      _rotateIfNeeded();
      _cleanupOld();

      talker.stream.listen((data) {
        try {
          _sink?.writeln(data.generateTextMessage());
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('LogService file sink init failed: $e');
    }
  }

  void _rotateIfNeeded() {
    final dir = _logDir;
    if (dir == null) return;
    final today = _formatDate(DateTime.now());
    if (_currentDate == today && _sink != null) return;
    _currentDate = today;
    _sink?.flush();
    _sink?.close();
    final file = File('${dir.path}/app-$today.log');
    _sink = file.openWrite(mode: FileMode.writeOnlyAppend);
  }

  void _cleanupOld() {
    final dir = _logDir;
    if (dir == null) return;
    final cutoff = DateTime.now().subtract(const Duration(days: _retainDays));
    try {
      for (final e in dir.listSync()) {
        if (e is! File) continue;
        final stat = e.statSync();
        if (stat.modified.isBefore(cutoff)) {
          try {
            e.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  void _hookFlutterErrors() {
    FlutterError.onError = (details) {
      talker.handle(details.exception, details.stack, 'FlutterError');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      talker.handle(error, stack, 'PlatformDispatcher');
      return true;
    };
  }

  void _hookZonedPrint() {
    // 把 debugPrint 也灌进 Talker
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) talker.debug(message);
    };
  }

  void _listenNative() {
    _nativeSub = _channel.receiveBroadcastStream().listen(
      (event) {
        if (event is! Map) return;
        final level = (event['level'] as String?) ?? 'i';
        final tag = event['tag'] as String?;
        final msg = (event['message'] as String?) ?? '';
        final source = (event['source'] as String?) ?? 'native';
        final prefix = tag == null ? '[$source]' : '[$source/$tag]';
        final line = '$prefix $msg';
        switch (level) {
          case 'v':
          case 'd':
            talker.debug(line);
            break;
          case 'w':
            talker.warning(line);
            break;
          case 'e':
          case 'f':
          case 'a':
            talker.error(line);
            break;
          default:
            talker.info(line);
        }
      },
      onError: (e) => talker.error('native log channel error: $e'),
    );
  }

  /// 日志目录大小（字节）
  Future<int> totalSize() async {
    final dir = _logDir;
    if (dir == null) return 0;
    var total = 0;
    try {
      for (final e in dir.listSync()) {
        if (e is File) total += e.lengthSync();
      }
    } catch (_) {}
    return total;
  }

  List<File> listLogFiles() {
    final dir = _logDir;
    if (dir == null) return const [];
    try {
      return dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
    } catch (_) {
      return const [];
    }
  }

  /// 清空日志：关闭当前 sink → 删除所有文件 → 重新建立 sink
  Future<void> clear() async {
    try {
      await _sink?.flush();
      await _sink?.close();
      _sink = null;
      _currentDate = null;

      final dir = _logDir;
      if (dir != null) {
        for (final e in dir.listSync()) {
          if (e is File) {
            try {
              await e.delete();
            } catch (_) {}
          }
        }
      }
      talker.cleanHistory();
      _rotateIfNeeded();
      talker.info('Logs cleared');
    } catch (e) {
      talker.error('Logs clear failed: $e');
      rethrow;
    }
  }

  /// 合并所有日志文件 + Talker history 导出为一个文件，返回路径
  Future<File> exportToFile() async {
    final dir = _logDir;
    if (dir == null) {
      throw StateError('Log directory not ready');
    }
    await _sink?.flush();

    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final out = File('${tmp.path}/ai_agent_logs_$stamp.log');
    final sink = out.openWrite();

    sink.writeln('# AI Agent Client 日志导出');
    sink.writeln('# 导出时间: ${DateTime.now().toIso8601String()}');
    sink.writeln('# 平台: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    sink.writeln('');

    for (final f in listLogFiles().reversed) {
      sink.writeln('===== ${f.uri.pathSegments.last} =====');
      try {
        await sink.addStream(f.openRead());
      } catch (e) {
        sink.writeln('<read failed: $e>');
      }
      sink.writeln('');
    }

    // 追加当前内存 history（可能比文件新）
    sink.writeln('===== in-memory history =====');
    for (final item in talker.history) {
      sink.writeln(item.generateTextMessage());
    }

    await sink.flush();
    await sink.close();
    return out;
  }

  Future<void> dispose() async {
    await _nativeSub?.cancel();
    await _sink?.flush();
    await _sink?.close();
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 便捷访问
Talker get logger => LogService.instance.talker;
