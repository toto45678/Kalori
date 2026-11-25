Pod::Spec.new do |s|
  s.name = 'KaloriHealth'
  s.version = '1.0.0'
  s.summary = 'Reads energy burned and body weight from Apple Health for Kalori'
  s.license = { :type => 'Proprietary', :text => 'Kalori' }
  s.homepage = 'https://toto45678.github.io/kalori/'
  s.author = 'Kalori'
  s.source = { :git => 'https://github.com/toto45678/kalori.git', :tag => s.version.to_s }
  s.source_files = 'ios/Plugin/**/*.{swift,h,m}'
  s.ios.deployment_target = '15.0'
  s.dependency 'Capacitor'
  s.frameworks = 'HealthKit'
  s.swift_version = '5.1'
end
