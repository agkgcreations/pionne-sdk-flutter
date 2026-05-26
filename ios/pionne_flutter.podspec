#
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint pionne_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'pionne_flutter'
  s.version          = '0.4.0'
  s.summary          = 'Native crash capture (MetricKit) for the Pionne Flutter SDK.'
  s.description      = <<-DESC
    Subscribes to MetricKit and surfaces native iOS crashes (NSException, signals,
    OOM, watchdog) on the next launch to the Pionne dashboard via a method channel.
  DESC
  s.homepage         = 'https://pionne.agkgcreations.fr'
  s.license          = { :type => 'MIT' }
  s.author           = { 'AGKG Creations' => 'contact@agkgcreations.fr' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  # Flutter's modern floor is iOS 12; MetricKit *crash* diagnostics need iOS 14,
  # so the Swift gates the subscription with `if #available(iOS 14.0, *)`.
  s.platform         = :ios, '12.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
