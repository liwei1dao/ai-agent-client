/// Stub of `flutter_blue_plus` for the legacy meeting module port.
///
/// Bluetooth functionality is disabled in `ai-agent-client`. This file
/// exposes just enough surface area to compile the original code.
import 'dart:async';

class Guid {
  final String value;
  Guid(this.value);

  @override
  bool operator ==(Object other) => other is Guid && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class BluetoothDevice {
  String platformName = '';

  Future<void> connect() async {}
  Future<void> disconnect() async {}

  Future<List<BluetoothService>> discoverServices() async => const [];
}

class BluetoothService {
  Guid serviceUuid = Guid('');
  List<BluetoothCharacteristic> characteristics = const [];
}

class BluetoothCharacteristic {
  Guid characteristicUuid = Guid('');
  Stream<List<int>> get onValueReceived => const Stream.empty();

  Future<void> setNotifyValue(bool value) async {}

  Future<void> write(List<int> value,
      {bool withoutResponse = false}) async {}
}

class ScanResult {
  BluetoothDevice device = BluetoothDevice();
}

class FlutterBluePlus {
  static Stream<List<ScanResult>> get scanResults => const Stream.empty();
  static Stream<bool> get isScanning => const Stream.empty();

  static Future<void> startScan({
    Duration? timeout,
    List<Guid>? withServices,
    List<String>? withNames,
  }) async {}

  static Future<void> stopScan() async {}
}
