/// Stub of `wifi_iot` for the legacy meeting module port.
enum NetworkSecurity { WPA, WEP, NONE }

class WiFiForIoTPlugin {
  static Future<bool> connect(
    String ssid, {
    String? password,
    NetworkSecurity security = NetworkSecurity.NONE,
  }) async =>
      false;

  static Future<bool> disconnect() async => false;

  static Future<bool> forceWifiUsage(bool useWifi) async => false;
}
