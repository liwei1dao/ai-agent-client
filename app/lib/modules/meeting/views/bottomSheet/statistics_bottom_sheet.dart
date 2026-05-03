import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import '../../../../legacy_stubs/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../profile/controllers/profile_controller.dart';
import '../../controllers/meeting_mine_controller.dart';

class StatisticsBottomSheet extends StatefulWidget {
  const StatisticsBottomSheet({super.key});

  @override
  State<StatisticsBottomSheet> createState() => _StatisticsBottomSheetState();
}

class _StatisticsBottomSheetState extends State<StatisticsBottomSheet> {
  final _mineController = Get.find<MeetingMineController>();
  final _profileCtrl = Get.find<ProfileController>();

  final GlobalKey _posterKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () => Get.back(),
          behavior: HitTestBehavior.translucent,
          child: SizedBox(
            width: 1.sw,
            height: 1.sh,
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RepaintBoundary(
                key: _posterKey,
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 15.w, vertical: 20.w),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16.w),
                    image: const DecorationImage(
                      alignment: Alignment.topCenter,
                      image: AssetImage('assets/images/mine-background.png'),
                      fit: BoxFit.fitWidth,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 50.w,
                        height: 50.w,
                        margin: EdgeInsets.only(bottom: 10.w),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(50.w),
                        ),
                        child: CircleAvatar(
                          radius: 25.w,
                          backgroundImage: _profileCtrl
                                  .localAvatar.value.isNotEmpty
                              ? FileImage(File(_profileCtrl.localAvatar.value))
                              : (_profileCtrl.userInfo.value.avatar.isNotEmpty
                                  ? NetworkImage(
                                      _profileCtrl.userInfo.value.avatar)
                                  : null) as ImageProvider<Object>?,
                          backgroundColor: Colors.grey[200],
                          child: (_profileCtrl.localAvatar.value.isEmpty &&
                                  _profileCtrl.userInfo.value.avatar.isEmpty)
                              ? Icon(
                                  Icons.person,
                                  size: 25.r,
                                  color: Colors.grey[600],
                                )
                              : null,
                        ),
                      ),
                      Text(
                        _profileCtrl.userInfo.value.name,
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 20.w),
                        child: Wrap(
                          spacing: 5.w,
                          runSpacing: 5.w,
                          children: [
                            _item(
                              '天',
                              '${_mineController.days.value}',
                              Colors.amber,
                            ),
                            _item(
                              '文件',
                              '${_mineController.numberFiles.value}',
                              Colors.blueGrey,
                            ),
                            _item(
                              '小时',
                              '${_mineController.hourage.value}',
                              Colors.cyan,
                            ),
                            _item(
                              '连续录音天数',
                              '${_mineController.continuousDays.value}',
                              Colors.deepOrangeAccent,
                            ),
                            _item(
                              '单日最多录音',
                              '${_mineController.maxNumberFiles.value}',
                              Colors.teal,
                            ),
                            _item(
                              '单日最长录音',
                              '${_mineController.maxHourage.value}',
                              Colors.pink,
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            '过去12个月的热力图',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12.sp,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '较冷',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12.sp,
                            ),
                          ),
                          5.horizontalSpace,
                          Container(
                            width: 10.w,
                            height: 10.w,
                            margin: EdgeInsets.symmetric(horizontal: 1.w),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(2.w),
                            ),
                          ),
                          Container(
                            width: 10.w,
                            height: 10.w,
                            margin: EdgeInsets.symmetric(horizontal: 1.w),
                            decoration: BoxDecoration(
                              color: Colors.red[100],
                              borderRadius: BorderRadius.circular(2.w),
                            ),
                          ),
                          Container(
                            width: 10.w,
                            height: 10.w,
                            margin: EdgeInsets.symmetric(horizontal: 1.w),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(2.w),
                            ),
                          ),
                          5.horizontalSpace,
                          Text(
                            '较热',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12.sp,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        height: 50.w,
                        alignment: Alignment.center,
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 52,
                            mainAxisSpacing: 1.w,
                            crossAxisSpacing: 1.w,
                          ),
                          itemCount: 364,
                          itemBuilder: (BuildContext context, int index) {
                            final col = index % 52;
                            final row = index ~/ 52;
                            final vIndex = row + col * 7;

                            int type = 0;
                            if (_mineController.statistics
                                .containsKey(vIndex + 1)) {
                              if (_mineController.statistics[vIndex + 1]
                                      ['count'] <=
                                  _mineController.averageNumberFiles) {
                                type = 1;
                              } else {
                                type = 2;
                              }
                            }
                            return Container(
                              color: type == 0
                                  ? Colors.grey[200]
                                  : type == 1
                                      ? Colors.red[100]
                                      : Colors.red,
                            );
                          },
                        ),
                      ),
                      DefaultTextStyle(
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 10.sp,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Text('Jan'),
                            Text('Feb'),
                            Text('Mar'),
                            Text('Apr'),
                            Text('May'),
                            Text('Jun'),
                            Text('Jul'),
                            Text('Aug'),
                            Text('Sep'),
                            Text('Oct'),
                            Text('Nov'),
                            Text('Dec'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 10.w),
              Row(
                children: [
                  _button(Icons.share, '分享图片', Colors.deepOrange, () async {
                    EasyLoading.show();
                    Uint8List pngBytes = await _generate();
                    final tempDir = await getTemporaryDirectory();
                    final String fileName =
                        'share_${DateTime.now().millisecondsSinceEpoch}.png';
                    final file = File('${tempDir.path}/$fileName');
                    await file.writeAsBytes(pngBytes);
                    final result = await SharePlus.instance.share(ShareParams(
                      text: '分享 Voitrans',
                      files: [XFile(file.path)],
                    ));
                    if (result.status == ShareResultStatus.success) {
                      Get.back();
                      EasyLoading.showToast('分享完成！');
                    }
                    EasyLoading.dismiss();
                  }),
                  10.horizontalSpace,
                  _button(Icons.download, '保存图片', Colors.cyan, () async {
                    EasyLoading.show();
                    Uint8List pngBytes = await _generate();
                    final result = await ImageGallerySaverPlus.saveImage(
                      pngBytes,
                      quality: 100,
                    );
                    if (result['isSuccess']) {
                      Get.back();
                      EasyLoading.showToast('保存成功');
                    } else {
                      EasyLoading.showToast('保存失败');
                    }
                    EasyLoading.dismiss();
                  }),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _item(String unit, String amount, Color color) {
    return Container(
      width: 105.w,
      height: 70.w,
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8.w),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            unit,
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12.sp,
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              color: Colors.black87,
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _button(IconData icon, String title, Color color, Function() onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.w),
          ),
          child: Container(
            height: 60.w,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16.w),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 25.w,
                ),
                5.horizontalSpace,
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 16.sp,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _generate() async {
    RenderRepaintBoundary boundary =
        _posterKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    ui.Image image = await boundary.toImage(pixelRatio: 6.0);
    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    Uint8List pngBytes = byteData!.buffer.asUint8List();
    return pngBytes;
  }
}
