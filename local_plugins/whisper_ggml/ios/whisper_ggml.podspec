Pod::Spec.new do |s|
  s.name             = 'whisper_ggml'
  s.version          = '2.6.0-metal.6'
  s.summary          = 'whisper.cpp for Flutter, forked to run on Metal.'
  s.description      = <<-DESC
Fork of whisper_ggml 2.6.0 with the ggml Metal backend vendored in from
whisper.cpp v1.9.1. Upstream ships only the CPU/Accelerate backend on iOS.
                       DESC
  s.homepage         = 'https://github.com/sk3llo/whisper_ggml'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'kapraton@gmail.com' }

  s.dependency 'Flutter'
  s.source           = { :path => '.' }

  # Compile units only — no vendored .h/.hpp here. ggml headers stay private
  # and are resolved through USER_HEADER_SEARCH_PATHS below, so they never
  # flatten into the framework module next to llama_ggml's copy of ggml.
  s.source_files = [
    'Classes/WhisperGgmlPlugin.h',
    'Classes/WhisperGgmlPlugin.m',
    'Classes/whisper_ggml_ffi.h',
    'Classes/whisper_flutter_plus.cpp',
    'Classes/whisper/src/whisper.cpp',
    'Classes/whisper/ggml/src/*.{c,cpp}',
    'Classes/whisper/ggml/src/ggml-cpu/**/*.{c,cpp}',
    'Classes/whisper/ggml/src/ggml-metal/*.{cpp,m,S}',
  ]
  # Only the FFI bridge header is public; ggml stays private.
  s.public_header_files = 'Classes/WhisperGgmlPlugin.h', 'Classes/whisper_ggml_ffi.h'
  s.preserve_paths = 'Classes/whisper/ggml/src/ggml-metal/*.metal', 'Classes/whisper_ggml.exports'
  s.static_framework = true

  s.platform = :ios, '15.6'
  s.ios.deployment_target  = '15.6'

  s.requires_arc = 'Classes/WhisperGgmlPlugin.m'

  s.xcconfig = {
    'IPHONEOS_DEPLOYMENT_TARGET' => '15.6',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
  }
  s.library = 'c++'
  s.frameworks = 'Accelerate', 'Foundation', 'Metal', 'MetalKit'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'USE_HEADERMAP' => 'NO',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    # User headers are not exported to dependent targets (Runner, other pods).
    'USER_HEADER_SEARCH_PATHS' => [
      '"$(PODS_TARGET_SRCROOT)/Classes"',
      '"$(PODS_TARGET_SRCROOT)/Classes/whisper/include"',
      '"$(PODS_TARGET_SRCROOT)/Classes/whisper/ggml/include"',
      '"$(PODS_TARGET_SRCROOT)/Classes/whisper/ggml/src"',
      '"$(PODS_TARGET_SRCROOT)/Classes/whisper/ggml/src/ggml-cpu"',
      '"$(PODS_TARGET_SRCROOT)/Classes/whisper/ggml/src/ggml-metal"',
      '"$(PODS_TARGET_SRCROOT)/Classes/whisper/src"',
    ].join(' '),
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) GGML_USE_CPU=1 GGML_USE_ACCELERATE=1 ACCELERATE_NEW_LAPACK=1 ACCELERATE_LAPACK_ILP64=1 GGML_USE_METAL=1 GGML_METAL_EMBED_LIBRARY=1 GGML_VERSION=\"1.9.1\" GGML_COMMIT=\"whisper.cpp-v1.9.1\" WHISPER_VERSION=\"1.9.1\"',
    'OTHER_CFLAGS' => '$(inherited) -fvisibility=hidden -I"$(PODS_TARGET_SRCROOT)/Classes/whisper/ggml/src/ggml-metal"',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -fvisibility=hidden -fvisibility-inlines-hidden',
    'GCC_OPTIMIZATION_LEVEL' => '3',
  }
  s.swift_version = '5.0'
end
