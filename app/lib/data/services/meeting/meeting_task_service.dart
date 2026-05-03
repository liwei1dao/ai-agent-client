import 'dart:convert';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../db/sqflite_api.dart';
import '../network/api.dart';
import '../../models/user_Info.dart';
import 'meeting_upload_service.dart';

class MeetingTaskService extends GetxService {
  MeetingUploadService get _uploadService => Get.find<MeetingUploadService>();

  final GetStorage _storage = GetStorage();
  static const String _pendingLocalRecordingTitleStorageKey =
      'meeting_pending_local_recording_titles';

  List _taskList = []; //待处理的会议任务列表

  bool _isTask = false; //是否有正在处理的任务

  RxInt updateListState = 0.obs; //是否更新首页列表
  RxInt localImportState = 0.obs; //是否触发本地录音导入
  int meetingId = 0;
  RxInt tasktype = 1.obs; //任务类型，0-初始，1-等待转写中，2-转写中，3-等待总结中，4-总结中，5-完成
  List textList = [];
  String personnel = '';
  String summary = '';
  String overview = '';

  void setPendingLocalRecordingTitle(String wavFileName, String displayTitle) {
    if (wavFileName.isEmpty) return;
    final data = _storage.read(_pendingLocalRecordingTitleStorageKey);
    final map = (data is Map)
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    map[wavFileName] = displayTitle;
    _storage.write(_pendingLocalRecordingTitleStorageKey, map);
  }

  String? takePendingLocalRecordingTitle(String wavFileName) {
    if (wavFileName.isEmpty) return null;
    final data = _storage.read(_pendingLocalRecordingTitleStorageKey);
    if (data is! Map) return null;
    final map = Map<String, dynamic>.from(data);
    final v = map.remove(wavFileName);
    if (v == null) return null;
    _storage.write(_pendingLocalRecordingTitleStorageKey, map);
    return v.toString();
  }

  void requestLocalImport() {
    localImportState.value++;
  }

  Future<void> addTask(
    int id,
    String audiourl,
    String formlanguage,
    String tolanguage,
    bool isdistinguishspeaker,
    int templateid,
    String tid,
  ) async {
    if (audiourl.isEmpty) {
      Map uploadData = _uploadService.uploadList.firstWhere(
        (element) => element['id'] == id,
        orElse: () => {},
      );
      if (uploadData.isNotEmpty) {
        if (uploadData['audiourl'].isEmpty) {
          uploadData['isTask'] = true;
          uploadData['formlanguage'] = formlanguage;
          uploadData['tolanguage'] = tolanguage;
          uploadData['isdistinguishspeaker'] = isdistinguishspeaker;
          uploadData['templateid'] = templateid;
          uploadData['tid'] = tid;
          // 文件还在上传：先把 tasktype 持久化为 1，避免详情页退出再进
          // 时状态被 DB 旧值覆盖回 0。等 executeUpload 完成会再次调
          // submitTask，状态会被重写覆盖（仍然是 1）。
          await SqfliteApi.editMeetingTitle(id, {'tasktype': 1});
          await SqfliteApi.editMeeting(id, {'tasktype': 1});
          if (id == meetingId) tasktype.value = 1;
          updateListState.value++;
        } else {
          await submitTask(
            id,
            formlanguage,
            tolanguage,
            isdistinguishspeaker,
            templateid,
            tid,
          );
        }
      } else {
        // 既不在上传队列，audiourl 也是空——通常是 record 已同步自服务端
        // 但本地音频缺失。直接发起 startTask 让服务端走云端音频流程，
        // 避免点了开始撰写完全没动静的"静默失败"路径。
        await submitTask(
          id,
          formlanguage,
          tolanguage,
          isdistinguishspeaker,
          templateid,
          tid,
        );
      }
    } else {
      await submitTask(
        id,
        formlanguage,
        tolanguage,
        isdistinguishspeaker,
        templateid,
        tid,
      );
    }
  }

  Future<void> submitTask(
    int id,
    String formlanguage,
    String tolanguage,
    bool isdistinguishspeaker,
    int templateid,
    String tid,
  ) async {
    try {
      await Api.startTaskEchomeet({
        'id': id,
        'formlanguage': formlanguage,
        'tolanguage': tolanguage,
        'isdistinguishspeaker': isdistinguishspeaker,
        'templateid': templateid,
        'tid': tid,
      });
    } catch (e) {
      // 服务端拒绝（如积分不足 / record not found）：回滚此前
      // 在 addTask 延迟分支或者外层乐观写入的 tasktype=1，恢复到 0。
      try {
        await SqfliteApi.editMeetingTitle(id, {'tasktype': 0});
        await SqfliteApi.editMeeting(id, {'tasktype': 0});
      } catch (_) {}
      _taskList.removeWhere((e) => e['id'] == id);
      if (id == meetingId) tasktype.value = 0;
      updateListState.value++;
      rethrow;
    }
    final seconds = await _getMeetingSeconds(id);
    _decrementMeetingIntegral(cost: seconds);
    _taskList.add({
      'id': id,
      'tasktype': 1,
    });
    // 必须同时把 meeting / meetingdetails 两张表的 tasktype 同步成 1，
    // 否则详情页 _getDataDetails 会从 meetingdetails 读旧值，看起来"状态被还原"。
    await SqfliteApi.editMeetingTitle(id, {'tasktype': 1});
    await SqfliteApi.editMeeting(id, {'tasktype': 1});
    if (id == meetingId) tasktype.value = 1;
    updateListState.value++;
    _executeTask();
  }

  Future<void> refreshTask(int id, int templateid, String tid, String tolanguage) async {
    final int previousType = tasktype.value;
    tasktype.value = 3;
    try {
      await Api.refreshTaskEchomeet({
        'id': id,
        'templateid': templateid,
        'tid': tid,
        'tolanguage': tolanguage,
      });
    } catch (e) {
      tasktype.value = previousType;
      rethrow;
    }
    _taskList.add({
      'id': id,
      'tasktype': 3,
    });
    await SqfliteApi.editMeetingTitle(id, {'tasktype': 3});
    await SqfliteApi.editMeeting(id, {'tasktype': 3});
    updateListState.value++;
    _executeTask();
  }

  Future<void> readTask(int id) async {
    await Api.readRecordEchomeet({'id': id});
    await SqfliteApi.editMeetingTitle(id, {'tasktype': 6});
    await SqfliteApi.editMeeting(id, {'tasktype': 6});
    updateListState.value++;
  }

  void _executeTask() async {
    if (_isTask) return;
    _isTask = true;
    while (_taskList.isNotEmpty) {
      await Future.delayed(const Duration(seconds: 5));
      await _queryTask();
    }
    _isTask = false;
  }

  Future<void> removeTask(int id) async {
    _taskList.removeWhere((element) => element['id'] == id);
    await Api.delRecordEchomeet({
      'ids': [id],
    });
  }

  void startTask(List data) {
    _taskList = data;
    _executeTask();
  }

  void stopTask() {
    _taskList.clear();
  }

  Future<void> _queryTask() async {
    if (_taskList.isEmpty) return;
    List ids = _taskList.map((e) => e['id']).toList();
    var response = await Api.getMultitermRecord({
      'ids': ids,
    });
    List queryList = response['records'] ?? [];
    for (var element in queryList) {
      int id = element['id'];
      int newTasktype = element['state'];
      Map taskData = _taskList.firstWhere(
        (i) => i['id'] == id,
        orElse: () => {},
      );
      if (taskData.isNotEmpty) {
        int oldTasktype = taskData['tasktype'];
        if (oldTasktype != newTasktype) {
          if (oldTasktype < 3 && newTasktype >= 3) {
            // 转写完成
            List<dynamic> decodeList = jsonDecode(element['translate']);
            List<Map<String, Object?>> speakerList =
                decodeList.map((e) => Map<String, Object?>.from(e)).toList();
            await SqfliteApi.deleteMeetingSpeaker(id);
            await SqfliteApi.insertMeetingSpeaker(speakerList);
            await SqfliteApi.editMeeting(
              id,
              {'tasktype': newTasktype},
            );
            if (id == meetingId) {
              List sqlSpeakerList = await SqfliteApi.getMeetingSpeaker(id);
              textList = List.from(sqlSpeakerList);
              tasktype.value = newTasktype;
            }
          }
          if (oldTasktype < 5 && newTasktype >= 5) {
            // 总结完成
            await SqfliteApi.editMeeting(id, {
              'tasktype': newTasktype,
              'personnel': element['personnel'] ?? '',
              'summary': element['summary'] ?? '',
              'overview': element['overview'] ?? '',
            });
            if (id == meetingId) {
              personnel = element['personnel'] ?? '';
              summary = element['summary'] ?? '';
              overview = element['overview'] ?? '';
              tasktype.value = newTasktype;
            }
          }
          await SqfliteApi.editMeetingTitle(
            id,
            {'tasktype': newTasktype},
          );
          taskData['tasktype'] = newTasktype;
          updateListState.value++;
        }
      }
      if (newTasktype >= 5) {
        _taskList.removeWhere((i) => i['id'] == id);
      }
    }
  }

  /// 获取会议音频秒数
  Future<int> _getMeetingSeconds(int id) async {
    try {
      final data = await SqfliteApi.getMeetingDetails(id);
      final v = data['seconds'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    } catch (_) {
      return 0;
    }
  }

  /// 减少用户会议积分
  void _decrementMeetingIntegral({required int cost}) {
    if (!User.isLoggedIn()) return;
    if (cost <= 0) return;
    final next = User.instance.meetintegral - cost;
    User.instance.updateUserInfo({'meetintegral': next < 0 ? 0 : next});
    //GetStorage().write('user_info', User.instance.toJson());
  }
}
