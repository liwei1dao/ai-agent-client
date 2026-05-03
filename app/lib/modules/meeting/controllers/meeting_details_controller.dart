import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../legacy_stubs/audio_session.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/services/api_client.dart';
import '../../../core/services/log_service.dart';
import '../../../core/utils/logger.dart';
import '../../../data/services/db/sqflite_api.dart';
import '../../../data/services/meeting/meeting_task_service.dart';
import '../../../data/services/meeting/meeting_upload_service.dart';
import '../../../data/services/network/api.dart';
import '../model/meeting_details_model.dart';
import '../model/meeting_model.dart';

/// 会议详情控制器
class MeetingDetailsController extends GetxController
    with GetTickerProviderStateMixin {
  MeetingDetailsController({this.injectedId = 0});

  /// Binding 闭包注入的 id —— 优先级高于 `Get.arguments['id']`。
  final int injectedId;

  late TabController tabController;
  final RxInt currentIndex = 0.obs;

  late AnimationController lottieController;

  late final Worker _tasktypeListener;

  final _meetingUploadService = Get.find<MeetingUploadService>();
  final _meetingTaskService = Get.find<MeetingTaskService>();

  final PlayerController playerController = PlayerController();

  StreamSubscription? _currentDurationSubscription;
  StreamSubscription? _playerStateSubscription;

  RxBool isTop = false.obs;
  RxInt durationMax = 0.obs;
  RxDouble dragOffset = 210.w.obs;

  RxBool isPlay = false.obs;
  RxInt currentDuration = 0.obs;

  // 播放器准备状态
  RxBool isPlayerReady = false.obs;

  RxInt speakerAllStarttime = (-1).obs;
  RxInt speakerAllEndtime = (-1).obs;

  int id = 0;

  RxBool isLoading = true.obs;
  Rx<MeetingModel> meetingData = MeetingModel().obs;
  Rx<MeetingDetailsModel> meetingDetails = MeetingDetailsModel().obs;
  RxList textList = [].obs;
  RxBool isSpeakerText = false.obs;
  List editSpeakerTextList = [];
  RxInt editSpeakerTextId = 0.obs;
  String editSpeakerTextChange = '';

  int _everType = 99999;
  RxInt summaryNumberModifications = 0.obs;
  RxInt personnelNumberModifications = 0.obs;

  String markmapLibJs = '';
  String d3Js = '';
  String markmapViewJs = '';
  String markmapToolbarJs = '';
  String saveSvgAsPngJs = '';

  RxBool isDownload = false.obs;
  RxDouble downloadProgress = 0.0.obs;

  List categoryTemplateList = [];
  Map editTemplate = {};
  int deleteTemplateId = 0;

  @override
  void onInit() {
    super.onInit();
    tabController = TabController(length: 4, vsync: this);
    tabController.addListener(() {
      if (currentIndex.value == 2 && tabController.index != 2) {
        FocusScope.of(Get.context!).unfocus();
      }
      currentIndex.value = tabController.index;
    });
    lottieController = AnimationController(vsync: this)
      ..duration = const Duration(seconds: 2);
    // 优先使用 binding 闭包注入的 id；GoRouter+GetX 桥接模式下
    // `Get.arguments` 经常拿不到，binding 注入是可靠路径。
    if (injectedId > 0) {
      id = injectedId;
    } else {
      final Map<String, dynamic> args = (Get.arguments is Map)
          ? Map<String, dynamic>.from(Get.arguments)
          : {};
      final dynamic rawId = args['id'];
      if (rawId is int) {
        id = rawId;
      } else if (rawId is num) {
        id = rawId.toInt();
      } else if (rawId is String) {
        id = int.tryParse(rawId) ?? 0;
      } else {
        id = 0;
      }
    }
    if (id <= 0) {
      Logger.e('MeetingDetailsController',
          'invalid id: injectedId=$injectedId getArgs=${Get.arguments}');
      LogService.instance.talker.info(
          '[MeetingDetailsController] INVALID id: injectedId=$injectedId '
          'getArgs=${Get.arguments}');
    } else {
      Logger.i('MeetingDetailsController', 'opened meeting id=$id');
      LogService.instance.talker
          .info('[MeetingDetailsController] opened meeting id=$id');
    }
    _meetingTaskService.meetingId = id;
    _getDataDetails();
    _loadJS();
    _tasktypeListener = ever(_meetingTaskService.tasktype, (value) {
      meetingDetails.value.tasktype = value;
      if (_everType <= value) {
        if (value >= 3 && value < 10000) {
          textList.value = _meetingTaskService.textList;
        }
        if (value >= 5 && value < 10000) {
          meetingDetails.value.personnel = _meetingTaskService.personnel;
          meetingDetails.value.summary = _meetingTaskService.summary;
          meetingDetails.value.overview = _meetingTaskService.overview;
          summaryNumberModifications.value++;
        }
      }
      meetingDetails.refresh();
    });
  }

  @override
  void onClose() {
    _tasktypeListener.dispose();
    _currentDurationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    tabController.dispose();
    playerController.dispose();
    lottieController.dispose();
    super.onClose();
  }

  void popInvokedWithResult(didPop, result) async {
    _meetingUploadService.removeUpload(id);
    _meetingTaskService.meetingId = 0;
  }

  void _getDataDetails() async {
    final data = await SqfliteApi.getMeetingDetails(id);
    meetingData.value = MeetingModel.fromJson(Map<String, dynamic>.from(data));
    final dynamic detailsRaw = data['details'];
    meetingDetails.value = MeetingDetailsModel.fromJson(
      detailsRaw is Map ? Map<String, dynamic>.from(detailsRaw) : <String, dynamic>{},
    );
    _everType = meetingDetails.value.tasktype + 1;
    _meetingTaskService.tasktype.value = meetingDetails.value.tasktype;
    if (meetingDetails.value.tasktype == 5) {
      await _meetingTaskService.readTask(id);
    }
    if (meetingDetails.value.tasktype >= 5 &&
        meetingDetails.value.tasktype < 10000) {
      dragOffset.value = 0;
      isTop.value = true;
    }
    if (meetingData.value.filepath.isNotEmpty) {
      await _loadPlayerController();
    }
    if (meetingDetails.value.tasktype >= 3 &&
        meetingDetails.value.tasktype < 10000) {
      List speakerList = await SqfliteApi.getMeetingSpeaker(id);
      textList.value = List.from(speakerList);
    }
    isLoading.value = false;
  }

  Future<void> _loadPlayerController() async {
    try {
      final filepath = meetingData.value.filepath;

      // 验证文件路径
      if (filepath.isEmpty) {
        Logger.error('音频文件路径为空，无法加载播放器');
        isPlayerReady.value = false;
        return;
      }

      // 验证文件是否存在
      final file = File(filepath);
      if (!await file.exists()) {
        Logger.error('音频文件不存在: $filepath');
        isPlayerReady.value = false;
        // 本地文件缺失：若云端存在音频，清空本地路径并持久化，
        // 让 UI 自动切换为"下载"按钮，下载完成后即可播放；
        // 仅当云端也没有音频时才提示文件不存在
        if (meetingData.value.audiourl.isNotEmpty) {
          Logger.d('MeetingDetails', '本地音频缺失，切换为下载态（云端URL可用）');
          meetingData.value.filepath = '';
          meetingData.refresh();
          await SqfliteApi.editMeetingTitle(id, {'filePath': ''});
        } else {
          Get.snackbar(
            'error'.tr,
            'audioFileNotFound'.tr, // 音频文件不存在
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 3),
          );
        }
        return;
      }

      Logger.d('MeetingDetails', '开始加载音频播放器: $filepath');

      // iOS平台特殊处理：配置音频会话
      if (Platform.isIOS) {
        try {
          Logger.d('MeetingDetails', 'iOS平台：开始配置音频会话');
          final session = await AudioSession.instance;
          await session.configure(const AudioSessionConfiguration(
            avAudioSessionCategory: AVAudioSessionCategory.playback,
            avAudioSessionCategoryOptions:
                AVAudioSessionCategoryOptions.mixWithOthers,
            avAudioSessionMode: AVAudioSessionMode.defaultMode,
            avAudioSessionRouteSharingPolicy:
                AVAudioSessionRouteSharingPolicy.defaultPolicy,
            avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
            androidAudioAttributes: AndroidAudioAttributes(
              contentType: AndroidAudioContentType.music,
              usage: AndroidAudioUsage.media,
            ),
            androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
            androidWillPauseWhenDucked: true,
          ));
          Logger.d('MeetingDetails', 'iOS平台：音频会话配置成功');
        } catch (e) {
          Logger.error('iOS平台：音频会话配置失败: $e');
          // 继续执行，尝试播放
        }
      }

      // 准备播放器
      await playerController.preparePlayer(
        path: filepath,
        shouldExtractWaveform: false,
        noOfSamples: 88,
      );

      // 获取音频时长
      final duration = await playerController.getDuration(DurationType.max);
      // 校验时长有效性，防止无效值导致 DateUtil.formatDateMs 报错
      // 有效的毫秒时间戳应该在合理范围内（大于0且小于未来100年）
      const int maxValidDuration = 315360000000; // 约10年的毫秒数
      if (duration > 0 && duration < maxValidDuration) {
        durationMax.value = duration;
      } else {
        durationMax.value = 0;
        Logger.w('MeetingDetails', '获取到无效的音频时长: $duration，已重置为0');
      }

      Logger.d('MeetingDetails', '音频播放器加载成功，时长: ${durationMax.value}ms');

      // 设置播放完成模式
      playerController.setFinishMode(finishMode: FinishMode.pause);

      // 监听播放进度
      _currentDurationSubscription =
          playerController.onCurrentDurationChanged.listen((int position) {
        currentDuration.value = position;
        if (speakerAllEndtime.value > 0) {
          if (position >= speakerAllEndtime.value) {
            playerController.pausePlayer();
            speakerAllStarttime.value = -1;
            speakerAllEndtime.value = -1;
          }
        }
      });

      // 监听播放状态
      _playerStateSubscription = playerController.onPlayerStateChanged
          .listen((PlayerState playerState) {
        isPlay.value = playerState.isPlaying;
        if (playerState.isPlaying) {
          lottieController.repeat();
        } else {
          lottieController.stop();
        }
      });

      // 标记播放器已准备好
      isPlayerReady.value = true;
    } catch (e, stackTrace) {
      Logger.error('加载音频播放器失败: $e');
      Logger.error('堆栈跟踪: $stackTrace');
      isPlayerReady.value = false;

      Get.snackbar(
        'error'.tr,
        'playerLoadFailed'.tr, // 音频播放器加载失败
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 3),
      );
    }
  }

  void _loadJS() async {
    // 这些 JS 是给 markmap webview 用的，缺失只会让思维导图渲染不出来，
    // 不应该把整个详情页冒泡成 PlatformDispatcher error。
    Future<String> tryLoad(String path) async {
      try {
        return await rootBundle.loadString(path);
      } catch (e) {
        Logger.warning('asset missing: $path ($e)');
        return '';
      }
    }

    markmapLibJs = await tryLoad('assets/js/markmap-lib.js');
    d3Js = await tryLoad('assets/js/d3@7.js');
    markmapViewJs = await tryLoad('assets/js/markmap-view.js');
    markmapToolbarJs = await tryLoad('assets/js/markmap-toolbar.js');
    saveSvgAsPngJs = await tryLoad('assets/js/saveSvgAsPng.min.js');
  }

  void downloadAudio() async {
    if (isDownload.value) return;
    isDownload.value = true;
    final directory = await getApplicationDocumentsDirectory();
    final directoryDir = Directory('${directory.path}/DownloadAudio');
    if (!await directoryDir.exists()) {
      await directoryDir.create(recursive: true);
    }
    final fileName = meetingData.value.audiourl.split('/').last;
    final String filePath = '${directory.path}/DownloadAudio/$fileName';
    await Dio().download(
      meetingData.value.audiourl,
      filePath,
      onReceiveProgress: (int received, int total) {
        downloadProgress.value = total > 0 ? received / total : 0.0;
      },
    );
    meetingData.value.filepath = filePath;
    meetingData.refresh();
    _loadPlayerController();
    SqfliteApi.editMeetingTitle(id, {'filePath': filePath});
    isDownload.value = false;
  }

  /// 从云端下载音频文件（用于分享/导出场景）
  /// 与 [downloadAudio] 的区别：有返回值，便于调用方判断是否成功
  ///
  /// 返回值：下载成功的本地文件路径；失败时返回 null
  Future<String?> downloadAudioForShare() async {
    final audioUrl = meetingData.value.audiourl;
    if (audioUrl.isEmpty) {
      Logger.error('云端音频URL为空，无法从云端下载');
      return null;
    }
    try {
      final directory = await getApplicationDocumentsDirectory();
      final directoryDir = Directory('${directory.path}/DownloadAudio');
      if (!await directoryDir.exists()) {
        await directoryDir.create(recursive: true);
      }
      final fileName = audioUrl.split('/').last;
      final String filePath = '${directory.path}/DownloadAudio/$fileName';
      await Dio().download(
        audioUrl,
        filePath,
        onReceiveProgress: (int received, int total) {
          downloadProgress.value = total > 0 ? received / total : 0.0;
        },
      );
      // 更新本地路径并持久化
      meetingData.value.filepath = filePath;
      meetingData.refresh();
      SqfliteApi.editMeetingTitle(id, {'filePath': filePath});
      // 若播放器尚未初始化，顺带加载（异步，不阻塞分享流程）
      if (!isPlayerReady.value) {
        _loadPlayerController();
      }
      Logger.d('MeetingDetails', '云端音频下载成功: $filePath');
      return filePath;
    } catch (e) {
      Logger.error('从云端下载音频失败: $e');
      return null;
    }
  }

  void editSpeakerText() async {
    if (editSpeakerTextId.value != 0 && editSpeakerTextChange.isNotEmpty) {
      Map? foundElement = editSpeakerTextList.firstWhere(
        (element) => element['id'] == editSpeakerTextId.value,
        orElse: () => null,
      );
      if (foundElement != null) {
        foundElement['content'] = editSpeakerTextChange;
      } else {
        editSpeakerTextList.add({
          'id': editSpeakerTextId.value,
          'content': editSpeakerTextChange,
        });
      }
    }
    if (editSpeakerTextList.isNotEmpty) {
      EasyLoading.show();
      var result = await SqfliteApi.editMeetingSpeaker(editSpeakerTextList);
      if (result != null) {
        for (var element in editSpeakerTextList) {
          int index =
              textList.indexWhere((item) => item['id'] == element['id']);
          if (index != -1) {
            final dataMap = Map<String, dynamic>.from(textList[index]);
            dataMap['content'] = element['content'];
            textList[index] = dataMap;
          }
        }
        await Api.modifyRecordEchomeet({
          'id': id,
          'translate': jsonEncode(textList),
        });
        isSpeakerText.value = false;
        editSpeakerTextId.value = 0;
        editSpeakerTextList = [];
      }
      EasyLoading.dismiss();
    } else {
      isSpeakerText.value = false;
      editSpeakerTextId.value = 0;
      editSpeakerTextList = [];
    }
  }

  void summaryCreate(
    String formlanguage,
    String tolanguage,
    bool isdistinguishspeaker,
    int templateid,
    String tid,
  ) async {
    LogService.instance.talker.info(
        '[MeetingDetailsController] summaryCreate id=$id '
        'audiourl=${meetingData.value.audiourl} '
        'templateid=$templateid tid=$tid');
    if (id <= 0) {
      EasyLoading.showError('会议 id 无效，无法发起任务');
      return;
    }
    EasyLoading.show();
    _everType = 2;
    final String audiourl = meetingData.value.audiourl;
    try {
      await _meetingTaskService.addTask(
        id,
        audiourl,
        formlanguage,
        tolanguage,
        isdistinguishspeaker,
        templateid,
        tid,
      );
      meetingDetails.value.tasktype = 1;
      meetingDetails.refresh();
      EasyLoading.dismiss();
    } catch (e) {
      // 服务端业务错误（积分不足 / record not found 等）：
      //   - submitTask 已把 DB 回滚成 tasktype=0
      //   - 这里把 in-memory 状态也回滚，避免 UI 停在"撰写中"
      //   - 然后用 snackbar 把服务端 message 透传给用户
      meetingDetails.value.tasktype = 0;
      meetingDetails.refresh();
      EasyLoading.dismiss();
      final msg = (e is ApiException) ? e.message : e.toString();
      Get.snackbar('生成失败', msg, snackPosition: SnackPosition.TOP);
    }
  }

  void refreshSummary(int templateid, String tid, String tolanguage) async {
    LogService.instance.talker.info(
        '[MeetingDetailsController] refreshSummary id=$id '
        'templateid=$templateid tid=$tid');
    if (id <= 0) {
      EasyLoading.showError('会议 id 无效，无法刷新总结');
      return;
    }
    final int previousType = meetingDetails.value.tasktype;
    EasyLoading.show();
    _everType = 4;
    try {
      await _meetingTaskService.refreshTask(id, templateid, tid, tolanguage);
      meetingDetails.value.tasktype = 3;
      meetingDetails.refresh();
      EasyLoading.dismiss();
    } catch (e) {
      meetingDetails.value.tasktype = previousType;
      meetingDetails.refresh();
      EasyLoading.dismiss();
      final msg = (e is ApiException) ? e.message : e.toString();
      Get.snackbar('刷新失败', msg, snackPosition: SnackPosition.TOP);
    }
  }
}
