Pod::Spec.new do |s|
  s.name                  = 'MixpanelSessionReplay'
  s.version               = '1.4.0'
  s.summary               = 'Mixpanel Session Replay library for iOS (Swift)'
  s.homepage              = 'https://github.com/mixpanel/mixpanel-ios-session-replay-package'
  s.license               = { :type => 'Apache License, Version 2.0', :file => 'LICENSE' }
  s.author                = { 'Mixpanel, Inc' => 'support@mixpanel.com' }
  s.source                = { :git => 'https://github.com/mixpanel/mixpanel-ios-session-replay-package.git', :tag => "#{s.version}" }
  s.platform = :ios
  s.ios.deployment_target = '13.0'
  s.swift_version         = '5.0'
  s.source_files          = 'MixpanelSessionReplay/MixpanelSessionReplay/**/*.{swift,h}'
  s.resource_bundles      = { 'MixpanelSessionReplay' => ['MixpanelSessionReplay/MixpanelSessionReplay/**/*.xcprivacy'] }
  s.ios.frameworks        = 'UIKit', 'Foundation', 'WebKit', 'MapKit'
  s.dependency 'MixpanelSwiftCommon', '~> 1.0.1'
end
