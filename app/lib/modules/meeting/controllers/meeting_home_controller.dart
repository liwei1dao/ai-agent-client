import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import '../../../legacy_stubs/just_audio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/services/log_service.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/synchrodata.dart';
import '../../../data/services/ble_manager.dart';
import '../../../data/services/db/sqflite_api.dart';
import '../../../core/utils/permission_util.dart';

import 'package:share_plus/share_plus.dart';

import '../../../data/services/meeting/meeting_task_service.dart';
import '../../../data/services/meeting/meeting_upload_service.dart';
import '../../../data/services/network/api.dart';
import '../bindings/meeting_details_binding.dart';
import '../views/meeting_details_view.dart';
import 'meeting_record_controller.dart';
import 'meeting_controller.dart';

// 会议首页控制器
class MeetingHomeController extends GetxController {
  final meetingController = Get.find<MeetingController>();
  final meetingUploadService = Get.find<MeetingUploadService>();
  final meetingTaskService = Get.find<MeetingTaskService>();

  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isImportingLocalRecordings = false;

  List<String> selected = [];

  final appDocDir = getApplicationDocumentsDirectory();
  List<FileSystemEntity> files = [];
  TextEditingController titleController = TextEditingController(); // 录音标题
  String titleCSuffix = ""; // 录音标题后缀

  RxList originalDataList = [].obs;
  RxList dataList = [].obs;
  RxString filtrateType = ''.obs;
  bool isAsc = false; // 是否升序排序
  TextEditingController filtrateController = TextEditingController();

  // 多选删除模式状态
  final RxBool isSelectionMode = false.obs;
  final RxList<int> selectedIds = <int>[].obs;

  bool get isAllSelected =>
      dataList.isNotEmpty && selectedIds.length == dataList.length;

  void enterSelectionMode([int? id]) {
    isSelectionMode.value = true;
    if (id != null && !selectedIds.contains(id)) {
      selectedIds.add(id);
    }
  }

  void exitSelectionMode() {
    isSelectionMode.value = false;
    selectedIds.clear();
  }

  void toggleSelection(int id) {
    if (selectedIds.contains(id)) {
      selectedIds.remove(id);
    } else {
      selectedIds.add(id);
    }
  }

  void toggleSelectAll() {
    if (isAllSelected) {
      selectedIds.clear();
    } else {
      selectedIds.value =
          dataList.map<int>((item) => item['id'] as int).toList();
    }
  }

  Future<void> deleteSelectedMeetings() async {
    if (selectedIds.isEmpty) return;
    final ids = List<int>.from(selectedIds);
    for (final id in ids) {
      final item = originalDataList.firstWhere(
        (e) => e['id'] == id,
        orElse: () => null,
      );
      final filepath = item != null ? (item['filepath'] ?? '') as String : '';
      originalDataList.removeWhere((e) => e['id'] == id);
      dataList.removeWhere((e) => e['id'] == id);
      SqfliteApi.deleteMeeting(id);
      if (filepath.isNotEmpty) {
        await _deleteFile(filepath);
      }
      meetingUploadService.removeUpload(id, isDeleteTask: true);
      meetingTaskService.removeTask(id);
    }
    exitSelectionMode();
  }

  // 蓝牙服务
  final bleManager = Get.find<BleManager>();

  late final Worker _updateListStateListener;
  late final Worker _localImportListener;

  @override
  void onInit() {
    super.onInit();
    _requestStoragePermission();
    _initGetDataList();
    addMeetingAudio();
    final Map<String, dynamic> args = Get.arguments ?? {};
    // 检查参数是否存在且包含有效路径
    if (args.isNotEmpty &&
        args.containsKey('filePath') &&
        args['filePath'] is String &&
        args['filePath'].isNotEmpty) {
      final String path = args['filePath'];
      addAudio(path);
    }
    _updateListStateListener =
        ever(meetingTaskService.updateListState, (value) async {
      _getDataList();
    });
    _localImportListener = ever(meetingTaskService.localImportState, (value) {
      addMeetingAudio();
    });
  }

  @override
  void onClose() {
    titleController.dispose();
    filtrateController.dispose();
    _audioPlayer.dispose();
    _updateListStateListener.dispose();
    _localImportListener.dispose();
    super.onClose();
  }

  void onPopInvokedWithResult(didPop, result) {
    // Synchrodata.uploadOperationRecords(isSynchro: true);
    meetingTaskService.stopTask();
  }

  void _initGetDataList() async {
    await Synchrodata.uploadOperationRecords(isSynchro: true);
    _getDataList();
  }

  // 请求本地数据
  void _getDataList() async {
    List list = await SqfliteApi.getMeetingList();
    final ids = list.map((e) => e is Map ? e['id'] : null).toList();
    LogService.instance.talker.info(
        '[MeetingHomeController] getMeetingList loaded ${list.length} rows, ids=$ids');
    originalDataList.value = List.from(list);
    dataList.value = List.from(list);
  }

  // 请求存储权限
  void _requestStoragePermission() async {
    // 只在Android 10及以下版本请求存储权限
    if (Platform.isAndroid) {
      try {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final sdkVersion = androidInfo.version.sdkInt;

        // Android 11+ (API 30+) 不需要存储权限
        if (sdkVersion >= 30) {
          Logger.d("Permission", "Android 11+版本，无需请求存储权限");
          return;
        }
      } catch (e) {
        Logger.e("Permission", "获取Android版本信息失败: $e");
        // 如果获取版本失败，为了兼容性还是请求权限
      }
    }

    PermissionUtil.instance
        .requestPermission(
      permissionType: Permission.storage,
      permissionName: "meetingStoragePermission".tr, // 对应中文：存储
      explanationText: "meetingStoragePermissionExplanation"
          .tr, // 对应中文：我们需要访问存储权限，以便您可以选择并上传音频文件。
      permanentDenialText: "meetingStoragePermissionPermanentDenial"
          .tr, // 对应中文：检测到您已永久拒绝存储权限。如需继续使用此功能，请前往应用设置中手动开启存储权限。
    )
        .then((granted) {
      if (granted) {
        Logger.d("Permission", "用户授予了存储权限");
      } else {
        Logger.d("Permission", "用户未授予存储权限");
      }
    });
  }

  void loadTranslatopus() async {
    final dir = Directory("/data/user/0/com.saitong.voitrans/files/OpusAudio");

    files = dir
        .listSync()
        .where((f) => f is File && (f.path.endsWith('.opus')))
        .toList();
  }

//未使用
  void loadTranslatAudio() async {
    try {
      final appDir = await appDocDir; // 先 await 获取目录
      final dir = Directory("${appDir.path}/TranslatAudio");

      if (!await dir.exists()) {
        await dir.create(recursive: true);
        files = [];
        return;
      }

      files = dir
          .listSync()
          .where((f) =>
              f is File &&
              (f.path.endsWith('.mp3') ||
                  f.path.endsWith('.wav') ||
                  f.path.endsWith('.aac') ||
                  f.path.endsWith('.m4a') ||
                  f.path.endsWith('.mp4') ||
                  f.path.endsWith('.mov')))
          .toList();
    } catch (e) {
      files = [];
    }
  }

  Future<void> shareAllTranslatAudio() async {
    final filePath = selected[0];
    try {
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'shareAudio'.tr, // 对应中文：分享会议音频
      );

      EasyLoading.showToast('shareComplete'.tr); // 对应中文：分享完成！
    } catch (e) {
      EasyLoading.showToast('shareFailed'
          .tr
          .replaceAll('{error}', e.toString())); // 对应中文：分享失败: {error}
    }
  }

  // 核心方法：导入本地录音文件到统一目录
  void addMeetingAudio() async {
    if (_isImportingLocalRecordings) return;
    _isImportingLocalRecordings = true;
    EasyLoading.show(status: 'importingLocalRecordings'.tr); // 对应中文：正在导入本地录音...
    try {
      int addUp = 0; // 新增计数
      final appDir = await appDocDir; // 获取应用文档目录
      final activeRecordingWavName = _getActiveRecordingWavFileName();

      final sourceDirs = [
        Directory("${appDir.path}/MeetingAudio/"), // 会议录音目录
        Directory("${appDir.path}/DestAudio/"), // 目标录音目录
      ];

      // 目标目录：LocalAudio
      final destDir = Directory("${appDir.path}/LocalAudio/");
      if (!await destDir.exists()) {
        // 检查目标目录是否存在
        await destDir.create(recursive: true);
      }

      List<FileSystemEntity> allFiles = [];

      for (final dir in sourceDirs) {
        if (await dir.exists()) {
          final files = await dir
              .list(recursive: true, followLinks: false)
              .where((entity) => entity is File)
              .toList();
          allFiles.addAll(files); //合并到总文件列表
        }
      }

      // 遍历所有文件实体
      for (final fileEntity in allFiles) {
        try {
          final entityName = path.basename(fileEntity.path);
          final activeName = activeRecordingWavName == null
              ? null
              : path.basename(activeRecordingWavName);
          if (activeName != null && entityName == activeName) {
            continue;
          }

          final file = File(fileEntity.path); //将文件实体转换为具体文件操作对象
          final filePath = file.path;

          final fileStat = await file.stat(); //获取文件状态信息，包含修改时间等
          if (fileStat.size < 1024) {
            continue;
          }

          // 使用just_audio库加载音频文件以获取时长
          final Duration? duration =
              await _audioPlayer.setAudioSource(AudioSource.file(filePath));
          final Duration? effectiveDuration = duration ?? _audioPlayer.duration;
          final int durationMs = effectiveDuration?.inMilliseconds ?? 0;
          final int seconds =
              durationMs <= 0 ? 0 : ((durationMs + 999) ~/ 1000);
          if (seconds <= 0) {
            continue;
          }

          final creationTime = fileStat.changed.millisecondsSinceEpoch;

          final originalFileName = entityName;
          final pendingTitle = meetingTaskService
              .takePendingLocalRecordingTitle(originalFileName);
          final displayTitle = pendingTitle ?? originalFileName;

          // 准备新路径
          String fileName = originalFileName; //获取文件名（包含扩展名）
          String newPath = "${destDir.path}/$fileName"; //构建新路径，保持原文件名
          if (await File(newPath).exists()) {
            final ext = path.extension(fileName);
            final base = path.basenameWithoutExtension(fileName);
            final ts = DateTime.now().millisecondsSinceEpoch;
            fileName = '${base}_$ts$ext';
            newPath = "${destDir.path}/$fileName";
          }

          // 构建要存入数据库的音频文件抽象对象
          Map<String, Object?> data = {
            'title': displayTitle,
            'type': 'LOCAL',
            'seconds': seconds,
            'filepath': newPath, // 存储新路径
            'audiourl': '',
            'tasktype': 0,
            'creationtime': creationTime,
          };

          // 插入数据库
          final response = await Api.addRecordEchomeet({
            'rtype': 'LOCAL',
            'size': fileStat.size,
            ...data,
          });
          final meetingId = _extractMeetingId(response, 'addMeetingAudio');
          if (meetingId <= 0) {
            continue;
          }
          final meetingResult = await SqfliteApi.insertMeeting({
            'id': meetingId,
            ...data,
          });
          if (meetingResult != null) {
            // 移动文件：优先 rename，失败再 copy+delete，确保上传读取的是完整目标文件
            try {
              await file.rename(newPath);
            } catch (_) {
              await file.copy(newPath);
              await file.delete();
            }
            // 安排后台上传任务
            meetingUploadService.addUpload(meetingId, newPath, 'LocalAudio');

            originalDataList.insert(0, {
              'id': meetingId,
              ...data,
            });
            // 更新UI数据
            if (isAsc) {
              dataList.add({
                'id': meetingId,
                ...data,
              });
            } else {
              dataList.insert(0, {
                'id': meetingId,
                ...data,
              });
            }

            addUp++;
          }
        } catch (e) {
          Logger.error('fileProcessingFailed'
              .tr
              .replaceAll('{filePath}', fileEntity.path)
              .replaceAll('{error}',
                  e.toString())); // 对应中文：文件处理失败: {filePath}, 错误: {error}
        }
      }
      if (addUp > 0) {
        EasyLoading.showSuccess('importSuccess'
            .tr
            .replaceAll('{count}', '$addUp')); // 对应中文：成功导入本地 {count} 条录音
      }
    } catch (e) {
      EasyLoading.showError('importError'
          .tr
          .replaceAll('{error}', e.toString())); // 对应中文：导入失败: {error}
    } finally {
      _isImportingLocalRecordings = false;
      EasyLoading.dismiss();
    }
  }

  String? _getActiveRecordingWavFileName() {
    if (!Get.isRegistered<MeetingRecordController>()) return null;
    final controller = Get.find<MeetingRecordController>();
    if (!controller.isRecording.value) return null;
    final name = controller.fileName.value;
    if (name.isEmpty) return null;
    return path.basename('$name.wav');
  }

  // 新增（2025-11-04）：将翻译音频归档到 LocalAudio 并返回新路径（优先 rename，失败再 copy+delete）
  Future<String> _archiveTranslatToLocal(String srcPath) async {
    // 获取应用文档目录并确保 LocalAudio 目录存在
    final appDir = await appDocDir;
    final destDir = Directory(path.join(appDir.path, 'LocalAudio'));
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    // 中文注释：目标文件名与路径，处理重名冲突
    final fileName = path.basename(srcPath);
    final baseName = path.basenameWithoutExtension(fileName);
    final ext = path.extension(fileName);
    String destPath = path.join(destDir.path, fileName);

    if (await File(destPath).exists()) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      destPath = path.join(destDir.path, '${baseName}_$ts$ext');
    }

    // 中文注释：尝试 rename（更快），失败则 copy + delete
    final srcFile = File(srcPath);
    try {
      await srcFile.rename(destPath);
      return destPath;
    } catch (_) {
      await srcFile.copy(destPath);
      await srcFile.delete();
      return destPath;
    }
  }

  // 修改：翻译音频导入支持归档到 LocalAudio（智能转写默认归档以隐藏原翻译目录）
  void addTranslatAudio({bool archiveToLocal = true}) async {
    EasyLoading.show(status: 'batchImporting'.tr); // 对应中文：正在批量导入...
    for (final originalPath in selected) {
      try {
        // 中文注释：根据开关决定是否将翻译音频迁移到 LocalAudio
        final usePath = archiveToLocal
            ? await _archiveTranslatToLocal(originalPath)
            : originalPath;

        // 中文注释：计算音频时长与创建时间
        await _audioPlayer.setAudioSource(AudioSource.file(usePath));
        final fileStat = await File(usePath).stat();
        final creationTime = fileStat.changed.millisecondsSinceEpoch;
        final seconds = _audioPlayer.duration?.inSeconds ?? 0;
        final fileName = path.basename(usePath);

        // 中文注释：归档则统一标记为 LOCAL，未归档则保留 TRANSLAT
        final String recordType = archiveToLocal ? 'LOCAL' : 'TRANSLAT';

        // 中文注释：写入数据库
        final Map<String, Object?> data = {
          'title': fileName,
          'type': recordType,
          'seconds': seconds,
          'filepath': usePath,
          'audiourl': '',
          'tasktype': 0,
          'creationtime': creationTime,
        };

        final response = await Api.addRecordEchomeet({
          'rtype': recordType,
          'size': fileStat.size,
          ...data,
        });
        final meetingId = _extractMeetingId(response, 'addAudio');
        if (meetingId <= 0) {
          continue;
        }
        final meetingResult = await SqfliteApi.insertMeeting({
          'id': meetingId,
          ...data,
        });
        if (meetingResult != null) {
          // 中文注释：上传分类按目录区分
          final uploadBucket = archiveToLocal ? 'LocalAudio' : 'TranslatAudio';
          meetingUploadService.addUpload(meetingId, usePath, uploadBucket);

          // 中文注释：更新列表（保持现有排序逻辑）
          final record = {'id': meetingId, ...data};
          originalDataList.insert(0, record);
          if (isAsc) {
            dataList.add(record);
          } else {
            dataList.insert(0, record);
          }
        }
      } catch (e) {
        Logger.error('importFailed'
            .tr
            .replaceAll('{filePath}', originalPath)
            .replaceAll('{error}',
                e.toString())); // 对应中文：导入文件失败: {filePath}, error: {error}
      }
    }
    EasyLoading.dismiss();
  }

  void addAudio([String? filePath]) async {
    EasyLoading.show(status: 'importing'.tr); // 对应中文：正在导入...
    String fileName = "";
    bool isParamProvided = filePath != null; // 更清晰的变量名
    String audioType = 'IMPORT'; // 默认类型为IMPORT
    String effectivePath = filePath ?? '';
    if (filePath != null) {
      // 正确截取文件名（跨平台安全方式）
      fileName = path.basename(filePath);
      // 检查是否来自翻译模块（兼容不同平台路径分隔符）
      final isFromTranslat = filePath.contains('/TranslatAudio/') ||
          filePath.contains('\\TranslatAudio\\');
      if (isFromTranslat) {
        try {
          // 实现——导入前将翻译音频归档到LocalAudio
          effectivePath = await _archiveTranslatToLocal(filePath);
          audioType = 'TRANSLAT'; // 归档后统一标记为TRANSLAT类型
          fileName = path.basename(effectivePath);
        } catch (e) {
          // 归档失败则回退为原路径、保持TRANSLAT类型以避免中断导入
          audioType = 'TRANSLAT';
          effectivePath = filePath;
          Logger.error('importFailed'
              .tr
              .replaceAll('{filePath}', filePath)
              .replaceAll('{error}',
                  e.toString())); // 对应中文：导入文件失败: {filePath}, error: {error}
        }
      } else {
        effectivePath = filePath;
      }
    } else {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        withData: false,
        //type: FileType.audio,
        allowMultiple: false,
      );
      if (result != null) {
        PlatformFile file = result.files.first;

        if (!_isAudioFile(file.name)) {
          Get.snackbar(
            'error'.tr, // 错误
            'pleaseSelectAudioFile'.tr, // 对应中文：请选择音频文件
            snackPosition: SnackPosition.TOP,
            backgroundColor: Colors.red.withOpacity(0.1),
            colorText: Colors.red,
          );
          EasyLoading.dismiss();
          return;
        }

        // 使用文件路径而不是字节数据
        effectivePath = file.path ?? await _copyFileToLocal(file);
        fileName = file.name;
      } else {
        EasyLoading.dismiss();
        return;
      }
    }

    final meetingId =
        await insertMeetingAudio(fileName, effectivePath, type: audioType);

    if (isParamProvided) {
      final int safeId = meetingId is int
          ? meetingId
          : (meetingId is num ? meetingId.toInt() : 0);
      if (safeId > 0) {
        Get.to(
          () => const MeetingDetailsView(),
          binding: MeetingDetailsBinding(id: safeId),
          arguments: {'id': safeId},
        );
      }
    }
    EasyLoading.dismiss();
  }

  Future insertMeetingAudio(
    String fileName,
    String filePath, {
    bool isUpload = true,
    String type = 'IMPORT', //添加type参数，默认为'IMPORT'
  }) async {
    await _audioPlayer.setAudioSource(AudioSource.file(filePath));
    int seconds = _audioPlayer.duration?.inSeconds ?? 0;
    int creationTime = DateTime.now().millisecondsSinceEpoch;
    final fileStat = await File(filePath).stat();
    Map<String, Object?> data = {
      'title': fileName,
      'type': type, // 使用传入的type参数
      'seconds': seconds,
      'filepath': filePath,
      'audiourl': '',
      'tasktype': 0,
      'creationtime': creationTime,
    };
    final response = await Api.addRecordEchomeet({
      'rtype': type,
      'size': fileStat.size,
      ...data,
    });
    final meetingId = _extractMeetingId(response, 'insertMeetingAudio');
    if (meetingId <= 0) {
      EasyLoading.showError('服务端未返回会议 id，已取消');
      return null;
    }
    final meetingResult = await SqfliteApi.insertMeeting({
      'id': meetingId,
      ...data,
    });
    if (meetingResult != null) {
      // 中文注释：根据类型选择上传分类；LOCAL 走 LocalAudio，其它走 ExternalAudio
      final uploadBucket = type == 'LOCAL' ? 'LocalAudio' : 'ExternalAudio';
      meetingUploadService.addUpload(
        meetingId,
        filePath,
        uploadBucket,
        isUpload: isUpload,
      );
      originalDataList.insert(0, {
        'id': meetingId,
        ...data,
      });
      if (isAsc) {
        dataList.add({
          'id': meetingId,
          ...data,
        });
      } else {
        dataList.insert(0, {
          'id': meetingId,
          ...data,
        });
      }
    }
    return meetingId;
  }

  // 新增：流式复制文件方法
  Future<String> _copyFileToLocal(PlatformFile file) async {
    final directory = await getApplicationDocumentsDirectory();
    final directoryDir = Directory('${directory.path}/ExternalAudio');
    if (!await directoryDir.exists()) {
      await directoryDir.create(recursive: true);
    }

    final String targetPath = '${directory.path}/ExternalAudio/${file.name}';

    if (file.path != null) {
      // 如果有原始路径，直接复制文件
      final sourceFile = File(file.path!);
      await sourceFile.copy(targetPath);
    } else {
      // 如果没有路径，使用流式写入（分块处理）
      final targetFile = File(targetPath);
      final sink = targetFile.openWrite();

      try {
        // 分块写入，避免一次性加载大文件到内存
        const chunkSize = 1024 * 1024; // 1MB chunks
        final bytes = file.bytes!;

        for (int i = 0; i < bytes.length; i += chunkSize) {
          final end =
              (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
          sink.add(bytes.sublist(i, end));

          // 给UI线程一些时间处理其他任务
          await Future.delayed(Duration(milliseconds: 1));
        }
      } finally {
        await sink.close();
      }
    }

    return targetPath;
  }

  // 移除原来的_saveFile方法，替换为上面的_copyFileToLocal
  // Future<String> _saveFile(PlatformFile file) async {
  //   final directory = await getApplicationDocumentsDirectory();
  //   final directoryDir = Directory('${directory.path}/ExternalAudio');
  //   if (!await directoryDir.exists()) {
  //     await directoryDir.create(recursive: true);
  //   }
  //   final String filePath = '${directory.path}/ExternalAudio/${file.name}';
  //   final File localFile = File(filePath);
  //   await localFile.writeAsBytes(file.bytes!);
  //   return filePath;
  // }

  // 修改标题
  void editMeetingTitle(int id) async {
    if (titleController.text.isNotEmpty) {
      String title = titleController.text + titleCSuffix;
      Api.modifyRecordEchomeet({'id': id, 'title': title});
      SqfliteApi.editMeetingTitle(id, {'title': title});
      int originalIndex =
          originalDataList.indexWhere((item) => item['id'] == id);
      int index = dataList.indexWhere((item) => item['id'] == id);
      if (originalIndex != -1) {
        final dataMap =
            Map<String, dynamic>.from(originalDataList[originalIndex]);
        dataMap['title'] = title;
        originalDataList[originalIndex] = dataMap;
      }
      if (index != -1) {
        final dataMap = Map<String, dynamic>.from(dataList[index]);
        dataMap['title'] = title;
        dataList[index] = dataMap;
      }
    }
    Get.back();
  }

  // 删除数据
  void deleteMeeting(int id, String filepath) async {
    originalDataList.removeWhere((item) => item['id'] == id);
    dataList.removeWhere((item) => item['id'] == id);
    // 删除数据库中的记录
    SqfliteApi.deleteMeeting(id);
    _deleteFile(filepath);
    meetingUploadService.removeUpload(id, isDeleteTask: true);
    meetingTaskService.removeTask(id);
  }

  // 删除文件
  Future<void> _deleteFile(String filepath) async {
    File file = File(filepath);
    bool fileExists = await file.exists();
    if (fileExists) {
      await file.delete();
    }
  }

  bool _isAudioFile(String fileName) {
    const List audioExtensions = ['.mp3', '.wav', '.m4a', '.aac'];
    final extension = path.extension(fileName).toLowerCase();
    return audioExtensions.contains(extension);
  }

  /// 安全提取 `Api.addRecordEchomeet` 返回的会议 id。服务端协议正常路径
  /// 是 `{record:{id:N}}`，但响应可能因网络/版本兼容缺字段——这里把所有
  /// 异常情况都打日志、统一返回 0 让调用方决定怎么回退。
  int _extractMeetingId(dynamic response, String tag) {
    if (response is! Map) {
      Logger.e('MeetingHomeController',
          '$tag: addRecordEchomeet response not a Map: ${response.runtimeType} $response');
      return 0;
    }
    final record = response['record'];
    if (record is! Map) {
      Logger.e('MeetingHomeController',
          '$tag: addRecordEchomeet response missing record: $response');
      return 0;
    }
    final raw = record['id'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    Logger.e('MeetingHomeController',
        '$tag: record id is not int-like: $raw (${raw.runtimeType}) record=$record');
    return 0;
  }
}
