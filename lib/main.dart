import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/session_status.dart';
import 'models/speech_direction.dart';
import 'models/translation_turn.dart';
import 'services/pcm_recorder.dart';
import 'services/translation_engine.dart';
import 'theme/night_theme.dart';
import 'widgets/bridge_status_bar.dart';
import 'widgets/push_to_talk_button.dart';
import 'widgets/translation_stage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(NightTheme.overlayStyle);
  runApp(const MarineVoiceApp());
}

class MarineVoiceApp extends StatelessWidget {
  const MarineVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '航海英语语音翻译',
      debugShowCheckedModeBanner: false,
      theme: NightTheme.build(),
      // The bridge is dark at night and the app has no light palette to fall
      // back to, so the OS theme setting is deliberately ignored.
      themeMode: ThemeMode.dark,
      home: const TranslatorHomePage(),
    );
  }
}

class TranslatorHomePage extends StatefulWidget {
  const TranslatorHomePage({super.key});

  @override
  State<TranslatorHomePage> createState() => _TranslatorHomePageState();
}

class _TranslatorHomePageState extends State<TranslatorHomePage>
    with WidgetsBindingObserver {
  /// Anything shorter than this is a mis-tap, not speech.
  static const Duration _minimumUtterance = Duration(milliseconds: 400);

  final PcmRecorder _recorder = PcmRecorder();
  final TranslationEngine _engine = DemoPhrasebookEngine();

  StreamSubscription<double>? _levelSubscription;
  Timer? _elapsedTicker;
  Stopwatch? _stopwatch;

  SessionStatus _status = SessionStatus.idle;
  SpeechDirection? _activeDirection;
  TranslationTurn? _turn;
  String? _errorMessage;
  Duration _elapsed = Duration.zero;
  double _level = 0;
  bool _hasMicPermission = false;

  bool get _isBusy =>
      _status == SessionStatus.listening || _status == SessionStatus.decoding;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _levelSubscription = _recorder.levelStream.listen((level) {
      if (mounted) setState(() => _level = level);
    });

    unawaited(_refreshPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _elapsedTicker?.cancel();
    unawaited(_levelSubscription?.cancel());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Losing the foreground mid-utterance means the capture is unusable, so
    // drop it rather than translating a truncated clip.
    if (state != AppLifecycleState.resumed &&
        _status == SessionStatus.listening) {
      unawaited(_abortRecording());
    }
  }

  Future<void> _refreshPermission() async {
    final granted = await _recorder.hasPermission();
    if (!mounted) return;
    setState(() => _hasMicPermission = granted);
  }

  Future<void> _requestPermission() async {
    final granted = await _recorder.requestPermission();
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
      _elapsed = Duration.zero;
      _level = 0;
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

  Future<void> _stopRecording() async {
    if (_status != SessionStatus.listening) return;

    final direction = _activeDirection ?? SpeechDirection.englishToChinese;
    _stopTicker();

    setState(() {
      _status = SessionStatus.decoding;
      _level = 0;
    });

    PcmClip? clip;
    try {
      clip = await _recorder.stop();
    } on RecorderException catch (error) {
      _failTurn(error.message);
      return;
    }

    if (!mounted) return;

    if (clip == null || clip.duration < _minimumUtterance) {
      setState(() {
        _status = _turn == null ? SessionStatus.idle : SessionStatus.done;
        _activeDirection = null;
      });
      _showSnack('按住时间太短，请按住按键说完再松开。');
      return;
    }

    try {
      final turn = await _engine.process(clip, direction: direction);
      if (!mounted) return;
      setState(() {
        _turn = turn;
        _status = SessionStatus.done;
        _activeDirection = null;
      });
    } on TranslationException catch (error) {
      _failTurn(error.message);
    } on Object catch (error) {
      _failTurn('翻译失败：$error');
    }
  }

  Future<void> _abortRecording() async {
    _stopTicker();
    await _recorder.cancel();
    if (!mounted) return;

    setState(() {
      _status = _turn == null ? SessionStatus.idle : SessionStatus.done;
      _activeDirection = null;
      _level = 0;
    });
  }

  void _failTurn(String message) {
    if (!mounted) return;
    setState(() {
      _status = SessionStatus.failed;
      _activeDirection = null;
      _errorMessage = message;
      _level = 0;
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
                          onRequestPermission: _requestPermission,
                        ),
                        const SizedBox(height: 20),
                        Expanded(
                          child: TranslationStage(
                            status: _status,
                            turn: _turn,
                            activeDirection: _activeDirection,
                            elapsed: _elapsed,
                            level: _level,
                            errorMessage: _errorMessage,
                            onDismissError: () => setState(() {
                              _errorMessage = null;
                              _status = _turn == null
                                  ? SessionStatus.idle
                                  : SessionStatus.done;
                            }),
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
