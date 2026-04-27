import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterEventChannel(
        name: NativeLogBridge.channel,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setStreamHandler(NativeLogBridge())
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
