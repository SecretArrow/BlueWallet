Pod::Spec.new do |s|
  s.name             = 'octra_native'
  s.version          = '1.0.0'
  s.summary          = 'Octra native C/C++ crypto library for iOS Dart FFI'
  s.homepage         = 'https://octra.io'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Octra' => 'dev@octra.io' }
  s.platform         = :ios, '13.0'
  s.static_framework = true

  # Paths relative to this podspec: ios/octra_native/octra_native.podspec
  # Go up 3 levels (octra_native → ios → flutter → blue_wallet) to reach webcli
  WEBCLI      = File.expand_path('../../../webcli',                    __FILE__)
  ANDROID_CPP = File.expand_path('../../android/app/src/main/cpp', __FILE__)

  s.source = { :path => '.' }
  s.source_files = [
    "#{ANDROID_CPP}/octra_ffi.cpp",
    "#{WEBCLI}/lib/tweetnacl.c",
    "#{WEBCLI}/lib/randombytes.c",
    "#{WEBCLI}/pvac/pvac_c_api.cpp",
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
