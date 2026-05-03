import 'dart:async';
import 'dart:io';

import '../../../legacy_stubs/flutter_blue_plus.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import '../../../legacy_stubs/wifi_iot.dart';

import '../../../core/utils/ftpconnect/ftpconnect.dart';
import '../../../data/services/meeting/meeting_upload_service.dart';
import 'meeting_home_controller.dart';

class MeetingConnectController extends GetxController {
  final _meetingController = Get.find<MeetingHomeController>();

  RxString stateStr = 'searching'.tr.obs; // 对应中文：搜索中...
  RxBool isRescan = false.obs;
  RxString importedFilesStr = ''.obs;

  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;
  BluetoothDevice? _device;

  bool isScanFailed = false;

  BluetoothCharacteristic? _writeCharacteristic;
  StreamSubscription<List<int>>? _valueReceivedSubscription;

  String _wifiSSID = '';
  String _wifiPassword = '';
  String _ftpAddress = '';
  String _ftpPort = '';
  String _ftpAccount = '';
  String _ftpPassword = '';

  FTPConnect? _ftpConnect;

  RxBool isDownload = false.obs;
  RxDouble downloadProgress = 0.0.obs;
  RxInt totalReceived = 0.obs;
  RxInt fileSize = 0.obs;

  @override
  void onInit() {
    super.onInit();
    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult item in results) {
        _handlerScanResult(item);
      }
    });
    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      if (isScanFailed) {
        stateStr.value = 'searchFailed'.tr; // 对应中文：搜索失败，请检查蓝牙是否开启
        isRescan.value = true;
        return;
      }
      if (!state && _device == null) {
        stateStr.value = 'aiPenNotFound'.tr; // 对应中文：未搜索到 AI PEN 设备
        isRescan.value = true;
      } else {
        stateStr.value = 'searching'.tr; // 对应中文：搜索中...
        isRescan.value = false;
      }
    });
    startScan();
  }

  @override
  void onClose() {
    _scanResultsSubscription.cancel();
    _isScanningSubscription.cancel();
    _valueReceivedSubscription?.cancel();
    _stopScan();
    _disconnect();
    super.onClose();
  }

  Future<void> startScan() async {
    try {
      isScanFailed = false;
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        withServices: [
          Guid('FFF0'),
        ],
        withNames: ['AI PEN'],
      );
    } catch (e) {
      isScanFailed = true;
    }
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  Future<void> _connect() async {
    await _device?.connect();
    await _discoverServices();
  }

  Future<void> _disconnect() async {
    _ftpConnect?.disconnect();
    await WiFiForIoTPlugin.forceWifiUsage(false);
    await WiFiForIoTPlugin.disconnect();
    await _device?.disconnect();
  }

  void _handlerScanResult(ScanResult result) async {
    if (result.device.platformName == 'AI PEN') {
      _device = result.device;
      await _stopScan();
      await _connect();
      stateStr.value = 'connectedToAiPen'.tr; // 对应中文：已连接到 AI PEN 设备
    }
  }

  Future<void> _discoverServices() async {
    List<BluetoothService> services = await _device?.discoverServices() ?? [];
    if (services.isNotEmpty) {
      for (var element in services) {
        if (element.serviceUuid == Guid('FFF0')) {
          _readCharacteristics(element.characteristics);
        }
      }
    }
  }

  Future<void> _readCharacteristics(
      List<BluetoothCharacteristic> characteristics) async {
    for (var element in characteristics) {
      if (element.characteristicUuid == Guid('FFF1')) {
        _writeCharacteristic = element;
        stateStr.value = 'checkingNewFiles'.tr; // 对应中文：检查是否有新文件需要导入
        sendData([0x5a, 0x01, 0x0d]);
      } else if (element.characteristicUuid == Guid('FFF2')) {
        await element.setNotifyValue(true);
        _valueReceivedSubscription = element.onValueReceived.listen((value) {
          _listenData(value);
        });
      }
    }
  }

  Future<void> sendData(List<int> value) async {
    await _writeCharacteristic?.write(value, withoutResponse: true);
  }

  void _listenData(List<int> value) {
    int command = value[2];
    switch (command) {
      case 0x0d: // 是否有导入文件
        if (value[3] == 0x01) {
          stateStr.value = 'startingWifi'.tr; // 对应中文：正在开启Wi-Fi...
          importedFilesStr.value = 'newFilesDetected'.tr; // 对应中文：检查到有新文件，正在准备导入
          sendData([0x5a, 0x02, 0x87, 0x01]);
        } else {
          importedFilesStr.value = 'noNewFiles'.tr; // 对应中文：没有新文件需要导入
        }
        break;
      case 0x87: // Wi-Fi 开启/关闭
        if (value[3] == 0x01 && value[4] == 0x01) {
          sendData([0x5a, 0x01, 0x0b]);
        }
        break;
      case 0x0b: // WiFi 热点 SSID
        _wifiSSID = String.fromCharCodes(value.sublist(3, value.length - 2));
        sendData([0x5a, 0x01, 0x0c]);
        break;
      case 0x0c: // WiFi 热点密码
        _wifiPassword = _decodePassword(value);
        _connectWifi();
        break;
      case 0x03: // FTP 地址
        _ftpAddress = String.fromCharCodes(value.sublist(3, value.length - 2));
        sendData([0x5a, 0x01, 0x04]);
        break;
      case 0x04: // FTP 端口
        _ftpPort = String.fromCharCodes(value.sublist(3, value.length - 2));
        sendData([0x5a, 0x01, 0x05]);
        break;
      case 0x05: // FTP 账号
        _ftpAccount = String.fromCharCodes(value.sublist(3, value.length - 2));
        sendData([0x5a, 0x01, 0x06]);
        break;
      case 0x06: // FTP 密码
        _ftpPassword = _decodePassword(value);
        _connectFtp();
        break;
      default:
    }
  }

  void _connectWifi() async {
    if (_wifiSSID.isNotEmpty && _wifiPassword.isNotEmpty) {
      stateStr.value = 'connectingWifi'.tr; // 对应中文：正在连接 Wi-Fi...
      await WiFiForIoTPlugin.connect(
        _wifiSSID,
        password: _wifiPassword,
        security: NetworkSecurity.WPA,
      );
      await WiFiForIoTPlugin.forceWifiUsage(true);
      stateStr.value = 'wifiConnected'.tr; // 对应中文：Wi-Fi 连接成功
      sendData([0x5a, 0x01, 0x03]);
    }
  }

  void _connectFtp() async {
    if (_ftpAddress.isNotEmpty &&
        _ftpPort.isNotEmpty &&
        _ftpAccount.isNotEmpty &&
        _ftpPassword.isNotEmpty) {
      _ftpConnect = FTPConnect(
        _ftpAddress,
        port: int.tryParse(_ftpPort) ?? 21,
        user: _ftpAccount,
        pass: _ftpPassword,
      );
      await _ftpConnect?.connect();
      _ftpConnect?.listCommand = ListCommand.LIST;
      List<FTPEntry>? listDirectory = await _ftpConnect?.listDirectoryContent();
      if (listDirectory != null && listDirectory.isNotEmpty) {
        stateStr.value = 'downloadingFiles'.tr; // 对应中文：正在下载文件...
        isDownload.value = true;
        int totalSize = listDirectory.fold(
          0,
          (sum, entry) => sum + (entry.size ?? 0),
        );
        for (var i = 0; i < listDirectory.length; i++) {
          importedFilesStr.value = 'downloadingFileProgress'
              .tr
              .replaceAll('{total}', '${listDirectory.length}')
              .replaceAll('{current}',
                  '${i + 1}'); // 对应中文：共{total}个文件，正在下载第{current}个文件
          int previousSize = i > 0 ? listDirectory[i - 1].size ?? 0 : 0;
          FTPEntry element = listDirectory[i];
          await _downloadFile(totalSize, previousSize, element);
          await _ftpConnect?.deleteFile(element.name);
        }
        await _disconnect();
        stateStr.value = 'downloadComplete'.tr; // 对应中文：下载完成
        importedFilesStr.value = 'downloadCompleteInfo'.tr.replaceAll('{count}',
            '${listDirectory.length}'); // 对应中文：下载完成，共{count}个文件，2秒后自动返回
        Future.delayed(const Duration(seconds: 2), () {
          _executeUpload();
          Get.back();
        });
      }
    }
  }

  Future<void> _downloadFile(
      int totalSize, int previousSize, FTPEntry entry) async {
    final directory = await getApplicationDocumentsDirectory();
    final directoryDir = Directory('${directory.path}/RecordingPen');
    if (!await directoryDir.exists()) {
      await directoryDir.create(recursive: true);
    }
    final String filePath = '${directory.path}/RecordingPen/${entry.name}';
    final File localFile = File(filePath);
    await _ftpConnect?.downloadFileWithRetry(
      entry.name,
      localFile,
      pRetryCount: 3,
      onProgress: (double progress, int received, int size) {
        downloadProgress.value = (previousSize + received) / totalSize;
        totalReceived.value = received;
        fileSize.value = size;
      },
    );
    await _meetingController.insertMeetingAudio(
      entry.name,
      filePath,
      isUpload: false,
    );
  }

  Future<void> _executeUpload() async {
    await Future.delayed(const Duration(seconds: 3));
    final meetingUploadService = Get.find<MeetingUploadService>();
    meetingUploadService.executeUpload();
  }

  String _decodePassword(List<int> data) {
    final passwordData = data.sublist(3, data.length - 2);
    final decodedBytes = passwordData.map((byte) => byte ^ 0xFF).toList();
    return String.fromCharCodes(decodedBytes);
  }
}
