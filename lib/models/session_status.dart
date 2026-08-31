/// Where a push-to-talk turn currently is in the pipeline.
enum SessionStatus {
  /// Waiting for a key press.
  idle,

  /// A key is held down and PCM frames are streaming in.
  listening,

  /// The key was released; the offline engine is working on the clip.
  decoding,

  /// A translation is on screen.
  done,

  /// The turn failed (permission, mic, or engine).
  failed,
}
