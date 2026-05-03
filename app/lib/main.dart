import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_storage/get_storage.dart';
import 'app.dart';
import 'core/services/log_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LogService.instance.init();
  await dotenv.load(fileName: '.env', mergeWith: {}, isOptional: true);
  // 移植自 deepvoice_client_liwei 的会议模块依赖 GetStorage
  await GetStorage.init();
  runApp(const ProviderScope(child: App()));
}
