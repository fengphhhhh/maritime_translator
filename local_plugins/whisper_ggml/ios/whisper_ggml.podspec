Pod::Spec.new do |s|
  s.name             = 'whisper_ggml'
  s.version          = '2.6.0-metal.1'
  s.summary          = 'whisper.cpp for Flutter, forked to run on Metal.'
  s.description      = <<-DESC
Fork of whisper_ggml 2.6.0 with the ggml Metal backend vendored in from
whisper.cpp v1.9.1. Upstream ships only the CPU/Accelerate backend on iOS.
                       DESC
  s.homepage         = 'https://github.com/sk3llo/whisper_ggml'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'kapraton@gmail.com' }

  s.dependency 'Flutter'
  s.source           = {
    :git => 'https://github.com/sk3llo/whisper_ggml'
  }

  # .m  -> ggml-metal-context.m / ggml-metal-device.m (the Metal backend)
  # .S  -> ggml-metal-embed.S, which .incbin's the shader into the binary
  #
  # ggml-metal.metal and ggml-metal-embed.metal are deliberately NOT compiled:
  # the shader is compiled at runtime from the embedded source, with the
  # feature macros that match the device. Listing them here would make Xcode
  # build a default.metallib too, which would be dead weight.
  s.source_files = 'Classes/**/*.{cpp,c,h,hpp,m,S}'
  s.preserve_paths = 'Classes/whisper/ggml/src/ggml-metal/*.metal'

  # Only whisper.h is public; the ggml tree has duplicate header basenames
  # (common.h, quants.h) that collide when flattened into the framework.
  s.public_header_files = 'Classes/whisper/include/whisper.h'
  s.platform = :ios, '15.6'
  s.ios.deployment_target  = '15.6'

  # ggml-metal-context.m and ggml-metal-device.m are written against manual
  # retain/release. Nothing else here is Objective-C, so turning ARC off for
  # the whole pod is the simplest correct setting.
  s.requires_arc = false

  # Flutter.framework does not contain a i386 slice.
  s.xcconfig = {
    'IPHONEOS_DEPLOYMENT_TARGET' => '15.6',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
  }
  s.library = 'c++'
  s.frameworks = 'Accelerate', 'Foundation', 'Metal', 'MetalKit'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    # whisper.cpp v1.9.1 include roots
    'HEADER_SEARCH_PATHS' => [
      '"$(PODS_TARGET_SRCROOT)/Classes/whisper/include"',
      '"$(PODS_TARGET_SRCROOT)/Classes/whisper/ggml/include"',
      '"$(PODS_TARGET_SRCROOT)/Classes/whisper/ggml/src"',
      '"$(PODS_TARGET_SRCROOT)/Classes/whisper/ggml/src/ggml-cpu"',
      '"$(PODS_TARGET_SRCROOT)/Classes/whisper/ggml/src/ggml-metal"',
      '"$(PODS_TARGET_SRCROOT)/Classes/whisper/src"',
    ].join(' '),
    # GGML_USE_METAL           -> registers the Metal backend in
    #                             ggml-backend-reg.cpp and compiles the
    #                             ggml-metal sources into the framework.
    # GGML_METAL_EMBED_LIBRARY -> ggml-metal-device.m reads the shader from the
    #                             ggml_metallib_start/end symbols that
    #                             ggml-metal-embed.S provides, instead of
    #                             hunting for a default.metallib in a bundle.
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) GGML_USE_CPU=1 GGML_USE_ACCELERATE=1 ACCELERATE_NEW_LAPACK=1 ACCELERATE_LAPACK_ILP64=1 GGML_USE_METAL=1 GGML_METAL_EMBED_LIBRARY=1 GGML_VERSION=\"1.9.1\" GGML_COMMIT=\"whisper.cpp-v1.9.1\" WHISPER_VERSION=\"1.9.1\"',
    # .incbin in ggml-metal-embed.S names the shader without a directory, so
    # the assembler needs its folder on the include search path.
    'OTHER_CFLAGS' => '$(inherited) -I"$(PODS_TARGET_SRCROOT)/Classes/whisper/ggml/src/ggml-metal"',
    # keep inference usable in debug builds
    'GCC_OPTIMIZATION_LEVEL' => '3',
  }
  s.swift_version = '5.0'
end
