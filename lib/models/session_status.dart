/// Where a push-to-talk turn currently is in the pipeline.
enum SessionStatus {
  /// Waiting for a key press.
  idle,

  /// A key is held down and PCM frames are streaming in.
  listening,

  /// The key was released; whisper is transcribing the clip.
  recognizing,

  /// A transcript is on screen.
  done,

  /// The turn failed (permission, mic, model, or inference).
  failed,
}
