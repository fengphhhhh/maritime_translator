Pod::Spec.new do |s|
  s.name             = 'llama_ggml'
  s.version          = '0.1.2'
  s.summary          = 'llama.cpp for Flutter, on Metal.'
  s.description      = <<-DESC
Minimal Dart FFI plugin over llama.cpp b9700, built with the ggml Metal
backend so a small instruct model can translate on the iPhone GPU.
                       DESC
  s.homepage         = 'https://github.com/ggml-org/llama.cpp'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'marine_voice_translator' => 'noreply@example.com' }

  s.dependency 'Flutter'
  s.source           = { :path => '.' }

  s.source_files = [
    'Classes/llama_ggml.cpp',
    'Classes/llama/src/**/*.{cpp,c}',
    'Classes/llama/ggml/*.{c,cpp}',
    'Classes/llama/ggml/ggml-cpu/**/*.{c,cpp}',
    'Classes/llama/ggml/ggml-metal/*.{cpp,m,S}',
  ].join(', ')
  s.preserve_paths = 'Classes/llama/ggml/ggml-metal/*.metal', 'Classes/llama_ggml.exports'

  # Only the C ABI bridge is public; the vendored ggml tree must stay private.
  s.public_header_files = 'Classes/llama_ggml.h'
  s.static_framework = true

  s.platform = :ios, '15.6'
  s.ios.deployment_target  = '15.6'

  s.requires_arc = false

  s.xcconfig = {
    'IPHONEOS_DEPLOYMENT_TARGET' => '15.6',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
  }
  s.library = 'c++'
  s.frameworks = 'Accelerate', 'Foundation', 'Metal', 'MetalKit'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'GCC_SYMBOLS_PRIVATE_EXTERN' => 'YES',
    'USE_HEADERMAP' => 'NO',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'USER_HEADER_SEARCH_PATHS' => [
      '"$(PODS_TARGET_SRCROOT)/Classes"',
      '"$(PODS_TARGET_SRCROOT)/Classes/llama/include"',
      '"$(PODS_TARGET_SRCROOT)/Classes/llama/ggml-include"',
      '"$(PODS_TARGET_SRCROOT)/Classes/llama/ggml"',
      '"$(PODS_TARGET_SRCROOT)/Classes/llama/ggml/ggml-cpu"',
      '"$(PODS_TARGET_SRCROOT)/Classes/llama/ggml/ggml-metal"',
      '"$(PODS_TARGET_SRCROOT)/Classes/llama/src"',
    ].join(' '),
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) GGML_USE_CPU=1 GGML_USE_ACCELERATE=1 ACCELERATE_NEW_LAPACK=1 ACCELERATE_LAPACK_ILP64=1 GGML_USE_METAL=1 GGML_METAL_EMBED_LIBRARY=1 GGML_VERSION=\"b9700\" GGML_COMMIT=\"b9700\"',
    'OTHER_CFLAGS' => '$(inherited) -fvisibility=hidden -I"$(PODS_TARGET_SRCROOT)/Classes/llama/ggml/ggml-metal"',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -fvisibility=hidden -fvisibility-inlines-hidden',
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-exported_symbols_list,$(PODS_TARGET_SRCROOT)/Classes/llama_ggml.exports',
    'GCC_OPTIMIZATION_LEVEL' => '3',
  }
  s.swift_version = '5.0'
end
