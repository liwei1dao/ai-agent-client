import Foundation

/// BERT WordPiece 分词（镜像 Kotlin WordPieceTokenizer）。需模型自带 vocab.txt。
final class WordPieceTokenizer {
    private let vocab: [String: Int]
    private let maxLen: Int
    private let doLowerCase: Bool
    private let clsId: Int
    private let sepId: Int
    private let unkId: Int

    init(vocab: [String: Int], maxLen: Int = 256, doLowerCase: Bool = true,
         cls: String = "[CLS]", sep: String = "[SEP]", unk: String = "[UNK]") {
        self.vocab = vocab
        self.maxLen = maxLen
        self.doLowerCase = doLowerCase
        clsId = vocab[cls] ?? 101
        sepId = vocab[sep] ?? 102
        unkId = vocab[unk] ?? 100
    }

    static func fromVocabText(_ text: String) -> [String: Int] {
        var m: [String: Int] = [:]
        for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let t = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if !t.isEmpty { m[t] = i }
        }
        return m
    }

    func encode(_ text: String) -> (ids: [Int64], mask: [Int64]) {
        var ids: [Int64] = [Int64(clsId)]
        outer: for word in basicTokenize(text) {
            for sub in wordpiece(word) {
                if ids.count >= maxLen - 1 { break outer }
                ids.append(Int64(vocab[sub] ?? unkId))
            }
        }
        ids.append(Int64(sepId))
        return (ids, [Int64](repeating: 1, count: ids.count))
    }

    private func basicTokenize(_ text: String) -> [String] {
        let s = doLowerCase ? text.lowercased() : text
        var out: [String] = []
        var buf = ""
        func flush() { if !buf.isEmpty { out.append(buf); buf = "" } }
        for ch in s {
            let scalar = ch.unicodeScalars.first?.value ?? 0
            let isCjk = scalar >= 0x4E00 && scalar <= 0x9FFF
            if ch.isWhitespace {
                flush()
            } else if isCjk {
                flush(); out.append(String(ch))
            } else if !(ch.isLetter || ch.isNumber) {
                flush(); out.append(String(ch))
            } else {
                buf.append(ch)
            }
        }
        flush()
        return out
    }

    private func wordpiece(_ word: String) -> [String] {
        if word.isEmpty { return [] }
        if vocab[word] != nil { return [word] }
        var out: [String] = []
        let chars = Array(word)
        var start = 0
        while start < chars.count {
            var end = chars.count
            var cur: String? = nil
            while start < end {
                var piece = String(chars[start..<end])
                if start > 0 { piece = "##" + piece }
                if vocab[piece] != nil { cur = piece; break }
                end -= 1
            }
            guard let c = cur else { return ["[UNK]"] }
            out.append(c)
            start = end
        }
        return out
    }
}

/// ONNX 前向端口：由 app 用 onnxruntime-objc 实现（见 README）。返回 [seqLen][hidden]。
protocol OnnxSession {
    func run(inputIds: [Int64], attentionMask: [Int64]) -> [[Float]]
}

/// 端上 ONNX 句向量嵌入：WordPiece 分词 + masked mean-pool + L2 归一；ORT 前向经 [OnnxSession]。
final class OnnxEmbedding: EmbeddingProvider {
    let dim: Int
    let model: String
    private let tokenizer: WordPieceTokenizer
    private let session: OnnxSession

    init(tokenizer: WordPieceTokenizer, session: OnnxSession,
         dim: Int = 384, model: String = "bge-small-zh-v1.5") {
        self.tokenizer = tokenizer
        self.session = session
        self.dim = dim
        self.model = model
    }

    func embed(_ text: String) -> [Double] {
        let (ids, mask) = tokenizer.encode(text)
        let hidden = session.run(inputIds: ids, attentionMask: mask)
        var pooled = [Double](repeating: 0, count: dim)
        var denom = 0.0
        for i in hidden.indices {
            if i < mask.count && mask[i] == 0 { continue }
            denom += 1
            let row = hidden[i]
            let n = min(dim, row.count)
            for j in 0..<n { pooled[j] += Double(row[j]) }
        }
        if denom > 0 { for j in 0..<dim { pooled[j] /= denom } }
        var norm = 0.0
        for x in pooled { norm += x * x }
        norm = norm.squareRoot()
        if norm > 0 { for j in 0..<dim { pooled[j] /= norm } }
        return pooled
    }
}
