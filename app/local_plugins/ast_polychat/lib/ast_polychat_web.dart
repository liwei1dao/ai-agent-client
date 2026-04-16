import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:ai_plugin_interface/ai_plugin_interface.dart';

class AstPolychatWeb {
  static void registerWith(Registrar registrar) {}
}

class AstPolychatPluginWeb implements AstPlugin {
  @override
  Future<void> initialize(AstConfig config) async {
    throw UnimplementedError('ast_polychat web SDK not yet integrated');
  }

  @override
  Future<void> startCall() async {
    throw UnimplementedError('ast_polychat web SDK not yet integrated');
  }

  @override
  void sendAudio(List<int> pcmData) {}

  @override
  Future<void> stopCall() async {}

  @override
  Stream<AstEvent> get eventStream => const Stream.empty();

  @override
  Future<void> dispose() async {}
}
