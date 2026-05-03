import 'dart:developer' as developer;
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

/// 日志级别
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// 日志工具类
///
/// 特性：
/// - 写日志只入内存队列，由后台 Timer 定时批量刷盘，避免主 Isolate 同步 I/O。
/// - Release 包默认 [LogLevel.warning]，Debug 包默认 [LogLevel.debug]。
/// - `error` 级别写入后强制立即 flush，崩溃前关键错误不丢。
/// - 支持 `dLazy/iLazy/wLazy` 闭包式 API，级别被过滤时完全不执行字符串插值。
/// - 时间戳格式化按秒缓存，避免每条日志重复 `DateFormat`。
class Logger {
  /// 当前日志级别
  static LogLevel _currentLevel =
      kReleaseMode ? LogLevel.warning : LogLevel.debug;

  /// 控制台输出开关（Release 默认关闭以减少 developer.log 开销）
  static bool _consoleEnabled = !kReleaseMode;

  /// 默认标签
  static const String _defaultTag = 'App';

  /// 文件日志相关
  static IOSink? _logSink;
  static File? _currentLogFile;
  static bool _fileLogEnabled = false;
  static String? _logDirPath;
  static final DateFormat _fileDateFormat = DateFormat('yyyy-MM-dd');

  /// 单行最大字符数，超过则截断（避免日志被过长字符串拖慢）
  static const int _maxLineLength = 4000;

  /// 最大单个日志文件大小 (2MB)
  static const int _maxFileSize = 2 * 1024 * 1024;

  /// 最多保留日志文件数量
  static const int _maxLogFiles = 7;

  /// 内存队列：写日志只入队，由定时器批量落盘
  static final List<String> _queue = <String>[];

  /// 队列上限。超过后丢弃最旧条目（保留最新），防止内存无限增长。
  static const int _maxQueueSize = 5000;

  /// 定时刷盘间隔
  static const Duration _flushInterval = Duration(milliseconds: 500);
  static Timer? _flushTimer;

  /// 轮转检查间隔
  static const Duration _rotationInterval = Duration(seconds: 30);
  static Timer? _rotationTimer;

  /// 轮转锁，防止并发轮转
  static bool _isRotating = false;

  /// 正在刷盘标记，防止定时器重入
  static bool _isFlushing = false;

  /// 当前日志文件的日期标识
  static String _currentFileDate = '';

  /// 时间戳缓存：同一秒内复用
  static int _cachedTsEpochSecond = 0;
  static String _cachedTsString = '';

  /// 初始化文件日志
  static Future<void> initFileLog() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logDirPath = '${dir.path}/logs';
      final logDir = Directory(_logDirPath!);
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      await _openLogFile();
      _fileLogEnabled = true;

      // 启动后台刷盘与轮转定时器
      _flushTimer ??= Timer.periodic(_flushInterval, (_) => _drainQueue());
      _rotationTimer ??=
          Timer.periodic(_rotationInterval, (_) => _checkRotation());

      Logger.i('Logger', '文件日志初始化成功: $_logDirPath level=$_currentLevel');
    } catch (e) {
      developer.log('[Logger] 文件日志初始化失败: $e');
    }
  }

  /// 打开/创建当前日志文件
  static Future<void> _openLogFile() async {
    final today = _fileDateFormat.format(DateTime.now());
    final filePath = '$_logDirPath/app_$today.log';
    _currentLogFile = File(filePath);
    await _logSink?.flush();
    await _logSink?.close();
    _logSink = _currentLogFile!.openWrite(mode: FileMode.append);
    _currentFileDate = today;
  }

  /// 把队列里的所有条目一次性写到 sink
  static Future<void> _drainQueue() async {
    if (_isFlushing) return;
    if (!_fileLogEnabled || _logSink == null) return;
    if (_queue.isEmpty) return;
    _isFlushing = true;
    try {
      // O(1) 取出全部
      final batch = List<String>.unmodifiable(_queue);
      _queue.clear();
      // 单次 write 减少 syscall 次数
      _logSink!.write(batch.join('\n'));
      _logSink!.write('\n');
      await _logSink!.flush();
    } catch (e) {
      developer.log('[Logger] drain 失败: $e');
    } finally {
      _isFlushing = false;
    }
  }

  /// 检查日志文件是否需要轮转（后台定时调度，不在写路径执行）
  static Future<void> _checkRotation() async {
    if (_isRotating || _currentLogFile == null) return;
    _isRotating = true;
    try {
      // 先把队列里的内容落盘，以免轮转后丢
      await _drainQueue();

      // 日期变更 → 换新文件
      final today = _fileDateFormat.format(DateTime.now());
      if (_currentFileDate != today) {
        await _openLogFile();
      }
      // 文件过大 → 切分
      if (await _currentLogFile!.exists()) {
        final size = await _currentLogFile!.length();
        if (size > _maxFileSize) {
          final now = DateTime.now();
          final suffix = DateFormat('HHmmss').format(now);
          final todayStr = _fileDateFormat.format(now);
          final newPath = '$_logDirPath/app_${todayStr}_$suffix.log';
          await _logSink?.flush();
          await _logSink?.close();
          _currentLogFile = File(newPath);
          _logSink = _currentLogFile!.openWrite(mode: FileMode.append);
        }
      }
      await _cleanOldLogs();
    } catch (_) {
    } finally {
      _isRotating = false;
    }
  }

  /// 清理旧日志文件，保留最近 _maxLogFiles 个
  static Future<void> _cleanOldLogs() async {
    if (_logDirPath == null) return;
    try {
      final logDir = Directory(_logDirPath!);
      final files = await logDir
          .list()
          .where((e) => e is File && e.path.endsWith('.log'))
          .cast<File>()
          .toList();
      if (files.length > _maxLogFiles) {
        files.sort((a, b) => a.path.compareTo(b.path));
        final toDelete = files.sublist(0, files.length - _maxLogFiles);
        for (final f in toDelete) {
          await f.delete();
        }
      }
    } catch (_) {}
  }

  /// 快速时间戳（到秒级缓存 + 毫秒拼接）
  static String _formatTimestamp(DateTime now) {
    final epochSec = now.millisecondsSinceEpoch ~/ 1000;
    if (epochSec != _cachedTsEpochSecond) {
      _cachedTsEpochSecond = epochSec;
      // yyyy-MM-dd HH:mm:ss
      final y = now.year.toString().padLeft(4, '0');
      final mo = now.month.toString().padLeft(2, '0');
      final d = now.day.toString().padLeft(2, '0');
      final h = now.hour.toString().padLeft(2, '0');
      final mi = now.minute.toString().padLeft(2, '0');
      final s = now.second.toString().padLeft(2, '0');
      _cachedTsString = '$y-$mo-$d $h:$mi:$s';
    }
    final ms = now.millisecond.toString().padLeft(3, '0');
    return '$_cachedTsString.$ms';
  }

  /// 入队（不触发 I/O）
  static void _enqueue(String level, String tag, String message) {
    if (!_fileLogEnabled) return;
    final ts = _formatTimestamp(DateTime.now());
    String msg = message;
    if (msg.length > _maxLineLength) {
      msg =
          '${msg.substring(0, _maxLineLength)}… (truncated ${message.length - _maxLineLength}字符)';
    }
    // 溢出保护：保留最新
    if (_queue.length >= _maxQueueSize) {
      _queue.removeRange(0, _queue.length - _maxQueueSize + 1);
    }
    _queue.add('$ts [$level][$tag] $msg');
  }

  /// 获取日志目录路径
  static String? get logDirPath => _logDirPath;

  /// 获取所有日志文件列表
  static Future<List<File>> getLogFiles() async {
    if (_logDirPath == null) return [];
    final logDir = Directory(_logDirPath!);
    if (!await logDir.exists()) return [];
    final files = await logDir
        .list()
        .where((e) => e is File && e.path.endsWith('.log'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// 强制把队列刷到磁盘（导出前调用）
  static Future<void> flush() async {
    await _drainQueue();
    await _logSink?.flush();
  }

  /// 设置日志级别
  static void setLevel(LogLevel level) {
    _currentLevel = level;
  }

  /// 开关控制台输出（默认 Release 关闭）
  static void setConsoleEnabled(bool enabled) {
    _consoleEnabled = enabled;
  }

  /// 当前级别是否允许某级别输出
  static bool isLoggable(LogLevel level) =>
      level.index >= _currentLevel.index;

  // ========== 普通 API ==========

  static void debug(String message) {
    if (LogLevel.debug.index >= _currentLevel.index) {
      _log('DEBUG', _defaultTag, message, false);
    }
  }

  static void d(String tag, String message) {
    if (LogLevel.debug.index >= _currentLevel.index) {
      _log('DEBUG', tag, message, false);
    }
  }

  static void info(String message) {
    if (LogLevel.info.index >= _currentLevel.index) {
      _log('INFO', _defaultTag, message, false);
    }
  }

  static void i(String tag, String message) {
    if (LogLevel.info.index >= _currentLevel.index) {
      _log('INFO', tag, message, false);
    }
  }

  static void warning(String message) {
    if (LogLevel.warning.index >= _currentLevel.index) {
      _log('WARN', _defaultTag, message, false);
    }
  }

  static void w(String tag, String message) {
    if (LogLevel.warning.index >= _currentLevel.index) {
      _log('WARN', tag, message, false);
    }
  }

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    if (LogLevel.error.index >= _currentLevel.index) {
      _log('ERROR', _defaultTag, message, true);
      if (error != null) _log('ERROR', _defaultTag, 'Original error: $error', true);
      if (stackTrace != null) {
        _log('ERROR', _defaultTag, 'Stack trace: $stackTrace', true);
      }
    }
  }

  static void e(String tag, String message,
      [dynamic error, StackTrace? stackTrace]) {
    if (LogLevel.error.index >= _currentLevel.index) {
      _log('ERROR', tag, message, true);
      if (error != null) _log('ERROR', tag, 'Original error: $error', true);
      if (stackTrace != null) {
        _log('ERROR', tag, 'Stack trace: $stackTrace', true);
      }
    }
  }

  // ========== 闭包式 API（高频热点推荐） ==========

  /// Debug 级别懒求值：级别未放行时连字符串都不会构造。
  static void dLazy(String tag, String Function() messageBuilder) {
    if (LogLevel.debug.index >= _currentLevel.index) {
      _log('DEBUG', tag, messageBuilder(), false);
    }
  }

  static void iLazy(String tag, String Function() messageBuilder) {
    if (LogLevel.info.index >= _currentLevel.index) {
      _log('INFO', tag, messageBuilder(), false);
    }
  }

  static void wLazy(String tag, String Function() messageBuilder) {
    if (LogLevel.warning.index >= _currentLevel.index) {
      _log('WARN', tag, messageBuilder(), false);
    }
  }

  /// 内部日志输出方法
  ///
  /// [forceFlush] = true 时（error 级别）立即触发一次 drain，
  /// 保证崩溃前关键错误一定落盘。
  static void _log(String level, String tag, String message, bool forceFlush) {
    if (_consoleEnabled) {
      if (message.length <= _maxLineLength) {
        developer.log('[$tag]: $message');
      } else {
        developer.log(
            '[$tag]: ${message.substring(0, _maxLineLength)}… (+${message.length - _maxLineLength}字符)');
      }
    }
    _enqueue(level, tag, message);
    if (forceFlush) {
      // fire-and-forget；_drainQueue 自带并发保护
      // 不 await 以免阻塞调用方
      // ignore: discarded_futures
      _drainQueue();
    }
  }
}
