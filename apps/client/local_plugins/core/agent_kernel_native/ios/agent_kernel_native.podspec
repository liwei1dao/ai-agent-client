Pod::Spec.new do |s|
  s.name             = 'agent_kernel_native'
  s.version          = '0.1.0'
  s.summary          = 'UniHelper 多 Agent 团队编排内核 (iOS Swift)'
  s.description      = '管家 Manager + 专员 + 路由 + WakeBus；供纯原生 agents_server 直接使用。'
  s.homepage         = 'https://github.com/liwei1dao/UniHelper'
  s.license          = { :type => 'MIT' }
  s.author           = { 'UniHelper' => 'liwei1dao@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
