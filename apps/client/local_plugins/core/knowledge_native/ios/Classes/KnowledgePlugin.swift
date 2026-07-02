import Flutter
import Foundation

/// Flutter UI 桥（供"我的→知识库"页）。
///
/// 主用户是纯原生 agents_server，直接 `KnowledgeEngine(...)` 调用、不经此桥。
public class KnowledgePlugin: NSObject, FlutterPlugin {
    private lazy var kb: KnowledgeEngine = {
        let base = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
        return KnowledgeEngine(vaultPath: base + "/kb_vault")
    }()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "ai.unihelper/knowledge",
                                           binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(KnowledgePlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "ingestMarkdown":
            result(kb.ingestMarkdown(
                userId: args["userId"] as? String ?? "default",
                title: args["title"] as? String ?? "",
                markdown: args["markdown"] as? String ?? "",
                kind: args["kind"] as? String ?? "note",
                sourceUri: args["sourceUri"] as? String,
                id: args["id"] as? String))
        case "retrieve":
            let hits = kb.retrieve(
                args["query"] as? String ?? "",
                k: args["k"] as? Int ?? 6,
                userId: args["userId"] as? String)
            result(hits.map { h in
                [
                    "chunkId": h.chunk.id,
                    "documentId": h.chunk.documentId,
                    "documentTitle": h.documentTitle as Any,
                    "text": h.chunk.text,
                    "score": h.score,
                    "heading": h.chunk.loc.heading as Any,
                ]
            })
        case "answerContext":
            result(kb.answerContext(
                args["query"] as? String ?? "",
                k: args["k"] as? Int ?? 6,
                userId: args["userId"] as? String))
        case "deleteDocument":
            kb.deleteDocument(args["docId"] as? String ?? "")
            result(nil)
        case "reindexFromVault":
            result(kb.reindexFromVault(userId: args["userId"] as? String))
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
