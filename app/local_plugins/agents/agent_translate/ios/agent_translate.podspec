Pod::Spec.new do |s|
  s.name             = 'agent_translate'
  s.version          = '0.1.0'
  s.summary          = 'Translate agent plugin (iOS stub).'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'AI Agent' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.platform         = :ios, '16.0'
  s.dependency 'Flutter'
  s.swift_version    = '5.9'
end
