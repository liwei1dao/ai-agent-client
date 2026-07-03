Pod::Spec.new do |s|
  s.name             = 'ai_plugin_interface'
  s.version          = '0.1.0'
  s.summary          = 'Shared abstract interfaces and data classes for AI plugins'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'AI Agent' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.platform         = :ios, '16.0'
  s.dependency 'Flutter'
  # WebRTC backend for VoitransWebRtcSession (used by sts_polychat /
  # ast_polychat). Same vendor as the Android build's
  # `io.github.webrtc-sdk:android:125.6422.07`.
  s.dependency 'WebRTC-SDK', '~> 125.6422.07'
  s.swift_version    = '5.9'
end
