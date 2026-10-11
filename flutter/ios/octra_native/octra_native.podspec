Pod::Spec.new do |s|
  s.name             = 'octra_native'
  s.version          = '1.0.0'
  s.summary          = 'Octra native C/C++ crypto library for iOS Dart FFI'
  s.homepage         = 'https://octra.io'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Octra' => 'dev@octra.io' }
  s.platform         = :ios, '13.0'
  s.static_framework = true

  # NOTE: CocoaPods requires source_files to be RELATIVE (absolute paths from
  # File.expand_path fail validation). Both targets below are relative to
  # this podspec: ios/octra_native/octra_native.podspec.
  # Absolute paths are still fine for HEADER_SEARCH_PATHS (build-time only).
  WEBCLI      = File.expand_path('../../../webcli',                    __FILE__)
  ANDROID_CPP = File.expand_path('../../android/app/src/main/cpp', __FILE__)

  s.source = { :path => '.' }
  s.source_files = [
    '../../android/app/src/main/cpp/octra_ffi.cpp',
    '../../../webcli/lib/tweetnacl.c',
    '../../../webcli/lib/randombytes.c',
    '../../../webcli/pvac/pvac_c_api.cpp',
  ]
  s.public_header_files = []

  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS'              => "#{WEBCLI} #{WEBCLI}/lib #{WEBCLI}/pvac #{WEBCLI}/pvac/include #{ANDROID_CPP}",
    'CLANG_CXX_LANGUAGE_STANDARD'      => 'c++17',
    'CLANG_CXX_LIBRARY'                => 'libc++',
    'GCC_SYMBOLS_PRIVATE_EXTERN'       => 'YES',
    'OTHER_CFLAGS'                     => '-fvisibility=hidden -Wno-unused-function -Wno-sign-compare',
    'OTHER_CPLUSPLUSFLAGS'             => '-fvisibility=hidden -Wno-unused-function -Wno-sign-compare -Wno-unused-parameter -DOCTRA_BUILDING_DLL',
    'OTHER_CPLUSPLUSFLAGS[arch=arm64]' => '-fvisibility=hidden -Wno-unused-function -Wno-sign-compare -Wno-unused-parameter -DOCTRA_BUILDING_DLL -march=armv8-a+crypto',
    'OTHER_CPLUSPLUSFLAGS[arch=x86_64]'=> '-fvisibility=hidden -Wno-unused-function -Wno-sign-compare -Wno-unused-parameter -DOCTRA_BUILDING_DLL -maes -msse2',
  }

  s.dependency 'OpenSSL-Universal', '~> 3.3'
end
