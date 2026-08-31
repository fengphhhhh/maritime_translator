Pod::Spec.new do |s|
  s.name             = 'llama_ggml'
  s.version          = '0.1.0'
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

  # .m  -> ggml-metal-context.m / ggml-metal-device.m (the Metal backend)
  # .S  -> ggml-metal-embed.S, which .incbin's the shader into the binary
  #
  # ggml-metal.metal and ggml-metal-embed.metal are deliberately NOT compiled:
  # the shader is compiled at runtime from the embedded source, with the
  # feature macros that match the device.
  s.source_files = 'Classes/**/*.{cpp,c,h,hpp,m,S}'
  s.preserve_paths = 'Classes/llama/ggml/ggml-metal/*.metal'

  # Flattening every header into the framework would collide: the ggml and
  # llama trees both carry common.h, and ggml-cpu adds a third.
  s.public_header_files = 'Classes/llama_ggml.h'
  s.platform = :ios, '15.6'
  s.ios.deployment_target  = '15.6'

  # ggml-metal-context.m and ggml-metal-device.m are written against manual
  # retain/release. Nothing else here is Objective-C.
  s.requires_arc = false

  s.xcconfig = {
    'IPHONEOS_DEPLOYMENT_TARGET' => '15.6',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
  }
  s.library = 'c++'
  s.frameworks = 'Accelerate', 'Foundation', 'Metal', 'MetalKit'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # Flutter.framework does not contain a i386 slice.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => [
      '"$(PODS_TARGET_SRCROOT)/Classes"',
      '"$(PODS_TARGET_SRCROOT)/Classes/llama/include"',
      '"$(PODS_TARGET_SRCROOT)/Classes/llama/ggml-include"',
      '"$(PODS_TARGET_SRCROOT)/Classes/llama/ggml"',
      '"$(PODS_TARGET_SRCROOT)/Classes/llama/ggml/ggml-cpu"',
      '"$(PODS_TARGET_SRCROOT)/Classes/llama/ggml/ggml-metal"',
      '"$(PODS_TARGET_SRCROOT)/Classes/llama/src"',
    ].join(' '),
    # Same Metal setup as the whisper_ggml fork next door, for the same
    # reasons: GGML_USE_METAL registers the backend in ggml-backend-reg.cpp,
    # and GGML_METAL_EMBED_LIBRARY makes ggml-metal-device.m read the shader
    # from the symbols ggml-metal-embed.S provides rather than looking for a
    # default.metallib in a bundle.
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) GGML_USE_CPU=1 GGML_USE_ACCELERATE=1 ACCELERATE_NEW_LAPACK=1 ACCELERATE_LAPACK_ILP64=1 GGML_USE_METAL=1 GGML_METAL_EMBED_LIBRARY=1 GGML_VERSION=\"b9700\" GGML_COMMIT=\"b9700\"',
    # .incbin in ggml-metal-embed.S names the shader without a directory, so
    # the assembler needs its folder on the include search path.
    'OTHER_CFLAGS' => '$(inherited) -I"$(PODS_TARGET_SRCROOT)/Classes/llama/ggml/ggml-metal"',
    'GCC_OPTIMIZATION_LEVEL' => '3',
  }
  s.swift_version = '5.0'
end
