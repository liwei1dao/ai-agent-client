import 'dart:async';

import 'package:ai_plugin_interface/ai_plugin_interface.dart' as ai;

import '../agent_event.dart';
import 'web_agent.dart';
import 'web_service_factory.dart';

/// STS chat agent — thin wrapper over the STS plugin. Ports StsChatAgentSession.kt.
///
/// Adapter responsibilities:
///
/// * Translate [ai.StsEvent] lifecycle (per ai_plugin_interface/sts_plugin.dart)
///   into the generic [AgentEvent] stream consumed by the chat UI.
/// * Compute text deltas for the bot side — [ai.StsEventType.recognizing]
///   carries a cumulative snapshot, but [LlmEvent.textDelta] is expected to be
///   an incremental fragment (consumers append rather than replace).
/// * Map the `user` role to [SttEvent] and the `bot` role to [LlmEvent] so the
///   existing chat transcript renderer stays unchanged.
class WebStsChatAgent implements WebAgent {
  WebStsChatAgent(this._emit);

  final AgentEventEmitter _emit;

  late WebAgentConfig _config;
  late ai.StsPlugin _sts;
  StreamSubscription<ai.StsEvent>? _sub;

  // Per-requestId bot cumulative text (for computing textDelta from snapshots).
  final Map<String, String> _botCumulativeByRequestId = {};

  // Per-requestId bot finalized pieces (concatenated into the final fullText
  // for LlmEvent.done).
  final Map<String, StringBuffer> _botCommittedByRequestId = {};

  @override
  Future<void> initialize(WebAgentConfig config) async {
    _config = config;
    _sts = WebServiceFactory.createSts(config.stsVendor ?? 'doubao');
    await _sts.initialize(
      WebConfigParser.parseSts(config.stsConfigJson ?? '{}'),
    );
  }

  @override
  Future<void> connectService() async {
    _sub?.cancel();
    _sub = _sts.eventStream.listen(_onStsEvent);
    try {
      await _sts.startCall();
    } catch (e) {
      _emit(AgentErrorEvent(
        sessionId: _config.agentId,
        errorCode: 'sts_connect_error',
        message: e.toString(),
      ));
    }
  }

  @override
  Future<void> disconnectService() async {
    await _sts.stopCall();
    _emit(ServiceConnectionStateEvent(
      sessionId: _config.agentId,
      connectionState: ServiceConnectionState.disconnected,
    ));
  }

  @override
  Future<void> sendText(String requestId, String text) async {
    // STS is voice-only; ignore text input.
  }

  @override
  Future<void> startListening() async {}

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> setInputMode(String mode) async {
    _config.inputMode = mode;
    // STS plugin manages mic lifecycle on web via startCall; no extra hooks.
  }

  @override
  Future<void> interrupt() async {
    // Rely on STS plugin's playback interruption via recognitionStart on a
    // new requestId; no direct API call here.
  }

  @override
  Future<void> release() async {
    await _sub?.cancel();
    await _sts.dispose();
    _botCumulativeByRequestId.clear();
    _botCommittedByRequestId.clear();
  }

  // ==========================================================================
  // Event routing
  // ==========================================================================

  void _onStsEvent(ai.StsEvent e) {
    switch (e.type) {
      case ai.StsEventType.connected:
        _emit(ServiceConnectionStateEvent(
          sessionId: _config.agentId,
          connectionState: ServiceConnectionState.connected,
        ));
        break;

      case ai.StsEventType.disconnected:
        _emit(ServiceConnectionStateEvent(
          sessionId: _config.agentId,
          connectionState: ServiceConnectionState.disconnected,
        ));
        break;

      case ai.StsEventType.error:
      case ai.StsEventType.recognitionError:
      case ai.StsEventType.synthesisError:
        _emit(ServiceConnectionStateEvent(
          sessionId: _config.agentId,
          connectionState: ServiceConnectionState.error,
          errorMessage: e.errorMessage,
        ));
        _emit(AgentErrorEvent(
          sessionId: _config.agentId,
          requestId: e.requestId,
          errorCode: e.errorCode ?? 'sts_error',
          message: e.errorMessage ?? '',
        ));
        break;

      case ai.StsEventType.recognitionStart:
        // Nothing to emit at the agent layer — bookkeeping only. For the bot
        // role, wipe any prior cumulative/committed state in case a previous
        // round didn't clean up.
        if (e.role == ai.StsRole.bot && e.requestId != null) {
          _botCumulativeByRequestId[e.requestId!] = '';
          _botCommittedByRequestId[e.requestId!] = StringBuffer();
        }
        break;

      case ai.StsEventType.recognizing:
        _handleRecognizing(e);
        break;

      case ai.StsEventType.recognized:
        _handleRecognized(e);
        break;

      case ai.StsEventType.recognitionDone:
        _handleRecognitionDone(e);
        break;

      case ai.StsEventType.recognitionEnd:
        if (e.requestId != null) {
          _botCumulativeByRequestId.remove(e.requestId);
          _botCommittedByRequestId.remove(e.requestId);
        }
        break;

      // Synthesis / playback aren't surfaced to the chat transcript — the STS
      // plugin plays audio internally on the web. They're still part of the
      // protocol for future consumers (e.g. a waveform UI).
      case ai.StsEventType.synthesisStart:
      case ai.StsEventType.synthesizing:
      case ai.StsEventType.synthesized:
      case ai.StsEventType.synthesisEnd:
      case ai.StsEventType.playbackStart:
      case ai.StsEventType.playbackEnd:
      case ai.StsEventType.audioChunk:
        break;
    }
  }

  // ==========================================================================
  // Recognition event handlers
  // ==========================================================================

  void _handleRecognizing(ai.StsEvent e) {
    final requestId = e.requestId;
    final role = e.role;
    final text = e.text ?? '';
    if (requestId == null || role == null || text.isEmpty) return;

    if (role == ai.StsRole.user) {
      // User-side snapshot maps directly to SttEvent.partialResult — both use
      // cumulative snapshot semantics.
      _emit(SttEvent(
        sessionId: _config.agentId,
        requestId: requestId,
        kind: SttEventKind.partialResult,
        text: text,
      ));
      return;
    }

    // Bot side: cumulative snapshot → compute delta, emit LlmEvent.firstToken
    // so the chat UI's `_appendAssistant(textDelta)` continues to work.
    final last = _botCumulativeByRequestId[requestId] ?? '';
    final delta = _computeDelta(last, text);
    _botCumulativeByRequestId[requestId] = text;
    if (delta.isEmpty) return;
    _emit(LlmEvent(
      sessionId: _config.agentId,
      requestId: requestId,
      kind: LlmEventKind.firstToken,
      textDelta: delta,
    ));
  }

  void _handleRecognized(ai.StsEvent e) {
    final requestId = e.requestId;
    final role = e.role;
    final text = e.text ?? '';
    if (requestId == null || role == null || text.isEmpty) return;

    if (role == ai.StsRole.user) {
      _emit(SttEvent(
        sessionId: _config.agentId,
        requestId: requestId,
        kind: SttEventKind.finalResult,
        text: text,
      ));
      return;
    }

    // Bot side: `text` is the finalized segment for this sentence. Flush any
    // remaining delta between the last cumulative snapshot and the commit.
    final last = _botCumulativeByRequestId[requestId] ?? '';
    final delta = _computeDelta(last, text);
    if (delta.isNotEmpty) {
      _emit(LlmEvent(
        sessionId: _config.agentId,
        requestId: requestId,
        kind: LlmEventKind.firstToken,
        textDelta: delta,
      ));
    }
    // Reset cumulative; if more recognizing arrives in the same role (multi-
    // segment), it starts a fresh snapshot from "".
    _botCumulativeByRequestId[requestId] = '';
    _botCommittedByRequestId
        .putIfAbsent(requestId, () => StringBuffer())
        .write(text);
  }

  void _handleRecognitionDone(ai.StsEvent e) {
    final requestId = e.requestId;
    final role = e.role;
    if (requestId == null || role == null) return;
    if (role != ai.StsRole.bot) return;

    // Bot side finished — emit LlmEvent.done with the concatenated fullText.
    final full = _botCommittedByRequestId[requestId]?.toString() ?? '';
    _emit(LlmEvent(
      sessionId: _config.agentId,
      requestId: requestId,
      kind: LlmEventKind.done,
      fullText: full,
    ));
  }

  // ==========================================================================
  // Helpers
  // ==========================================================================

  /// Returns the portion of [current] not already covered by [previous]. If
  /// [current] is not a strict extension of [previous] (rare — vendor replaced
  /// text mid-stream), returns [current] verbatim so nothing is lost.
  String _computeDelta(String previous, String current) {
    if (current.isEmpty) return '';
    if (previous.isEmpty) return current;
    if (current.length > previous.length && current.startsWith(previous)) {
      return current.substring(previous.length);
    }
    if (current == previous) return '';
    return current;
  }
}
