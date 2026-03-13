Pod::Spec.new do |s|
  s.name             = 'stt_azure'
  s.version          = '0.1.0'
  s.summary          = 'Azure Speech-to-Text plugin'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'AI Agent' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.platform         = :ios, '16.0'
  s.dependency 'Flutter'
  s.dependency 'MicrosoftCognitiveServicesSpeech-iOS', '~> 1.43'
  s.swift_version    = '5.9'
end
