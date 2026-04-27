import 'package:flutter/material.dart';
import 'package:talker_flutter/talker_flutter.dart';

import '../../../core/services/log_service.dart';

class LogViewerScreen extends StatelessWidget {
  const LogViewerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TalkerScreen(
      talker: LogService.instance.talker,
      appBarTitle: '日志',
    );
  }
}
