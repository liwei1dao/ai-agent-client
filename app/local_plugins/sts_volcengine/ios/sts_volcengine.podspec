Pod::Spec.new do |s|
  s.name             = 'sts_volcengine'
  s.version          = '0.1.0'
  s.summary          = 'Volcengine end-to-end STS plugin'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'AI Agent' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.platform         = :ios, '16.0'
  s.dependency 'Flutter'
  s.swift_version    = '5.9'
end
