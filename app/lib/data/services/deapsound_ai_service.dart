/// Stub for DeapsoundAIService used by ported meeting templates / AI sheet.
///
/// The real implementation streamed chat completions from a third-party
/// service. In `ai-agent-client` we keep it as a no-op so the UI compiles
/// — the surface area is intentionally minimal.
class DeapsoundAIService {
  DeapsoundAIService();

  Stream<String> sendMessageStream({
    required List<Map<String, String>> messages,
    String? systemPrompt,
    String? userProperties,
  }) async* {
    // Yields nothing — runtime AI features are disabled in this stub.
  }
}
