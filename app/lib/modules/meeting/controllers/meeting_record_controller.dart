// meeting_record_controller.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import '../../../core/utils/logger.dart';
import '../../../core/utils/overlay_permission_util.dart';
import '../../../core/utils/permission_util.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../../legacy_stubs/floating_ui_plugin.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../legacy_stubs/flutter_local_notifications.dart';
import '../bindings/meeting_record_binding.dart';
import '../views/meeting_record_view.dart';
import '../../../data/services/asr_service.dart';
import '../../../data/services/ble_manager.dart';
import '../../../data/services/meeting/meeting_task_service.dart';

/// 会议记录状态枚举
enum TimerStatus {
  stopped, // 停止
  running, // 运行中
  paused, // 暂停
}

/// 会议记录控制器
/// 负责会议记录的状态管理、音频处理、语音识别和UI交互
class MeetingRecordController extends GetxController
    with GetTickerProviderStateMixin, WidgetsBindingObserver {
  static const int _backgroundRecordingNotificationId = 91001;
  static const Duration _stopRecordTimeout = Duration(seconds: 12);
  static const Duration _fileOpTimeout = Duration(seconds: 8);

  static FlutterLocalNotificationsPlugin? _localNotificationsPlugin;
  final NativePlugin _nativePlugin = NativePlugin();

  static String sanitizeRecordingFileStem(
    String input, {
    String fallback = 'recording',
  }) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return fallback;

    var safe = trimmed
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'[\u0000-\u001F]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_');

    safe = safe.replaceAll(RegExp(r'^\.+'), '');
    safe = safe.replaceAll(RegExp(r'^_+|_+$'), '');

    if (safe.isEmpty) return fallback;
    if (safe.length > 80) {
      safe = safe.substring(0, 80);
    }
    return safe;
  }

  String _defaultRecordingFileStem() {
    switch (audioType.value) {
      case 0:
        return 'live_recording';
      case 1:
        return 'audio_video_recording';
      case 2:
        return 'call_recording';
      default:
        return 'recording';
    }
  }

  Timer? _recordingFloatingBarTimer;
  Timer? _routeMonitorTimer;
  StreamSubscription<String>? _recordingFloatingActionSubscription;
  bool _floatingBarManuallyClosed = false;
  bool _overlayPermissionPromptedThisSession = false;
  bool _overlayPermissionSnackShownThisSession = false;
  bool _overlayPermissionRequesting = false;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  String _lastKnownRoute = '';

  OverlayEntry? _recordingInAppOverlay;
  Offset? _recordingInAppOverlayOffset;

  Future<FlutterLocalNotificationsPlugin>
      _ensureLocalNotificationsPlugin() async {
    final existing = _localNotificationsPlugin;
    if (existing != null) return existing;

    final plugin = FlutterLocalNotificationsPlugin();
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await plugin.initialize(settings);
    _localNotificationsPlugin = plugin;
    return plugin;
  }

  Future<void> _requestNotificationPermissionIfNeeded() async {
    await PermissionUtil.instance.requestPermission(
      permissionType: Permission.notification,
      permissionName: 'notificationPermission'.tr,
      explanationText: 'notificationPermissionExplanation'.tr,
      permanentDenialText: 'notificationPermissionPermanentDenial'.tr,
      settingsButtonText: 'goToSettings'.tr,
      cancelButtonText: 'cancel'.tr,
    );
  }

  Future<void> showBackgroundRecordingIndicator() async {
    if (Platform.isAndroid) {
      if (_floatingBarManuallyClosed) return;
      await _startAndroidRecordingFloatingBar();
      return;
    }

    await _requestNotificationPermissionIfNeeded();
    if (!Platform.isIOS) return;

    if (_floatingBarManuallyClosed) return;
    if (_appLifecycleState == AppLifecycleState.resumed) {
      await _showInAppRecordingOverlay();
      return;
    }

    _hideInAppRecordingOverlay();
    final plugin = await _ensureLocalNotificationsPlugin();
    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false,
      ),
    );

    await plugin.show(
      _backgroundRecordingNotificationId,
      'meetingRecordRecordingNotificationTitle'.tr,
      'meetingRecordRecordingNotificationBody'.tr,
      details,
    );
  }

  Future<void> clearBackgroundRecordingIndicator() async {
    if (Platform.isAndroid) {
      _floatingBarManuallyClosed = false;
      await _stopAndroidRecordingFloatingBar();
      return;
    }
    if (!Platform.isIOS) return;
    final plugin = await _ensureLocalNotificationsPlugin();
    await plugin.cancel(_backgroundRecordingNotificationId);
    _floatingBarManuallyClosed = false;
    _hideInAppRecordingOverlay();
  }

  String _formatTimeForFloatingBar(int ms) {
    final totalSeconds = ms ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final secs = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _getRecordingTypeText() {
    switch (audioType.value) {
      case 0:
        return 'liveRecording'.tr;
      case 1:
        return 'audioVideoRecording'.tr;
      case 2:
        return 'callRecording'.tr;
      default:
        return 'liveRecording'.tr;
    }
  }

  Future<void> _startAndroidRecordingFloatingBar() async {
    if (!Platform.isAndroid) return;
    if (!isRecording.value) return;
    if (_floatingBarManuallyClosed) return;

    final granted = await _ensureAndroidOverlayPermissionForFloatingBar();
    if (!granted) return;

    final typeText = _getRecordingTypeText();
    final durationText = _formatTimeForFloatingBar(milliseconds.value);

    try {
      await _nativePlugin
          .showRecordingFloatingBar(
            duration: durationText,
            recordingType: typeText,
            isPaused: timerStatus.value == TimerStatus.paused,
          )
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      Logger.error('显示录音悬浮条失败: ${e.toString()}');
      return;
    }

    _recordingFloatingBarTimer?.cancel();
    _recordingFloatingBarTimer =
        Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isRecording.value) {
        unawaited(_stopAndroidRecordingFloatingBar());
        return;
      }
      _nativePlugin.updateRecordingFloatingBar(
        duration: _formatTimeForFloatingBar(milliseconds.value),
        recordingType: _getRecordingTypeText(),
        isPaused: timerStatus.value == TimerStatus.paused,
      );
    });
  }

  void _showOverlayPermissionSnackOnce() {
    if (_overlayPermissionSnackShownThisSession) return;
    _overlayPermissionSnackShownThisSession = true;
    Get.snackbar(
      'overlayPermissionTitle'.tr,
      'overlayPermissionRecordingDesc'.tr,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 4),
      mainButton: TextButton(
        onPressed: () {
          unawaited(OverlayPermissionUtil.openOverlayPermissionSettings());
        },
        child: Text('goToSettings'.tr),
      ),
    );
  }

  Future<bool> _ensureAndroidOverlayPermissionForFloatingBar() async {
    if (!Platform.isAndroid) return true;
    if (!isRecording.value) return false;

    final hasPermission = await OverlayPermissionUtil.hasOverlayPermission();
    if (hasPermission) return true;

    if (_appLifecycleState != AppLifecycleState.resumed) {
      return false;
    }

    if (_overlayPermissionPromptedThisSession || _overlayPermissionRequesting) {
      _showOverlayPermissionSnackOnce();
      return false;
    }

    _overlayPermissionPromptedThisSession = true;
    _overlayPermissionRequesting = true;
    try {
      final granted = await OverlayPermissionUtil.requestOverlayPermission(
        scene: OverlayPermissionScene.recordingFloatingBar,
      );
      if (!granted) {
        _showOverlayPermissionSnackOnce();
      }
      return granted;
    } finally {
      _overlayPermissionRequesting = false;
    }
  }

  Future<void> _stopAndroidRecordingFloatingBar() async {
    if (!Platform.isAndroid) return;
    _recordingFloatingBarTimer?.cancel();
    _recordingFloatingBarTimer = null;
    try {
      await _nativePlugin
          .hideRecordingFloatingBar()
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      Logger.error('隐藏录音悬浮条失败: ${e.toString()}');
    }
  }

  Future<void> togglePauseResumeFromFloatingBar() async {
    if (!isRecording.value) return;
    if (timerStatus.value == TimerStatus.running) {
      await _pauseRecording();
      return;
    }
    if (timerStatus.value == TimerStatus.paused) {
      await _resumeRecording();
    }
  }

  void _setupRecordingFloatingBarActionListener() {
    _recordingFloatingActionSubscription?.cancel();
    if (!Platform.isAndroid) return;
    _recordingFloatingActionSubscription =
        _nativePlugin.recordingFloatingActionStream.listen((action) async {
      if (action.isEmpty) return;
      switch (action) {
        case 'togglePause':
          await togglePauseResumeFromFloatingBar();
          return;
        case 'openMeetingRecord':
          _floatingBarManuallyClosed = false;
          if (Get.currentRoute == '/meeting/record') return;
          Get.to(
            () => const MeetingRecordView(),
            binding: MeetingRecordBinding(),
            arguments: {'audioTypes': audioType.value},
          );
          return;
        case 'closeFloatingBar':
          if (isRecording.value) {
            final saved = await saveRecording();
            if (saved && Get.isRegistered<MeetingTaskService>()) {
              Get.find<MeetingTaskService>().requestLocalImport();
            }
            return;
          }
          _floatingBarManuallyClosed = true;
          await _stopAndroidRecordingFloatingBar();
          return;
        default:
          return;
      }
    });
  }

  // 服务
  final AsrService _asrService = Get.find<AsrService>();
  final BleManager _bleManager = Get.find<BleManager>();

  // 流订阅
  StreamSubscription? _recognitionSubscription;

  // 记录状态
  final Rx<TimerStatus> timerStatus = TimerStatus.stopped.obs;
  final RxInt seconds = 0.obs;
  final RxInt milliseconds = 0.obs;
  final RxInt audioType = 0.obs; // 0=Live, 1=Media, 2=Call
  final RxBool isMarked = false.obs;
  final RxBool showTextContent = false.obs;
  final RxBool isRecording = false.obs;
  final RxBool isSaving = false.obs;
  //final RxBool isVoiceRecognitionActive = false.obs;
  final RxDouble rms = 0.0.obs;

  final RecorderController waveformController = RecorderController();

  // 转写内容
  final RxString intermediateContent = ''.obs;
  final RxString finalContent = ''.obs;

  // File management
  final RxString fileName = "初始文件名".obs;
  final RxString newName = "".obs;
  final RxBool isEditingTitle = false.obs;
  late TextEditingController titleEditingController;
  late FocusNode titleFocusNode;
  final Future<Directory> appDocDir = getApplicationDocumentsDirectory();

  // 计时变量
  Timer? _timer;
  int _elapsedMilliseconds = 0;
  int? _lastStartTime;
  // 移除了未使用的变量和TabController

  StreamSubscription<Uint8List>? _audioDataSubscription;
  double _smoothedRms = 0.0;
  double _latestRms = 0.0;
  Timer? _waveformTimer;
  static const Duration _waveformTick = Duration(milliseconds: 40);
  static const int _maxWaveSamples = 1200;

  @override
  void onInit() {
    super.onInit();
    _initializeComponents();
    _setupFromArguments();
    _setupRecordingFloatingBarActionListener();
    WidgetsBinding.instance.addObserver(this);
    //generateWaveData();
  }

  @override
  void onClose() {
    _cleanupResources();
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    unawaited(_refreshRecordingIndicator());
  }

  void applyRouteArgumentsIfIdle() {
    if (isEditingTitle.value) return;
    if (isRecording.value) return;
    if (timerStatus.value != TimerStatus.stopped) return;
    _setupFromArguments();
    titleEditingController.text = newName.value;
  }

// 请求录音权限
  Future<bool> _requestRecordPermission() async {
    try {
      final bool granted = await PermissionUtil.instance.requestPermission(
        permissionType: Permission.microphone,
        permissionName: 'microphonePermission'.tr,
        explanationText: 'microphonePermissionExplanation'.tr,
        permanentDenialText: 'microphonePermissionPermanentDenial'.tr,
      );

      if (granted) {
        Logger.d("Permission", "用户授予了录音权限");
        return true;
      } else {
        Logger.d("Permission", "用户未授予录音权限");
        return false;
      }
    } catch (e) {
      Logger.e("Permission", "请求录音权限时出错: $e");
      return false;
    }
  }

  /// 初始化 UI 控制器和焦点节点
  void _initializeComponents() {
    titleEditingController = TextEditingController(text: fileName.value);
    titleFocusNode = FocusNode();
    titleFocusNode.addListener(_handleTitleFocusChange);
  }

  /// 根据路由参数设置初始状态
  void _setupFromArguments() {
    final Map<String, dynamic> args = Get.arguments ?? {};
    audioType.value = args['audioTypes'] ?? 0;

    // 根据音频类型设置默认文件名
    switch (audioType.value) {
      case 0:
        fileName.value = "liveRecording".tr; //对应中文:现场录音
        break;
      case 1:
        fileName.value = "audioVideoRecording".tr; //对应中文:音视频录音
        break;
      case 2:
        fileName.value = "callRecording".tr; //对应中文:电话录音
        break;
    }
    newName.value = fileName.value;
  }

  /// 控制器销毁时清理资源
  void _cleanupResources() {
    _timer?.cancel();
    unawaited(_stopAndroidRecordingFloatingBar());
    _routeMonitorTimer?.cancel();
    _routeMonitorTimer = null;
    _recordingFloatingActionSubscription?.cancel();
    _recordingFloatingActionSubscription = null;
    _hideInAppRecordingOverlay();
    _stopWaveformTimer();
    _recognitionSubscription?.cancel();
    _recognitionSubscription = null;
    _audioDataSubscription?.cancel();
    _audioDataSubscription = null;
    titleEditingController.dispose();
    titleFocusNode.dispose();
    if (audioType.value != 0) {
      _bleManager.closeCodec();
    }
    if (isRecording.value) {
      _asrService.stopRecord(true);
    }
    isRecording.value = false;
    rms.value = 0.0;
    _smoothedRms = 0.0;
    _latestRms = 0.0;
    waveformController.reset();
    waveformController.dispose();
  }

  /// 处理标题输入框焦点变化
  void _handleTitleFocusChange() {
    if (!titleFocusNode.hasFocus && isEditingTitle.value) {
      saveTitleChange();
    }
  }

  /// 开始标题编辑模式
  void startTitleEditing() {
    isEditingTitle.value = true;
    titleEditingController.text = fileName.value;
    newName.value = fileName.value;
    Future.delayed(const Duration(milliseconds: 100), () {
      titleFocusNode.requestFocus();
    });
  }

  /// 保存新标题后退出编辑状态
  Future<void> saveTitleChange() async {
    isEditingTitle.value = true;
    if (isEditingTitle.value) {
      newName.value = titleEditingController.text;
      isEditingTitle.value = false;
    }
  }

  /// 切换转写文本内容的显示状态
  Future<void> toggleTextDisplay() async {
    showTextContent.toggle();
  }

  /// 切换重要标记状态
  void toggleMarked() => isMarked.toggle();

  /// 格式化时间为 MM:SS.S 显示格式
  String formatTime(int milliseconds) {
    // 使用毫秒级精度计算
    final totalMs = milliseconds;
    final minutes = (totalMs ~/ 60000);
    final secs = ((totalMs % 60000) ~/ 1000);
    final centiseconds = ((totalMs % 1000) ~/ 100); // 取十分之一秒（一位小数）

    return '${minutes.toString().padLeft(2, '0')}'
        ':${secs.toString().padLeft(2, '0')}'
        '.${centiseconds.toString()}';
  }

  /// 根据当前状态开始或恢复录音
  Future<void> toggleRecording() async {
    // 等待权限请求完成并获取结果
    final bool granted = await _requestRecordPermission();

    // 如果权限被拒绝，直接返回
    if (!granted) {
      Logger.d("Permission", "录音权限被拒绝，无法开始录音");
      return;
    }

    await _requestNotificationPermissionIfNeeded();

    // 根据当前计时器状态执行相应操作
    switch (timerStatus.value) {
      case TimerStatus.stopped:
        await _startRecording();
        break;
      case TimerStatus.running:
        await _pauseRecording();
        break;
      case TimerStatus.paused:
        await _resumeRecording();
        break;
    }
  }

  /// 开始录音会话
  Future<void> _startRecording() async {
    // Prepare storage directory
    final appDir = await appDocDir;
    final dir = Directory("${appDir.path}/MeetingAudio/");
    if (!await dir.exists()) await dir.create(recursive: true);

    // Generate timestamped filename
    final formattedTime = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final baseTitle = newName.value.isNotEmpty ? newName.value : fileName.value;
    final safeBase = sanitizeRecordingFileStem(
      baseTitle,
      fallback: _defaultRecordingFileStem(),
    );
    final fullFileName = "${safeBase}_$formattedTime";
    final filePath = path.join(dir.path, '$fullFileName.wav');

    // 根据音频类型选择音频源
    AudioSourceType audioSourceType;
    bool acceptAudioData = false;
    switch (audioType.value) {
      case 0: // Live
        audioSourceType = AudioSourceType.microphone;
        acceptAudioData = true;
        break;
      case 1: // Media
        audioSourceType = AudioSourceType.systemAudio;
        acceptAudioData = false;
        break;
      case 2: // Call
        audioSourceType = AudioSourceType.external;
        acceptAudioData = true;
        break;
      default:
        audioSourceType = AudioSourceType.microphone;
        acceptAudioData = true;
    }

    await _asrService.enableRecord(
      audioSourceType,
      filePath,
      acceptAudioData,
    );

    // 通过 asrService 获取音频数据流
    _audioDataSubscription =
        _asrService.getAudioDataStream()?.listen((audioData) {
      // 处理音频数据，例如：
      // 1. 实时音频可视化
      // 2. 音频质量检测
      // 3. 发送到其他服务
      // 处理音频数据的逻辑
      _processAudioData(audioData);
    });

    isRecording.value = true;
    _overlayPermissionPromptedThisSession = false;
    _overlayPermissionSnackShownThisSession = false;
    _overlayPermissionRequesting = false;
    // 更新录音状态
    fileName.value = fullFileName;
    newName.value = fullFileName;
    titleEditingController.text = fullFileName;

    // Start hardware components
    _startHardwareServices();
    _resetWaveform();
    _startWaveformTimer();
    startTimer();
    await _refreshRecordingIndicator();
  }

  /// 根据音频类型启动对应的硬件服务
  void _startHardwareServices() {
    switch (audioType.value) {
      case 0:
        // _bleManager.openEncoder();
        break;
      case 1:
        _asrService.setAudioConfig(sampleRate: 16000, channels: 1);
        _bleManager.openDecoder();
        break;
      case 2:
        _asrService.setAudioConfig(sampleRate: 16000, channels: 2);
        _bleManager.openCallRecordDecoder();
        break;
    }
  }

  /// 暂停当前录音会话
  Future<void> _pauseRecording() async {
    await _asrService.pauseRecord();
    _stopWaveformTimer();
    rms.value = 0.0;
    pauseTimer();
    await _refreshRecordingIndicator();
  }

  /// 恢复已暂停的录音会话
  Future<void> _resumeRecording() async {
    await _asrService.resumeRecord();
    _startWaveformTimer();
    startTimer();
    await _refreshRecordingIndicator();
  }

  /// 处理原始Uint8List音频数据
  void _processAudioData(Uint8List audioData) {
    if (!isRecording.value) return;
    final next = _calculateAmplitude(audioData);
    if (_smoothedRms == 0.0) {
      _smoothedRms = next;
    } else {
      _smoothedRms = _smoothedRms * 0.8 + next * 0.2;
    }
    rms.value = _smoothedRms;
    _latestRms = _smoothedRms;
  }

  void _resetWaveform() {
    waveformController.reset();
    waveformController.updateFrequency = _waveformTick;
  }

  void _startWaveformTimer() {
    _waveformTimer?.cancel();
    _waveformTimer = Timer.periodic(_waveformTick, (_) {
      if (!isRecording.value) return;
      if (timerStatus.value != TimerStatus.running) return;
      _appendWaveSample(_latestRms);
    });
  }

  void _stopWaveformTimer() {
    _waveformTimer?.cancel();
    _waveformTimer = null;
  }

  void _appendWaveSample(double value) {
    final normalized = value.clamp(0.0, 1.0);
    final eased = sqrt(normalized);
    final data = waveformController.waveData;
    data.add(eased);
    if (data.length > _maxWaveSamples) {
      data.removeRange(0, data.length - _maxWaveSamples);
    }
    waveformController.notifyListeners();
  }

  /// 计算音频数据的振幅
  double _calculateAmplitude(Uint8List audioData) {
    if (audioData.isEmpty) return 0.0;

    // 使用RMS (Root Mean Square) 算法，更准确反映音频能量
    double sumSquares = 0.0;
    int sampleCount = 0;

    for (int i = 0; i < audioData.length; i += 4) {
      // 跳跃采样，减少计算量
      if (i + 1 < audioData.length) {
        final int sample = (audioData[i + 1] << 8) | audioData[i];
        final int signedSample = sample > 32767 ? sample - 65536 : sample;
        sumSquares += (signedSample * signedSample);
        sampleCount++;
      }
    }

    if (sampleCount == 0) return 0.0;
    final rms = sqrt(sumSquares / sampleCount);
    return (rms / 32768.0).clamp(0.0, 1.0);
  }

  /// 保存录音并清理相关资源
  Future<bool> saveRecording() async {
    if (isSaving.value) return false;
    if (!isRecording.value) return true;
    isSaving.value = true;

    final prevStatus = timerStatus.value;
    pauseTimer();
    final prevElapsedMs = _elapsedMilliseconds;
    _stopWaveformTimer();

    try {
      final bool stopped = await _asrService
          .stopRecord(true)
          .timeout(_stopRecordTimeout, onTimeout: () => false);
      if (!stopped) {
        _restoreRecordingUiAfterFailedStop(prevStatus, prevElapsedMs);
        Get.snackbar('error'.tr, 'meetingRecordStopTimeout'.tr);
        return false;
      }

      if (audioType.value != 0) {
        _bleManager.closeCodec();
      }

      try {
        await clearBackgroundRecordingIndicator()
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        Logger.error('清理录音指示器失败: ${e.toString()}');
      }

      try {
        await _applyTitleChangeAfterSave();
      } catch (e) {
        Logger.error('保存录音后的文件处理失败: ${e.toString()}');
      }

      resetTimer();
      _resetToDefaultState();
      isRecording.value = false;
      rms.value = 0.0;
      _smoothedRms = 0.0;
      _latestRms = 0.0;
      _resetWaveform();
      await _refreshRecordingIndicator();
      return true;
    } catch (e) {
      Logger.error('保存录音失败: ${e.toString()}');
      _restoreRecordingUiAfterFailedStop(prevStatus, prevElapsedMs);
      Get.snackbar('error'.tr, 'meetingRecordSaveFailed'.tr);
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  Future<bool> discardRecording() async {
    if (!isRecording.value) return true;
    if (isSaving.value) return false;
    isSaving.value = true;

    final prevStatus = timerStatus.value;
    pauseTimer();
    final prevElapsedMs = _elapsedMilliseconds;
    _stopWaveformTimer();

    try {
      final bool stopped = await _asrService
          .stopRecord(false)
          .timeout(_stopRecordTimeout, onTimeout: () => false);
      if (!stopped) {
        _restoreRecordingUiAfterFailedStop(prevStatus, prevElapsedMs);
        Get.snackbar('error'.tr, 'meetingRecordStopTimeout'.tr);
        return false;
      }

      if (audioType.value != 0) {
        _bleManager.closeCodec();
      }

      try {
        await clearBackgroundRecordingIndicator()
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        Logger.error('清理录音指示器失败: ${e.toString()}');
      }

      resetTimer();
      _resetToDefaultState();
      isRecording.value = false;
      rms.value = 0.0;
      _smoothedRms = 0.0;
      _latestRms = 0.0;
      _resetWaveform();
      await _refreshRecordingIndicator();
      return true;
    } catch (e) {
      Logger.error('结束录音不保存失败: ${e.toString()}');
      _restoreRecordingUiAfterFailedStop(prevStatus, prevElapsedMs);
      Get.snackbar('error'.tr, 'meetingRecordStopFailed'.tr);
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  void _restoreRecordingUiAfterFailedStop(
    TimerStatus prevStatus,
    int prevElapsedMs,
  ) {
    _elapsedMilliseconds = prevElapsedMs;
    seconds.value = (prevElapsedMs / 1000).round();
    milliseconds.value = prevElapsedMs;
    if (prevStatus == TimerStatus.running) {
      timerStatus.value = TimerStatus.stopped;
      startTimer();
    } else {
      timerStatus.value = prevStatus;
    }
    _startWaveformTimer();
  }

  Future<void> _applyTitleChangeAfterSave() async {
    if (fileName.value == newName.value) return;
    if (!Get.isRegistered<MeetingTaskService>()) return;

    final raw = newName.value.trim();
    if (raw.isEmpty) return;

    final nextTitle = raw.toLowerCase().endsWith('.wav') ? raw : '$raw.wav';
    Get.find<MeetingTaskService>()
        .setPendingLocalRecordingTitle('${fileName.value}.wav', nextTitle);
  }

  /// 将控制器重置到初始状态
  void _resetToDefaultState() {
    switch (audioType.value) {
      case 0:
        fileName.value = "liveRecording".tr; //对应中文:现场录音
        break;
      case 1:
        fileName.value = "audioVideoRecording".tr; //对应中文:音视频录音
        break;
      case 2:
        fileName.value = "callRecording".tr; //对应中文:电话录音
        break;
    }
    newName.value = fileName.value;
    finalContent.value = '';
    intermediateContent.value = '';
    isMarked.value = false;
  }

  /// 计时器控制部分 ///

  /// 启动定时器
  void startTimer() {
    if (timerStatus.value != TimerStatus.running) {
      timerStatus.value = TimerStatus.running;
      _lastStartTime = DateTime.now().millisecondsSinceEpoch;

      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        // 改为100ms更新频率
        if (timerStatus.value != TimerStatus.running) return;

        final currentTime = DateTime.now().millisecondsSinceEpoch;
        _elapsedMilliseconds += currentTime - _lastStartTime!;
        _lastStartTime = currentTime;

        seconds.value = (_elapsedMilliseconds / 1000).round();
        milliseconds.value = _elapsedMilliseconds; // 更新毫秒值
      });
    }
  }

  /// 暂停当前计时器
  void pauseTimer() {
    if (timerStatus.value == TimerStatus.running) {
      timerStatus.value = TimerStatus.paused;
      _timer?.cancel();
      _timer = null;

      final currentTime = DateTime.now().millisecondsSinceEpoch;
      _elapsedMilliseconds += currentTime - _lastStartTime!;
      _lastStartTime = null;
    }
  }

  /// 将计时器重置到初始状态
  void resetTimer() {
    _timer?.cancel();
    _timer = null;
    _elapsedMilliseconds = 0;
    _lastStartTime = null;
    seconds.value = 0;
    milliseconds.value = 0;
    timerStatus.value = TimerStatus.stopped;
  }

  bool _shouldShowRecordingIndicator() {
    if (!isRecording.value) return false;
    if (_appLifecycleState != AppLifecycleState.resumed) return true;
    return Get.currentRoute != '/meeting/record';
  }

  Future<void> _refreshRecordingIndicator() async {
    if (!isRecording.value) {
      _routeMonitorTimer?.cancel();
      _routeMonitorTimer = null;
      _hideInAppRecordingOverlay();
      await _stopAndroidRecordingFloatingBar();
      return;
    }

    _startRouteMonitorIfNeeded();
    final shouldShow = _shouldShowRecordingIndicator();
    if (!shouldShow) {
      _hideInAppRecordingOverlay();
      await _stopAndroidRecordingFloatingBar();
      if (Platform.isIOS) {
        final plugin = await _ensureLocalNotificationsPlugin();
        await plugin.cancel(_backgroundRecordingNotificationId);
      }
      return;
    }

    if (_floatingBarManuallyClosed) return;

    if (Platform.isAndroid) {
      await showBackgroundRecordingIndicator();
      return;
    }

    if (Platform.isIOS) {
      if (_appLifecycleState == AppLifecycleState.resumed) {
        final plugin = await _ensureLocalNotificationsPlugin();
        await plugin.cancel(_backgroundRecordingNotificationId);
        await _showInAppRecordingOverlay();
      } else {
        await showBackgroundRecordingIndicator();
      }
    }
  }

  void _startRouteMonitorIfNeeded() {
    if (_routeMonitorTimer != null) return;
    _lastKnownRoute = Get.currentRoute;
    _routeMonitorTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      final currentRoute = Get.currentRoute;
      if (currentRoute == _lastKnownRoute) return;
      _lastKnownRoute = currentRoute;
      unawaited(_refreshRecordingIndicator());
    });
  }

  Future<void> _showInAppRecordingOverlay() async {
    if (!Platform.isIOS) return;
    if (_recordingInAppOverlay != null) return;
    final context = Get.overlayContext;
    if (context == null) return;

    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final safeTop = mediaQuery.padding.top;
    final safeBottom = mediaQuery.padding.bottom;

    final width = 260.w;
    final height = 52.h;
    final initial = _recordingInAppOverlayOffset ??
        Offset(16.w, max(16.h + safeTop, 100.h));
    _recordingInAppOverlayOffset = Offset(
      initial.dx.clamp(8.w, max(8.w, screenSize.width - width - 8.w)),
      initial.dy.clamp(
        8.h + safeTop,
        max(8.h + safeTop, screenSize.height - height - 8.h - safeBottom),
      ),
    );

    _recordingInAppOverlay = OverlayEntry(
      builder: (_) {
        final offset = _recordingInAppOverlayOffset ?? Offset(16.w, 120.h);
        return Positioned(
          left: offset.dx,
          top: offset.dy,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onPanUpdate: (details) {
                final next = Offset(
                  offset.dx + details.delta.dx,
                  offset.dy + details.delta.dy,
                );
                _recordingInAppOverlayOffset = Offset(
                  next.dx.clamp(8.w, max(8.w, screenSize.width - width - 8.w)),
                  next.dy.clamp(
                    8.h + safeTop,
                    max(
                      8.h + safeTop,
                      screenSize.height - height - 8.h - safeBottom,
                    ),
                  ),
                );
                _recordingInAppOverlay?.markNeedsBuild();
              },
              child: Container(
                width: width,
                height: height,
                padding: EdgeInsets.symmetric(horizontal: 10.w),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(26.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 10.r,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.mic_rounded,
                      size: 18.sp,
                      color: Colors.white,
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Obx(() {
                        final durationText =
                            _formatTimeForFloatingBar(milliseconds.value);
                        final typeText = _getRecordingTypeText();
                        return Text(
                          '$durationText · $typeText',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }),
                    ),
                    SizedBox(width: 6.w),
                    Obx(() {
                      final paused = timerStatus.value == TimerStatus.paused;
                      return InkWell(
                        onTap: togglePauseResumeFromFloatingBar,
                        borderRadius: BorderRadius.circular(18.r),
                        child: Padding(
                          padding: EdgeInsets.all(6.w),
                          child: Icon(
                            paused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                            size: 18.sp,
                            color: Colors.white,
                          ),
                        ),
                      );
                    }),
                    InkWell(
                      onTap: () {
                        _floatingBarManuallyClosed = false;
                        if (Get.currentRoute == '/meeting/record') return;
                        Get.to(
                          () => const MeetingRecordView(),
                          binding: MeetingRecordBinding(),
                          arguments: {'audioTypes': audioType.value},
                        );
                      },
                      borderRadius: BorderRadius.circular(18.r),
                      child: Padding(
                        padding: EdgeInsets.all(6.w),
                        child: Icon(
                          Icons.open_in_new_rounded,
                          size: 18.sp,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        _floatingBarManuallyClosed = true;
                        _hideInAppRecordingOverlay();
                      },
                      borderRadius: BorderRadius.circular(18.r),
                      child: Padding(
                        padding: EdgeInsets.all(6.w),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18.sp,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_recordingInAppOverlay!);
  }

  void _hideInAppRecordingOverlay() {
    _recordingInAppOverlay?.remove();
    _recordingInAppOverlay = null;
  }
}
