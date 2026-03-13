Pod::Spec.new do |s|
  s.name             = 'agent_runtime'
  s.version          = '0.1.0'
  s.summary          = 'Agent execution engine — native Background Audio + pipeline'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'AI Agent' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.platform         = :ios, '16.0'
  s.dependency 'Flutter'
  s.swift_version    = '5.9'
  # local_db 直接源码依赖（同 workspace 内）
  s.dependency 'local_db'
end
