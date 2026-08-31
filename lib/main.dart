import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/recognition_turn.dart';
import 'models/session_status.dart';
import 'models/speech_direction.dart';
import 'services/asr_service.dart';
import 'services/llm_service.dart';
import 'services/pcm_recorder.dart';
import 'services/resident_model.dart';
import 'theme/night_theme.dart';
import 'widgets/bridge_status_bar.dart';
import 'widgets/push_to_talk_button.dart';
import 'widgets/transcript_stage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(NightTheme.overlayStyle);
  runApp(const MarineVoiceApp());
}

class MarineVoiceApp extends StatelessWidget {
  const MarineVoiceApp({
    super.key,
    this.asrService,
    this.llmService,
  });

  /// Injection points for tests; production builds create the real services.
  final AsrService? asrService;
  final LlmService? llmService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '航海英语语音翻译',
      debugShowCheckedModeBanner: false,
      theme: NightTheme.build(),
      // The bridge is dark at night and the app has no light palette to fall
      // back to, so the OS theme setting is deliberately ignored.
      themeMode: ThemeMode.dark,
      home: TranslatorHomePage(
        asrService: asrService,
        llmService: llmService,
      ),
    );
  }
}

class TranslatorHomePage extends StatefulWidget {
  const TranslatorHomePage({
    super.key,
    this.asrService,
    this.llmService,
  });

  final AsrService? asrService;
  final LlmService? llmService;

  @override
  State<TranslatorHomePage> createState() => _TranslatorHomePageState();
}

class _TranslatorHomePageState extends State<TranslatorHomePage>
    with WidgetsBindingObserver {
  /// Anything shorter than this is a mis-tap, not speech.
  static const Duration _minimumUtterance = Duration(milliseconds: 400);

  /// How long the recognised source stays on screen before translation starts.
  static const Duration _sourceFlashDuration = Duration(milliseconds: 700);

  final PcmRecorder _recorder = PcmRecorder();
  late final AsrService _asr = widget.asrService ?? AsrService();
  late final LlmService _llm = widget.llmService ?? LlmService();
  late final ResidentModels _residentModels =
      ResidentModels(<ResidentModel>[_asr, _llm]);

  StreamSubscription<double>? _levelSubscription;
  Timer? _elapsedTicker;
  Stopwatch? _stopwatch;

  SessionStatus _status = SessionStatus.idle;
  SpeechDirection? _activeDirection;
  RecognitionTurn? _turn;
  String? _errorMessage;
  String? _pendingSource;
  bool _showSourceFlash = false;
  Duration _elapsed = Duration.zero;
  double _level = 0;
  int? _progress;
  bool _hasMicPermission = false;
  bool? _isAsrModelReady;
  bool? _isLlmModelReady;

  bool get _isBusy =>
      _status == SessionStatus.listening ||
      _status == SessionStatus.recognizing ||
      _status == SessionStatus.translating;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _levelSubscription = _recorder.levelStream.listen((level) {
      if (mounted) setState(() => _level = level);
    });

    unawaited(_refreshPermission());
    unawaited(_prepareModels());
    unawaited(_recorder.configureAudioSession());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _elapsedTicker?.cancel();
    unawaited(_levelSubscription?.cancel());
    unawaited(_recorder.dispose());
    unawaited(_residentModels.releaseAll());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Losing the foreground mid-utterance means the capture is unusable, so
    // drop it rather than transcribing a truncated clip.
    if (state != AppLifecycleState.resumed &&
        (_status == SessionStatus.listening ||
            _status == SessionStatus.recognizing ||
            _status == SessionStatus.translating)) {
      unawaited(_abortRecording());
    }

    // Parked large models hold gigabytes; iOS will kill a backgrounded app
    // that keeps them. Give them back and pay the reload on return.
    if (state == AppLifecycleState.paused) {
      unawaited(_residentModels.releaseAll());
    }
  }

  Future<void> _prepareModels() async {
    final results = await Future.wait<bool>([
      _asr.prepare(),
      _llm.prepare(),
    ]);
    if (!mounted) return;
    setState(() {
      _isAsrModelReady = results[0];
      _isLlmModelReady = results[1];
    });
  }

  Future<void> _refreshPermission() async {
    final granted = await _recorder.hasPermission().catchError((Object error) {
      debugPrint('读取麦克风权限失败: $error');
      return false;
    });
    if (!mounted) return;
    setState(() => _hasMicPermission = granted);
  }

  Future<void> _requestPermission() async {
    final granted = await _recorder.requestPermission().catchError((
      Object error,
    ) {
      debugPrint('申请麦克风权限失败: $error');
      return false;
    });
    if (!mounted) return;

    setState(() => _hasMicPermission = granted);
    if (!granted) {
      _showSnack('麦克风权限被拒绝，请到系统设置中手动开启。');
    }
  }

  Future<void> _startRecording(SpeechDirection direction) async {
    if (_isBusy) return;

    setState(() {
      _status = SessionStatus.listening;
      _activeDirection = direction;
      _errorMessage = null;
      _pendingSource = null;
      _showSourceFlash = false;
      _elapsed = Duration.zero;
      _level = 0;
      _progress = null;
    });

    try {
      await _recorder.start();
    } on RecorderException catch (error) {
      if (!mounted) return;
      setState(() {
        _status = SessionStatus.failed;
        _activeDirection = null;
        _errorMessage = error.message;
        _hasMicPermission = !error.isPermissionDenied;
      });
      return;
    }

    if (!mounted) {
      await _recorder.cancel();
      return;
    }

    // The press may have already been released while `start` was awaiting the
    // platform; in that case the state machine has moved on, so leave it alone.
    if (_status != SessionStatus.listening) return;

    setState(() => _hasMicPermission = true);
    _startTicker();
  }

  /// Key released: stop the capture, then hand the WAV to whisper.
  Future<void> _stopRecording() async {
    if (_status != SessionStatus.listening) return;

    final direction = _activeDirection ?? SpeechDirection.englishToChinese;
    _stopTicker();

    setState(() {
      _status = SessionStatus.recognizing;
      _level = 0;
      _progress = null;
    });

    final PcmClip? clip;
    try {
      clip = await _recorder.stop();
    } on RecorderException catch (error) {
      _failTurn(error.message);
      return;
    }
    if (!mounted) return;

    if (clip == null || clip.duration < _minimumUtterance) {
      _resetToLastResult();
      _showSnack('按住时间太短，请按住按键说完再松开。');
      return;
    }

    final wavPath = clip.wavPath;
    if (wavPath == null) {
      _failTurn('录音文件写入失败，无法进行识别。');
      return;
    }

    await _recognizeAndTranslate(clip, wavPath, direction);
  }

  Future<void> _recognizeAndTranslate(
    PcmClip clip,
    String wavPath,
    SpeechDirection direction,
  ) async {
    final asrStopwatch = Stopwatch()..start();

    try {
      final sourceText = await _asr.transcribe(
        wavPath,
        language: direction.asrLanguage,
        onProgress: (percent) {
          if (mounted && _status == SessionStatus.recognizing) {
            setState(() => _progress = percent);
          }
        },
      );
      asrStopwatch.stop();
      if (!mounted) return;

      if (sourceText.isEmpty) {
        setState(() {
          _turn = RecognitionTurn(
            direction: direction,
            sourceText: '',
            translation: '',
            audioDuration: clip.duration,
            asrTime: asrStopwatch.elapsed,
            llmTime: Duration.zero,
            createdAt: DateTime.now(),
            audioPath: wavPath,
          );
          _status = SessionStatus.done;
          _activeDirection = null;
          _progress = null;
        });
        return;
      }

      setState(() {
        _status = SessionStatus.translating;
        _pendingSource = sourceText;
        _showSourceFlash = true;
        _progress = null;
      });

      await Future<void>.delayed(_sourceFlashDuration);
      if (!mounted || _status != SessionStatus.translating) return;

      setState(() => _showSourceFlash = false);

      final llmStopwatch = Stopwatch()..start();
      final translation = await _llm.translate(
        text: sourceText,
        isEnglishToChinese: direction.isEnglishToChinese,
      );
      llmStopwatch.stop();
      if (!mounted) return;

      setState(() {
        _turn = RecognitionTurn(
          direction: direction,
          sourceText: sourceText,
          translation: translation,
          audioDuration: clip.duration,
          asrTime: asrStopwatch.elapsed,
          llmTime: llmStopwatch.elapsed,
          createdAt: DateTime.now(),
          audioPath: wavPath,
        );
        _status = SessionStatus.done;
        _activeDirection = null;
        _pendingSource = null;
        _showSourceFlash = false;
      });
    } on AsrException catch (error) {
      if (error.isModelMissing && mounted) {
        setState(() => _isAsrModelReady = false);
      }
      _failTurn(error.message);
    } on TranslationException catch (error) {
      if (error.isModelMissing && mounted) {
        setState(() => _isLlmModelReady = false);
      }
      _failTurn(error.message);
    } on Object catch (error) {
      _failTurn('处理失败：$error');
    }
  }

  Future<void> _abortRecording() async {
    _stopTicker();
    await _recorder.cancel();
    if (!mounted) return;

    _resetToLastResult();
  }

  void _resetToLastResult() {
    setState(() {
      _status = _turn == null ? SessionStatus.idle : SessionStatus.done;
      _activeDirection = null;
      _pendingSource = null;
      _showSourceFlash = false;
      _level = 0;
      _progress = null;
    });
  }

  void _failTurn(String message) {
    if (!mounted) return;
    setState(() {
      _status = SessionStatus.failed;
      _activeDirection = null;
      _pendingSource = null;
      _showSourceFlash = false;
      _errorMessage = message;
      _level = 0;
      _progress = null;
    });
  }

  void _startTicker() {
    _stopwatch = Stopwatch()..start();
    _elapsedTicker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _elapsed = _stopwatch?.elapsed ?? Duration.zero);
    });
  }

  void _stopTicker() {
    _elapsedTicker?.cancel();
    _elapsedTicker = null;
    _stopwatch?.stop();
    _stopwatch = null;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: NightTheme.overlayStyle,
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isRoomy = constraints.maxWidth >= 640;
              final horizontalPadding = isRoomy ? 32.0 : 20.0;
              final buttonHeight = constraints.maxHeight < 620 ? 128.0 : 168.0;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      16,
                      horizontalPadding,
                      16,
                    ),
                    child: Column(
                      children: [
                        BridgeStatusBar(
                          hasMicPermission: _hasMicPermission,
                          isAsrModelReady: _isAsrModelReady,
                          isLlmModelReady: _isLlmModelReady,
                          onRequestPermission: _requestPermission,
                        ),
                        const SizedBox(height: 20),
                        Expanded(
                          child: TranscriptStage(
                            status: _status,
                            turn: _turn,
                            activeDirection: _activeDirection,
                            elapsed: _elapsed,
                            level: _level,
                            progress: _progress,
                            sourceText: _pendingSource,
                            showSourceFlash: _showSourceFlash,
                            errorMessage: _errorMessage,
                            onDismissError: _resetToLastResult,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _TalkKeys(
                          activeDirection: _status == SessionStatus.listening
                              ? _activeDirection
                              : null,
                          isBusy: _isBusy,
                          level: _level,
                          buttonHeight: buttonHeight,
                          onPressStart: _startRecording,
                          onPressEnd: _stopRecording,
                          onPressCancel: _abortRecording,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The two oversized bottom keys, always side by side so muscle memory maps
/// "left = English, right = Chinese" no matter the screen size.
class _TalkKeys extends StatelessWidget {
  const _TalkKeys({
    required this.activeDirection,
    required this.isBusy,
    required this.level,
    required this.buttonHeight,
    required this.onPressStart,
    required this.onPressEnd,
    required this.onPressCancel,
  });

  final SpeechDirection? activeDirection;
  final bool isBusy;
  final double level;
  final double buttonHeight;
  final ValueChanged<SpeechDirection> onPressStart;
  final Future<void> Function() onPressEnd;
  final Future<void> Function() onPressCancel;

  @override
  Widget build(BuildContext context) {
    final keys = SpeechDirection.values.map((direction) {
      final isActive = activeDirection == direction;

      return Expanded(
        child: PushToTalkButton(
          direction: direction,
          isActive: isActive,
          isEnabled: !isBusy || isActive,
          level: isActive ? level : 0,
          height: buttonHeight,
          onPressStart: () => onPressStart(direction),
          onPressEnd: () => unawaited(onPressEnd()),
          onPressCancel: () => unawaited(onPressCancel()),
        ),
      );
    }).toList();

    return Row(children: [keys.first, const SizedBox(width: 14), keys.last]);
  }
}
