import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:ai_plugin_interface/ai_plugin_interface.dart';

class StsPolychatWeb {
  static void registerWith(Registrar registrar) {}
}

class StsPolychatPluginWeb implements StsPlugin {
  @override
  Future<void> initialize(StsConfig config) async {
    throw UnimplementedError('sts_polychat web SDK not yet integrated');
  }

  @override
  Future<void> startCall() async {
    throw UnimplementedError('sts_polychat web SDK not yet integrated');
  }

  @override
  void sendAudio(List<int> pcmData) {}

  @override
  Future<void> stopCall() async {}

  @override
  Stream<StsEvent> get eventStream => const Stream.empty();

  @override
  Future<void> dispose() async {}
}
