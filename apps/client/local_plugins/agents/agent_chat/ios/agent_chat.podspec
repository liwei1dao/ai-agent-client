Pod::Spec.new do |s|
  s.name             = 'agent_chat'
  s.version          = '0.1.0'
  s.summary          = 'Chat agent plugin (iOS stub).'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'AI Agent' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.platform         = :ios, '16.0'
  s.dependency 'Flutter'
  s.dependency 'ai_plugin_interface'
  s.swift_version    = '5.9'
end
