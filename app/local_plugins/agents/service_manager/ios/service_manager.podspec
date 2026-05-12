Pod::Spec.new do |s|
  s.name             = 'service_manager'
  s.version          = '0.1.0'
  s.summary          = 'Service management and testing plugin (iOS stub).'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'AI Agent' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.platform         = :ios, '16.0'
  s.dependency 'Flutter'
  s.dependency 'ai_plugin_interface'
  s.dependency 'local_db'
  s.swift_version    = '5.9'
end
