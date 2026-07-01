/// 端上、零依赖、确定性的"特征哈希"嵌入。
library;

import 'dart:math';

import '../ports.dart';
import '../text/tokenizer.dart';

/// 用途：离线/无模型时的默认与回退实现，及单测可复现。
///
/// 真正的语义嵌入由平台层用 ONNX 本地模型（bge-small-zh / e5-small）实现同一
/// [EmbeddingProvider] 端口替换——业务与索引不变。
class HashingEmbedding implements EmbeddingProvider {
  @override
  final int dim;
  const HashingEmbedding({this.dim = 256});

  @override
  String get model => 'hashing-v1-$dim';

  @override
  Future<List<double>> embed(String text) async => _embedSync(text);

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async =>
      [for (final t in texts) _embedSync(t)];

  List<double> _embedSync(String text) {
    final v = List<double>.filled(dim, 0);
    for (final tok in tokenize(text)) {
      final h = fnv1a(tok);
      final idx = h % dim;
      final sign = (fnv1a('#$tok') & 1) == 0 ? 1.0 : -1.0;
      v[idx] += sign;
    }
    var norm = 0.0;
    for (final x in v) {
      norm += x * x;
    }
    norm = sqrt(norm);
    if (norm > 0) {
      for (var i = 0; i < dim; i++) {
        v[i] /= norm;
      }
    }
    return v;
  }
}
