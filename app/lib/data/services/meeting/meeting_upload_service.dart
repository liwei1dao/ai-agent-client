import 'dart:io';
import 'dart:async';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../../core/utils/logger.dart';
import '../../../core/utils/upload_oss.dart';
import '../network/api.dart';
import '../usage_stats_service.dart';
import '../db/sqflite_api.dart';
import 'meeting_task_service.dart';

/// 管理会议音频文件上传服务
class MeetingUploadService extends GetxService {
  final _taskService = Get.find<MeetingTaskService>();

  final GetStorage _storage = GetStorage();

  RxInt meetingId = 0.obs;
  RxDouble uploadProgress = 0.0.obs;
  RxList uploadList = [].obs;

  bool _isUpload = false;
  int _handled = 0; //队列处理指针,表示当前循环语句处理的任务数量
  static const Duration _fileStableTimeout = Duration(seconds: 20);
  static const Duration _fileStablePoll = Duration(milliseconds: 350);
  static const int _fileStableNeededCount = 3;

  @override
  void onInit() {
    super.onInit();
    _getUploadList();
  }

  void cancelUpload() {
    _isUpload = false;
    _handled = 0;
    uploadList.clear();
    _storage.remove("meeting_upload_list");
  }

  void _getUploadList() {
    uploadList.value = _storage.read("meeting_upload_list") ?? [];
    executeUpload();
  }

  /// 添加待上传的音频文件
  void addUpload(
    int id,
    String filePath,
    String rootDir, {
    bool isUpload = true,
  }) async {
    int fileSize = 0;
    try {
      fileSize = await File(filePath).length();
    } catch (_) {}
    uploadList.add({
      'id': id,
      'filepath': filePath,
      'rootdir': rootDir,
      'audiourl': '',
      'isTask': false,
      'formlanguage': '',
      'tolanguage': '',
      'isdistinguishspeaker': true,
      'templateid': 0,
      'fileSizeBytes': fileSize,
    });
    _storage.write("meeting_upload_list", uploadList);
    if (isUpload) {
      executeUpload();
    }
  }

  void executeUpload() async {
    if (_isUpload) return;
    _isUpload = true;
    _handled = 0;
    while (_handled < uploadList.length) {
      Map element = uploadList[_handled];
      _handled++;
      if (element['audiourl'].isEmpty) {
        meetingId.value = element['id'];
        try {
          int totalProgress = 0;
          final filePath = (element['filepath'] ?? '').toString();
          if (filePath.isEmpty) {
            throw Exception('Empty upload file path');
          }
          final fileSizeBytes = await _waitForStableFileSize(
            filePath,
            timeout: _fileStableTimeout,
            pollInterval: _fileStablePoll,
            stableNeededCount: _fileStableNeededCount,
          );
          final isWav = filePath.toLowerCase().endsWith('.wav');
          if (isWav) {
            final ok = await _isWavHeaderConsistent(filePath, fileSizeBytes);
            if (!ok) {
              throw Exception('WAV header is inconsistent with file size');
            }
          }
          element['fileSizeBytes'] = fileSizeBytes;
          final audiourl = await UploadOss.upload(
            filepath: filePath,
            rootDir: element['rootdir'],
            onSendProgress: (int count, int total) {
              // uploadProgress.value = count / total;
              totalProgress = total;
              uploadProgress.value = total > 0 ? count / total : 0.0;
            },
          );
          await Api.upRecordEchomeet({
            'id': element['id'],
            'audiourl': audiourl,
          });
          await SqfliteApi.editMeetingTitle(
            element['id'],
            {'audiourl': audiourl},
          );
          try {
            // 记录对象存储用量
            final svc = Get.isRegistered<UsageStatsService>()
                ? Get.find<UsageStatsService>()
                : Get.put(UsageStatsService(), permanent: true);
            int fileSizeBytes = 0;
            try {
              fileSizeBytes = element['fileSizeBytes'] ?? 0;
            } catch (_) {}
            final transferred =
                totalProgress > 0 ? totalProgress : fileSizeBytes;
            svc.recordMeetingObjectStorage(
              meetingId: element['id'],
              storageUrl: audiourl,
              storageBytes: fileSizeBytes,
              transferBytes: transferred,
              uploadTimestamp: DateTime.now().millisecondsSinceEpoch,
            );
          } catch (e) {
            Logger.w('MeetingOSrecord', '对象存储用量记录失败: $e');
          }
          if (element['isTask']) {
            await _taskService.submitTask(
              element['id'],
              element['formlanguage'],
              element['tolanguage'],
              element['isdistinguishspeaker'],
              element['templateid'],
              element['tid'] ?? '',
            );
          }
          element['audiourl'] = audiourl;
          uploadProgress.value = 0.0;
          _storage.write("meeting_upload_list", uploadList);
        } catch (e) {
          Logger.error('Upload failed: $e');
        }
      }
    }
    meetingId.value = 0;
    _isUpload = false;
  }

  Future<int> _waitForStableFileSize(
    String filePath, {
    Duration timeout = _fileStableTimeout,
    Duration pollInterval = _fileStablePoll,
    int stableNeededCount = _fileStableNeededCount,
  }) async {
    final file = File(filePath);
    final deadline = DateTime.now().add(timeout);
    int lastSize = -1;
    int stableCount = 0;
    while (DateTime.now().isBefore(deadline)) {
      final exists = await file.exists();
      if (exists) {
        int size = 0;
        try {
          size = await file.length();
        } catch (_) {
          size = 0;
        }
        if (size > 0) {
          if (size == lastSize) {
            stableCount += 1;
          } else {
            stableCount = 0;
            lastSize = size;
          }
          if (stableCount >= stableNeededCount) {
            return size;
          }
        }
      }
      await Future.delayed(pollInterval);
    }
    throw TimeoutException('File not stable: $filePath', timeout);
  }

  Future<bool> _isWavHeaderConsistent(
      String filePath, int fileSizeBytes) async {
    RandomAccessFile? raf;
    try {
      raf = await File(filePath).open(mode: FileMode.read);
      final header = await raf.read(12);
      if (header.length < 12) return false;
      final riff = String.fromCharCodes(header.sublist(0, 4));
      final wave = String.fromCharCodes(header.sublist(8, 12));
      if (riff != 'RIFF' || wave != 'WAVE') return true;

      int offset = 12;
      const int maxScanBytes = 64 * 1024;
      while (offset + 8 <= fileSizeBytes && offset <= maxScanBytes) {
        await raf.setPosition(offset);
        final chunkHeader = await raf.read(8);
        if (chunkHeader.length < 8) return false;
        final chunkId = String.fromCharCodes(chunkHeader.sublist(0, 4));
        final chunkSize = _readUint32Le(chunkHeader, 4);
        final chunkDataStart = offset + 8;
        final expectedEnd = chunkDataStart + chunkSize;
        if (chunkId == 'data') {
          return fileSizeBytes >= expectedEnd;
        }
        final paddedSize = chunkSize + (chunkSize % 2);
        offset = chunkDataStart + paddedSize;
      }
      return true;
    } catch (_) {
      return true;
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  int _readUint32Le(List<int> bytes, int offset) {
    if (offset + 4 > bytes.length) return 0;
    return (bytes[offset]) |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  void removeUpload(int id, {bool isDeleteTask = false}) {
    Map uploadData = uploadList.firstWhere(
      (element) => element['id'] == id,
      orElse: () => {},
    );
    if (uploadData.isNotEmpty) {
      if (isDeleteTask || uploadData['audiourl'].isNotEmpty) {
        uploadList.remove(uploadData);
        _storage.write("meeting_upload_list", uploadList);
        if (uploadList.isEmpty) {
          _handled = 0;
        }
      }
    }
  }
}
