/// Stub of `flutter_local_notifications` for the legacy meeting module port.
class FlutterLocalNotificationsPlugin {
  FlutterLocalNotificationsPlugin();

  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    void Function(NotificationResponse)? onDidReceiveNotificationResponse,
    void Function(NotificationResponse)?
        onDidReceiveBackgroundNotificationResponse,
  }) async =>
      true;

  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails, {
    String? payload,
  }) async {}

  Future<void> cancel(int id) async {}
  Future<void> cancelAll() async {}
}

class InitializationSettings {
  final AndroidInitializationSettings? android;
  final DarwinInitializationSettings? iOS;
  final DarwinInitializationSettings? macOS;

  const InitializationSettings({
    this.android,
    this.iOS,
    this.macOS,
  });
}

class AndroidInitializationSettings {
  const AndroidInitializationSettings(String defaultIcon);
}

class DarwinInitializationSettings {
  const DarwinInitializationSettings({
    bool requestAlertPermission = true,
    bool requestBadgePermission = true,
    bool requestSoundPermission = true,
  });
}

class NotificationDetails {
  final AndroidNotificationDetails? android;
  final DarwinNotificationDetails? iOS;
  final DarwinNotificationDetails? macOS;

  const NotificationDetails({
    this.android,
    this.iOS,
    this.macOS,
  });
}

class AndroidNotificationDetails {
  const AndroidNotificationDetails(
    String channelId,
    String channelName, {
    String? channelDescription,
    Importance importance = Importance.defaultImportance,
    Priority priority = Priority.defaultPriority,
    bool ongoing = false,
    bool autoCancel = true,
    bool playSound = false,
    bool enableVibration = false,
  });
}

class DarwinNotificationDetails {
  const DarwinNotificationDetails({
    bool presentAlert = true,
    bool presentBadge = true,
    bool presentSound = true,
  });
}

class NotificationResponse {
  String? payload;
  int? id;
}

enum Importance { min, low, defaultImportance, high, max }

enum Priority { min, low, defaultPriority, high, max }
