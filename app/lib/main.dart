import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/services/log_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LogService.instance.init();
  await dotenv.load(fileName: '.env', mergeWith: {}, isOptional: true);
  runApp(const ProviderScope(child: App()));
}
