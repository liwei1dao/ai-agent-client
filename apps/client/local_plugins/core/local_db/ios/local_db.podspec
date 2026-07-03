Pod::Spec.new do |s|
  s.name             = 'local_db'
  s.version          = '0.1.0'
  s.summary          = 'Native SQLite data center (GRDB)'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'AI Agent' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.platform         = :ios, '16.0'
  s.dependency 'Flutter'
  s.dependency 'GRDB.swift', '~> 6.0'
  s.swift_version    = '5.9'
end
