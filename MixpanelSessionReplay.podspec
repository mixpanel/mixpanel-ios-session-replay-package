Pod::Spec.new do |s|
    s.name         = "MixpanelSessionReplay"
    s.version      = "1.0.0"
    s.summary      = "Mixpanel Session Replay library for iOS (Swift)"
    s.homepage     = "https://mixpanel.com"
    s.license = 'Apache License, Version 2.0'
    s.author       = { 'Mixpanel, Inc' => 'support@mixpanel.com' }
    s.source       = { :git => "https://github.com/mixpanel/mixpanel-ios-session-replay-package.git", :branch => "main", :tag => "#{s.version}" }
    s.vendored_frameworks = "MixpanelSessionReplay.xcframework"
    s.platform = :ios
    s.swift_version = "5.0"
    s.ios.deployment_target  = '13.0'
    s.ios.frameworks = 'UIKit', 'Foundation', 'WebKit', 'MapKit'
end
