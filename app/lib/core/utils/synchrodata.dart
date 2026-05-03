import 'dart:convert';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../core/services/log_service.dart';
import '../../data/services/db/database_helper.dart';
import '../../data/services/meeting/meeting_task_service.dart';
import '../../data/services/network/api.dart';

class Synchrodata {
  static final GetStorage _storage = GetStorage();

  static List<Map<String, dynamic>> _records =
      (_storage.read("operation_records") as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
  static List _delids = _storage.read("operation_delids") ?? [];
  static bool _isSynchro = false;

  // 保存操作记录
  static Future saveOperationRecord(
    String method,
    dynamic params,
  ) async {
    String userId = '';
    Map? userInfo = _storage.read("user_info");
    if (userInfo != null) {
      userId = userInfo['user']['uid'];
    }
    String id = '${userId}_${params['id']}';
    if (params['type'] != null) {
      params['rtype'] = params['type'];
    }

    switch (method) {
      case 'insert':
        _records.add({
          ...Map<String, dynamic>.from(params),
          'id': id,
          'number': params['id'],
          'uid': userId,
        });
        _storage.write("operation_records", _records);
        break;
      case 'update':
        Map<String, dynamic>? foundElement = _records.firstWhere(
          (element) => element['id'] == id,
          orElse: () => {},
        );
        if (foundElement.isNotEmpty) {
          foundElement.addAll({
            ...Map<String, dynamic>.from(params),
            'id': id,
            'number': params['id'],
          });
        } else {
          _records.add({
            ...Map<String, dynamic>.from(params),
            'id': id,
            'number': params['id'],
            'uid': userId,
          });
        }
        _storage.write("operation_records", _records);
        break;
      case 'delete':
        _delids.add(id);
        _storage.write("operation_delids", _delids);
        break;
      default:
        break;
    }
  }

  // 上传操作记录
  static Future uploadOperationRecords({bool isSynchro = false}) async {
    if (_isSynchro) return;
    _isSynchro = true;
    // if (_records.isNotEmpty || _delids.isNotEmpty) {
    //   // 获取需要修改的全部数据
    //   List putRecords = [];
    //   for (var element in _records) {
    //     Map result = {'details': {}};
    //     List speakerList = [];
    //     if (!_delids.contains(element['id'])) {
    //       result = await SqfliteApi.getMeetingDetails(element['number']);
    //       speakerList = await SqfliteApi.getMeetingSpeaker(element['number']);
    //     }
    //     putRecords.add({
    //       ...Map<String, dynamic>.from(result),
    //       ...Map<String, dynamic>.from(result['details']),
    //       'rtype': result['type'],
    //       'original': jsonEncode(speakerList),
    //       ...Map<String, dynamic>.from(element),
    //     });
    //   }
    //   var result = await Api.putOperationRecord({
    //     'delids': _delids,
    //     'records': putRecords,
    //   });
    //   if (result != null) {
    //     _records = [];
    //     _delids = [];
    //     _storage.write("operation_records", _records);
    //     _storage.write("operation_delids", _delids);
    //   }
    // }
    if (isSynchro) {
      await _synchrodata();
    }
    _isSynchro = false;
  }

  // 同步数据
  static Future _synchrodata() async {
    final talker = LogService.instance.talker;
    try {
      var result = await Api.getOperationAllRecord();
      List records = (result is Map ? result['records'] : null) as List? ?? [];
      talker.info(
          '[Synchrodata] got ${records.length} records from server, '
          'ids=${records.map((e) => e is Map ? e['id'] : null).toList()}');
      if (records.isEmpty) return;
      final meetingTaskService = Get.find<MeetingTaskService>();
      List taskList = [];
      final db = await DatabaseHelper().database;
      await db.transaction((txn) async {
        for (var element in records) {
          try {
            // 服务端 record id 应该是数字，但兼容字符串/缺失情况
            final dynamic rawId = element['id'];
            int recordId;
            if (rawId is int) {
              recordId = rawId;
            } else if (rawId is num) {
              recordId = rawId.toInt();
            } else if (rawId is String) {
              recordId = int.tryParse(rawId) ?? 0;
            } else {
              recordId = 0;
            }
            if (recordId <= 0) {
              talker.warning(
                  '[Synchrodata] skip record with invalid id: rawId=$rawId '
                  '(${rawId.runtimeType}) full=$element');
              continue;
            }

            final int state = element['state'] is num
                ? (element['state'] as num).toInt()
                : 0;
            if (state > 0 && state < 5) {
              taskList.add({'id': recordId, 'tasktype': state});
            }

            final List existList = await txn.query(
              'meeting',
              where: 'id = ?',
              whereArgs: [recordId],
            );
            final int seconds = element['seconds'] is num
                ? (element['seconds'] as num).toInt()
                : 0;
            final int creationtimeSec = element['creationtime'] is num
                ? (element['creationtime'] as num).toInt()
                : 0;
            Map<String, Object?> meetingData = {
              'id': recordId,
              'title': element['title']?.toString() ?? '',
              'type': element['rtype']?.toString() ?? '',
              'seconds': seconds,
              'audiourl': element['audiourl']?.toString() ?? '',
              'tasktype': state,
              'creationtime': creationtimeSec * 1000,
            };
            Map<String, Object?> meetingDetailsData = {
              'meetingid': recordId,
              'address': element['address']?.toString() ?? '',
              'personnel': element['personnel']?.toString() ?? '',
              'taskid': element['taskid']?.toString() ?? '',
              'tasktype': state,
              'overview': element['overview']?.toString() ?? '',
              'summary': element['summary']?.toString() ?? '',
              'mindmap': '',
            };
            if (existList.isNotEmpty) {
              await txn.update('meeting', meetingData,
                  where: 'id = ?', whereArgs: [recordId]);
              await txn.update('meetingdetails', meetingDetailsData,
                  where: 'meetingid = ?', whereArgs: [recordId]);
              talker.info(
                  '[Synchrodata] updated meeting id=$recordId state=$state');
            } else {
              await txn.insert('meeting', {
                ...meetingData,
                'filepath': '',
              });
              await txn.insert('meetingdetails', meetingDetailsData);
              talker.info(
                  '[Synchrodata] inserted meeting id=$recordId state=$state');
            }

            final dynamic translate = element['translate'];
            if (translate is String && translate.isNotEmpty) {
              try {
                final List speakerList = jsonDecode(translate) as List;
                await txn.delete('meetingspeaker',
                    where: 'meetingid = ?', whereArgs: [recordId]);
                final batch = txn.batch();
                for (var item in speakerList) {
                  if (item is Map) {
                    batch.insert(
                        'meetingspeaker', Map<String, Object?>.from(item));
                  }
                }
                await batch.commit();
              } catch (e) {
                talker.error(
                    '[Synchrodata] translate decode failed for id=$recordId: $e');
              }
            }
          } catch (e, st) {
            talker.error(
                '[Synchrodata] failed processing record $element: $e\n$st');
          }
        }
      });
      meetingTaskService.startTask(taskList);
    } catch (e, st) {
      talker.error('[Synchrodata] _synchrodata failed: $e\n$st');
    }
  }
}
