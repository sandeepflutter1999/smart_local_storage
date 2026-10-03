Pod::Spec.new do |s|
  s.name             = 'smart_local_cache'
  s.version          = '2.2.3'
  s.summary          = 'Pure Dart/Flutter local storage, no third-party packages.'
  s.description      = <<-DESC
Pure Dart/Flutter local storage plugin with no third-party pub packages.
                       DESC
  s.homepage         = 'https://github.com/sandeepflutter1999/smart_local_storage'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'sandeepflutter1999' => 'sandeepflutter1999@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'smart_local_cache/Sources/smart_local_cache/**/*.swift'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
