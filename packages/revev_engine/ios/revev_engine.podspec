Pod::Spec.new do |s|
  s.name = 'revev_engine'
  s.version = '0.0.1'
  s.summary = 'RevEV native engine-sim adapter.'
  s.description = 'Shared combustion simulation with native mobile audio output.'
  s.homepage = 'https://github.com/ange-yaghi/engine-sim'
  s.license = { :type => 'MIT (upstream components)', :file => '../THIRD_PARTY_NOTICES.txt' }
  s.author = 'RevEV'
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.{h,mm}', '../native/engine_{preset,runtime}.{h,cpp}',
    '../native/portable.h', '../native/vendor/engine-sim/include/*.h',
    '../native/vendor/engine-sim/src/*.cpp',
    '../native/vendor/engine-sim/dependencies/submodules/simple-2d-constraint-solver/{include,src}/*.{h,cpp}'
  s.public_header_files = 'Classes/RevevEnginePlugin.h'
  s.preserve_paths = '../native/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.frameworks = 'AVFoundation', 'UIKit'
  s.libraries = 'c++'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../native/vendor/engine-sim/include"',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -O2 -include "${PODS_TARGET_SRCROOT}/../native/portable.h"'
  }
end
