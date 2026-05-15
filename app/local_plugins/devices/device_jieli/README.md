# device_jieli

Flutter plugin around the JieLi (杰理) RCSP Bluetooth SDK. Provides a vendor-agnostic
MethodChannel / EventChannel surface (`device_jieli/method`, `device_jieli/event`)
so Dart-side code can scan / connect / query / OTA / translate against JieLi earpieces
on both Android and iOS.

## Platforms

| Platform | Native SDK | Status |
|---|---|---|
| Android | `android/libs/jl_bluetooth_rcsp_*.aar` etc. | Functional (used in production demo) |
| iOS     | `ios/Frameworks/JL_BLEKit.xcframework` etc. (from `JIELI-IOS-Release/Libs`) | **Compiles,真机验证未完成** — see [CHANGELOG.md](CHANGELOG.md) for the per-feature status matrix. |

## iOS setup

The plugin ships every required `.xcframework` under `ios/Frameworks/`. When the upstream
SDK in `JIELI-IOS-Release/Libs/` updates, mirror the new `.xcframework` directories on
top of `ios/Frameworks/` (overwrite is safe) and `pod install` again in the host app.

Minimum target: iOS 12.

The host app must declare in `Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>用于连接杰理蓝牙耳机</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>用于连接杰理蓝牙耳机</string>
<key>NSMicrophoneUsageDescription</key>
<string>用于翻译 / 语音助手录音</string>
```

## Channel surface

Dart API lives in [`lib/device_jieli.dart`](lib/device_jieli.dart). Native code on either
platform implements the same set of method calls and emits the same event payload schema —
the iOS implementation lives in [`ios/Classes/`](ios/Classes/), the Android
implementation in [`android/src/main/kotlin/com/jielihome/jielihome/`](android/src/main/kotlin/com/jielihome/jielihome/).

For background on the RCSP commands and translation pipeline see
[`JIELI_SDK_COMMANDS.md`](JIELI_SDK_COMMANDS.md).
