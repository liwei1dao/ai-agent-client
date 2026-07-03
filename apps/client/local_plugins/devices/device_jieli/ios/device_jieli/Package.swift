// swift-tools-version: 5.9
//
// 杰理 RCSP SDK Flutter plugin —— iOS 走 Swift Package Manager。
//
// 所有杰理官方 xcframework（含 OPUS 编解码用的 JLAudioUnitKit）都作为
// 本 plugin 的私有 binaryTarget，放在 `Frameworks/` 下。Package 不依赖
// 任何其他本地 plugin —— 自包含。

import PackageDescription

let package = Package(
    name: "device_jieli",
    platforms: [
        .iOS("12.0"),
    ],
    products: [
        // Flutter 约定：library 产品名用 dash，target 名用 underscore
        .library(name: "device-jieli", targets: ["device_jieli"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "device_jieli",
            dependencies: [
                "JL_BLEKit",
                "JL_OTALib",
                "JL_AdvParse",
                "JL_HashPair",
                "JLLogHelper",
                "JLAudioUnitKit",
                "JLBmpConvertKit",
                "JLDialUnit",
                "JLPackageResKit",
            ],
            path: "Sources/device_jieli",
            linkerSettings: [
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("UIKit"),
                .linkedFramework("Foundation"),
            ]
        ),
        .binaryTarget(name: "JL_BLEKit",        path: "Frameworks/JL_BLEKit.xcframework"),
        .binaryTarget(name: "JL_OTALib",        path: "Frameworks/JL_OTALib.xcframework"),
        .binaryTarget(name: "JL_AdvParse",      path: "Frameworks/JL_AdvParse.xcframework"),
        .binaryTarget(name: "JL_HashPair",      path: "Frameworks/JL_HashPair.xcframework"),
        .binaryTarget(name: "JLLogHelper",      path: "Frameworks/JLLogHelper.xcframework"),
        .binaryTarget(name: "JLAudioUnitKit",   path: "Frameworks/JLAudioUnitKit.xcframework"),
        .binaryTarget(name: "JLBmpConvertKit",  path: "Frameworks/JLBmpConvertKit.xcframework"),
        .binaryTarget(name: "JLDialUnit",       path: "Frameworks/JLDialUnit.xcframework"),
        .binaryTarget(name: "JLPackageResKit",  path: "Frameworks/JLPackageResKit.xcframework"),
    ]
)
