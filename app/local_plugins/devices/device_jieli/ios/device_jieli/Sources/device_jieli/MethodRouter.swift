import Flutter
import Foundation

/// 与 Android 端 `MethodRouter` 同语义：把 Dart MethodChannel 调用映射到 server 内的各 feature 模块。
/// 任何 throws/exception 统一兜底 `PLUGIN_ERR`，避免 Dart 端拿到悬空 Future。
public final class MethodRouter {

    private let server: JieliHomeServer
    public init(server: JieliHomeServer) { self.server = server }

    public func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = (call.arguments as? [String: Any]) ?? [:]
        do {
            try route(method: call.method, args: args, result: result)
        } catch {
            result(FlutterError(code: "PLUGIN_ERR", message: error.localizedDescription, details: nil))
        }
    }

    private func route(method: String, args: [String: Any], result: @escaping FlutterResult) throws {
        switch method {
        case "getPlatformVersion":
            result("iOS \(UIDevice.current.systemVersion)")

        case "initialize":
            server.initialize(
                multiDevice: args["multiDevice"] as? Bool ?? true,
                skipNoNameDev: args["skipNoNameDev"] as? Bool ?? false,
                enableLog: args["enableLog"] as? Bool ?? false
            )
            result(true)

        // ───── Scan ─────
        case "startScan":
            let timeoutMs = (args["timeoutMs"] as? NSNumber)?.intValue ?? 30_000
            let nameList = args["nameList"] as? [String] ?? []
            let uuidList = args["uuidList"] as? [String] ?? []
            let skipUnnamed = args["skipUnnamed"] as? Bool ?? true
            do {
                try server.scanFeature.startScan(
                    timeoutMs: timeoutMs,
                    nameList: nameList,
                    uuidList: uuidList,
                    skipUnnamed: skipUnnamed
                )
                result(true)
            } catch {
                result(FlutterError(code: "SCAN_FAILED", message: error.localizedDescription, details: nil))
            }

        case "stopScan":
            server.scanFeature.stopScan()
            result(true)

        case "isScanning":
            result(server.scanFeature.isScanning)

        // ───── Connect ─────
        case "connect":
            guard let address = args["address"] as? String, !address.isEmpty else {
                result(FlutterError(code: "BAD_ARG", message: "address required", details: nil)); return
            }
            server.connectFeature.connect(
                bleAddress: address,
                edrAddress: args["edrAddr"] as? String,
                deviceType: (args["deviceType"] as? NSNumber)?.intValue ?? -1,
                connectWay: (args["connectWay"] as? NSNumber)?.intValue ?? 0,
                // Dart 侧明确传 dualConnect=true 才做 BR/EDR 桥接升级，默认纯 BLE。
                dualConnect: (args["dualConnect"] as? Bool) ?? false
            ) { ok, errMsg in
                if ok { result(true) }
                else { result(FlutterError(code: "CONNECT_FAILED", message: errMsg ?? "connect failed", details: nil)) }
            }

        case "disconnect":
            guard let address = args["address"] as? String, !address.isEmpty else {
                result(FlutterError(code: "BAD_ARG", message: "address required", details: nil)); return
            }
            server.connectFeature.disconnect(address: address) { ok, errMsg in
                if ok { result(true) }
                else { result(FlutterError(code: "DISCONNECT_FAILED", message: errMsg ?? "disconnect failed", details: nil)) }
            }

        case "isConnected":
            guard let address = args["address"] as? String, !address.isEmpty else {
                result(FlutterError(code: "BAD_ARG", message: "address required", details: nil)); return
            }
            result(server.connectFeature.isConnected(address: address))

        case "connectedDevice":
            if let info = server.connectFeature.connectedDeviceInfo() {
                result(info)
            } else {
                result(nil)
            }

        // ───── Device info ─────
        case "deviceSnapshot":
            guard let address = args["address"] as? String, !address.isEmpty else {
                result(FlutterError(code: "BAD_ARG", message: "address required", details: nil)); return
            }
            result(server.deviceInfoFeature.snapshot(address: address))

        case "queryTargetInfo":
            guard let address = args["address"] as? String, !address.isEmpty else {
                result(FlutterError(code: "BAD_ARG", message: "address required", details: nil)); return
            }
            let mask = (args["mask"] as? NSNumber)?.intValue ?? 0x0F
            server.deviceInfoFeature.queryTargetInfo(address: address, mask: mask) { info, errCode, errMsg in
                if let info = info { result(info) }
                else { result(FlutterError(code: "TARGET_INFO_ERR", message: errMsg ?? "query failed", details: errCode)) }
            }

        // ───── Custom cmd ─────
        case "sendCustomCmd":
            guard let address = args["address"] as? String, !address.isEmpty else {
                result(FlutterError(code: "BAD_ARG", message: "address required", details: nil)); return
            }
            guard let opCode = (args["opCode"] as? NSNumber)?.intValue else {
                result(FlutterError(code: "BAD_ARG", message: "opCode required", details: nil)); return
            }
            let payloadBytes: [UInt8] = {
                if let arr = args["payload"] as? [Int] { return arr.map { UInt8(truncatingIfNeeded: $0) } }
                if let arr = args["payload"] as? [NSNumber] { return arr.map { UInt8(truncatingIfNeeded: $0.intValue) } }
                if let typed = args["payload"] as? FlutterStandardTypedData {
                    return [UInt8](typed.data)
                }
                return []
            }()
            server.customCmdFeature.send(address: address, opCode: opCode, payload: Data(payloadBytes)) { ok, data, errCode, errMsg in
                if ok {
                    result(data.map { [UInt8]($0) } ?? [])
                } else {
                    result(FlutterError(code: "CUSTOM_CMD_ERR", message: errMsg ?? "custom cmd failed", details: errCode))
                }
            }

        // ───── Translation ─────
        case "startTranslation":
            guard let modeId = (args["modeId"] as? NSNumber)?.intValue else {
                result(FlutterError(code: "BAD_ARG", message: "modeId required", details: nil)); return
            }
            let innerArgs = args["args"] as? [String: Any] ?? [:]
            print("[JieliRouter] startTranslation modeId=\(modeId) args=\(innerArgs) " +
                  "assistantRunning=\(server.assistantBridge.isRunning) " +
                  "deviceRecording=\(server.deviceRecordFeature.isRecording) " +
                  "translationWorking=\(server.translationFeature.isWorking)")
            // 设备录音 / AI 助理 与翻译互斥（同一 JLTranslationManager session）
            if server.assistantBridge.isRunning {
                print("[JieliRouter] startTranslation: stopping AssistantBridge first")
                server.assistantBridge.stop()
            }
            if server.deviceRecordFeature.isRecording {
                print("[JieliRouter] startTranslation: stopping DeviceRecord first")
                server.deviceRecordFeature.stop()
            }
            server.translationFeature.start(modeId: modeId, args: innerArgs) { ok, errMsg in
                print("[JieliRouter] startTranslation result modeId=\(modeId) ok=\(ok) err=\(errMsg ?? "nil")")
                if ok { result(true) }
                else { result(FlutterError(code: "TRANSLATION_ERR", message: errMsg ?? "start failed", details: nil)) }
            }

        case "stopTranslation":
            server.translationFeature.stop()
            result(true)

        case "translationStatus":
            result([
                "working": server.translationFeature.isWorking,
                "modeId": server.translationFeature.currentModeId as Any,
                "inputStreams": server.translationFeature.currentInputStreams,
                "outputStreams": server.translationFeature.currentOutputStreams,
            ] as [String: Any?])

        case "feedTranslatedAudio":
            guard let streamId = args["streamId"] as? String else {
                result(FlutterError(code: "BAD_ARG", message: "streamId required", details: nil)); return
            }
            guard let pcm = (args["pcm"] as? FlutterStandardTypedData)?.data else {
                result(FlutterError(code: "BAD_ARG", message: "pcm required", details: nil)); return
            }
            let sr = (args["sampleRate"] as? NSNumber)?.intValue ?? 16000
            let ch = (args["channels"] as? NSNumber)?.intValue ?? 1
            let bits = (args["bitsPerSample"] as? NSNumber)?.intValue ?? 16
            let isFinal = args["final"] as? Bool ?? false
            // 诊断：只在段尾或路由失败时打。
            let ok = server.translationFeature.feedTranslatedAudio(
                streamId: streamId,
                pcm: pcm,
                sampleRate: sr, channels: ch, bitsPerSample: bits,
                isFinal: isFinal
            )
            if isFinal || !ok {
                NSLog("[MethodRouter] feedTranslatedAudio streamId=%@ pcm=%dB isFinal=%@ routed=%@",
                      streamId, pcm.count, isFinal ? "true" : "false", ok ? "true" : "false")
            }
            result(ok)

        case "feedTranslationResult":
            server.translationFeature.feedTranslationResult(
                srcLang: args["srcLang"] as? String,
                srcText: args["srcText"] as? String,
                destLang: args["destLang"] as? String,
                destText: args["destText"] as? String,
                requestId: args["requestId"] as? String
            )
            result(true)

        case "isSupportCallTranslationWithStereo":
            result(server.translationFeature.isSupportCallTranslationWithStereo(address: args["address"] as? String))

        case "feedAudioFilePcm":
            guard let pcm = (args["pcm"] as? FlutterStandardTypedData)?.data else {
                result(FlutterError(code: "BAD_ARG", message: "pcm required", details: nil)); return
            }
            let sr = (args["sampleRate"] as? NSNumber)?.intValue ?? 16000
            result(server.translationFeature.feedAudioFilePcm(pcm: pcm, sampleRate: sr))

        // ───── Speech assistant (cmd=4/5/210 路径) ─────
        case "speechIsRecording":
            result(server.speechFeature.isRecording(address: args["address"] as? String))

        case "speechStart":
            server.speechFeature.start(
                address: args["address"] as? String,
                voiceType: (args["voiceType"] as? NSNumber)?.intValue ?? 2,
                sampleRate: (args["sampleRate"] as? NSNumber)?.intValue ?? 16,
                vadWay: (args["vadWay"] as? NSNumber)?.intValue ?? 0
            ) { ok, msg in
                if ok { result(true) }
                else { result(FlutterError(code: "SPEECH_START_ERR", message: msg ?? "speech start failed", details: nil)) }
            }

        case "speechStop":
            server.speechFeature.stop(
                address: args["address"] as? String,
                reason: (args["reason"] as? NSNumber)?.intValue ?? 0
            ) { ok, msg in
                if ok { result(true) }
                else { result(FlutterError(code: "SPEECH_STOP_ERR", message: msg ?? "speech stop failed", details: nil)) }
            }

        // ───── AI 助理通路 ─────
        case "assistantStart":
            if server.translationFeature.isWorking { server.translationFeature.stop() }
            if server.deviceRecordFeature.isRecording { server.deviceRecordFeature.stop() }
            let ok = server.assistantBridge.start(
                address: args["address"] as? String,
                sampleRate: (args["sampleRate"] as? NSNumber)?.intValue ?? 16000
            )
            if ok { result(true) }
            else { result(FlutterError(code: "ASSISTANT_START_ERR", message: "assistant bridge start failed", details: nil)) }

        case "assistantStop":
            server.assistantBridge.stop()
            result(true)

        case "assistantIsRunning":
            result(server.assistantBridge.isRunning)

        // ───── 设备录音 ─────
        case "deviceRecordStart":
            let innerArgs = args["args"] as? [String: Any] ?? [:]
            if server.translationFeature.isWorking { server.translationFeature.stop() }
            if server.assistantBridge.isRunning { server.assistantBridge.stop() }
            server.deviceRecordFeature.start(args: innerArgs) { ok, errMsg in
                if ok { result(true) }
                else { result(FlutterError(code: "DEVICE_RECORD_ERR", message: errMsg ?? "device record start failed", details: nil)) }
            }

        case "deviceRecordStop":
            server.deviceRecordFeature.stop()
            result(true)

        case "deviceRecordStatus":
            result(["recording": server.deviceRecordFeature.isRecording])

        // ───── OTA ─────
        case "otaStart":
            guard let path = args["firmwareFilePath"] as? String, !path.isEmpty else {
                result(FlutterError(code: "BAD_ARG", message: "firmwareFilePath required", details: nil)); return
            }
            server.otaFeature.start(
                address: args["address"] as? String,
                firmwareFilePath: path,
                blockSize: (args["blockSize"] as? NSNumber)?.intValue ?? 512,
                fileFlagBytes: (args["fileFlag"] as? FlutterStandardTypedData)?.data ?? Data()
            )
            result(true)

        case "otaCancel":
            server.otaFeature.cancel()
            result(true)

        case "otaIsRunning":
            result(server.otaFeature.isRunning)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
