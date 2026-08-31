import 'package:flutter/foundation.dart';

/// A model held in native memory between requests.
///
/// Both inference stages park their model so repeated presses do not pay the
/// load again: whisper's turbo model is around 550 MB and Qwen 1.5B q4_K_M
/// another gigabyte. Together that is more than iOS will let a backgrounded
/// app keep, so holding on to it is a deliberate trade that has to be undone
/// deliberately too.
abstract interface class ResidentModel {
  /// Human-readable name, for logging which stage failed to let go.
  String get residentModelName;

  /// Whether native memory is currently held.
  bool get isResident;

  /// Frees the native memory. Must be safe to call when nothing is resident.
  Future<void> release();
}

/// Releases every resident model as one operation.
///
/// The app goes through this rather than releasing each service by hand, so
/// adding a third model cannot quietly miss the background hook.
class ResidentModels {
  const ResidentModels(this._models);

  final List<ResidentModel> _models;

  /// True while any stage is holding native memory.
  bool get anyResident => _models.any((model) => model.isResident);

  /// Frees everything, in order.
  ///
  /// One stage failing does not stop the others: this runs when iOS is about
  /// to decide whether to kill the app, and a partial release still helps.
  Future<void> releaseAll() async {
    for (final ResidentModel model in _models) {
      try {
        await model.release();
      } on Object catch (error) {
        debugPrint('无法释放 ${model.residentModelName} 模型：$error');
      }
    }
  }
}
