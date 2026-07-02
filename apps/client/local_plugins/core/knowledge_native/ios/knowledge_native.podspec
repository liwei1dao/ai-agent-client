Pod::Spec.new do |s|
  s.name             = 'knowledge_native'
  s.version          = '0.1.0'
  s.summary          = 'UniHelper 知识库原生引擎 (iOS Swift)'
  s.description      = <<-DESC
md 文库为真源 + 本地派生索引；端上嵌入、混合检索、用户级隔离。
供纯原生 agents_server 后台/设备唤醒直调；同时提供 Flutter UI 桥。
                       DESC
  s.homepage         = 'https://github.com/liwei1dao/UniHelper'
  s.license          = { :type => 'MIT' }
  s.author           = { 'UniHelper' => 'liwei1dao@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.library          = 'sqlite3'   # SqliteStores.swift 用系统 SQLite3
  s.platform         = :ios, '12.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
