/// Stub of `audio_session` for the legacy meeting module port.
class AudioSession {
  static Future<AudioSession> get instance async => AudioSession();

  Future<void> configure(AudioSessionConfiguration config) async {}
  Future<bool> setActive(
    bool active, {
    AVAudioSessionSetActiveOptions? avOptions,
  }) async =>
      false;
}

class AudioSessionConfiguration {
  final AVAudioSessionCategory? avAudioSessionCategory;
  final AVAudioSessionCategoryOptions? avAudioSessionCategoryOptions;
  final AVAudioSessionMode? avAudioSessionMode;
  final AVAudioSessionRouteSharingPolicy? avAudioSessionRouteSharingPolicy;
  final AVAudioSessionSetActiveOptions? avAudioSessionSetActiveOptions;
  final AndroidAudioAttributes? androidAudioAttributes;
  final AndroidAudioFocusGainType? androidAudioFocusGainType;
  final bool androidWillPauseWhenDucked;

  const AudioSessionConfiguration({
    this.avAudioSessionCategory,
    this.avAudioSessionCategoryOptions,
    this.avAudioSessionMode,
    this.avAudioSessionRouteSharingPolicy,
    this.avAudioSessionSetActiveOptions,
    this.androidAudioAttributes,
    this.androidAudioFocusGainType,
    this.androidWillPauseWhenDucked = false,
  });
}

enum AVAudioSessionCategory {
  ambient,
  soloAmbient,
  playback,
  record,
  playAndRecord,
  multiRoute,
}

class AVAudioSessionCategoryOptions {
  final int _v;
  const AVAudioSessionCategoryOptions._(this._v);

  static const AVAudioSessionCategoryOptions none =
      AVAudioSessionCategoryOptions._(0);
  static const AVAudioSessionCategoryOptions allowBluetooth =
      AVAudioSessionCategoryOptions._(1);
  static const AVAudioSessionCategoryOptions allowBluetoothA2DP =
      AVAudioSessionCategoryOptions._(2);
  static const AVAudioSessionCategoryOptions defaultToSpeaker =
      AVAudioSessionCategoryOptions._(4);
  static const AVAudioSessionCategoryOptions mixWithOthers =
      AVAudioSessionCategoryOptions._(8);
  static const AVAudioSessionCategoryOptions duckOthers =
      AVAudioSessionCategoryOptions._(16);
  static const AVAudioSessionCategoryOptions allowAirPlay =
      AVAudioSessionCategoryOptions._(32);

  AVAudioSessionCategoryOptions operator |(AVAudioSessionCategoryOptions o) =>
      AVAudioSessionCategoryOptions._(_v | o._v);
}

enum AVAudioSessionMode {
  defaultMode,
  voiceChat,
  videoChat,
  gameChat,
  measurement,
  moviePlayback,
  spokenAudio,
  videoRecording,
  voicePrompt,
}

enum AVAudioSessionRouteSharingPolicy {
  defaultPolicy,
  longFormAudio,
  longFormVideo,
  independent,
}

class AVAudioSessionSetActiveOptions {
  final int _v;
  const AVAudioSessionSetActiveOptions._(this._v);

  static const AVAudioSessionSetActiveOptions none =
      AVAudioSessionSetActiveOptions._(0);
  static const AVAudioSessionSetActiveOptions notifyOthersOnDeactivation =
      AVAudioSessionSetActiveOptions._(1);

  AVAudioSessionSetActiveOptions operator |(
          AVAudioSessionSetActiveOptions o) =>
      AVAudioSessionSetActiveOptions._(_v | o._v);
}

class AndroidAudioAttributes {
  final AndroidAudioContentType? contentType;
  final AndroidAudioFlags? flags;
  final AndroidAudioUsage? usage;

  const AndroidAudioAttributes({
    this.contentType,
    this.flags,
    this.usage,
  });
}

enum AndroidAudioContentType { unknown, speech, music, movie, sonification }

class AndroidAudioFlags {
  final int _v;
  const AndroidAudioFlags._(this._v);

  static const AndroidAudioFlags none = AndroidAudioFlags._(0);
  static const AndroidAudioFlags audibilityEnforced = AndroidAudioFlags._(1);
}

enum AndroidAudioUsage {
  unknown,
  media,
  voiceCommunication,
  voiceCommunicationSignalling,
  alarm,
  notification,
  notificationRingtone,
  notificationCommunicationRequest,
  notificationCommunicationInstant,
  notificationCommunicationDelayed,
  notificationEvent,
  assistanceAccessibility,
  assistanceNavigationGuidance,
  assistanceSonification,
  game,
  assistant,
}

enum AndroidAudioFocusGainType {
  gain,
  gainTransient,
  gainTransientMayDuck,
  gainTransientExclusive,
}
