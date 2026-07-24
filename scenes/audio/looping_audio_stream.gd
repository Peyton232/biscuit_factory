class_name LoopingAudioStream
## Tiny shared helper: forces an `AudioStreamWAV` to loop its full length,
## in code, at runtime — not via the `.wav.import` file's `edit/loop_mode`.
##
## Two things had to be true before this worked at all (both real bugs,
## found and fixed on `TierMusicController`, this class's original and
## still-primary caller — see decisions.md for the full history):
## - `edit/loop_mode` in `.wav.import` doesn't reliably survive this
##   project's import pipeline; setting `loop_mode` directly on the
##   loaded resource always takes effect immediately instead.
## - `loop_end` must be a real frame count, not `-1`. Unlike the import
##   UI's own "-1 means the end of the sample" convention, the runtime
##   mixer (`AudioStreamPlaybackWAV::mix()`) uses `loop_end` as a literal
##   sample-frame boundary with no such sentinel handling — `-1` there is
##   a degenerate, near-zero-length loop range that silences playback
##   almost immediately. Computed by inverting `get_length()`'s own
##   seconds-from-bytes math (`* mix_rate`) instead, so it's correct
##   regardless of a track's bit depth/compression format.
##
## Pulled out to its own class (rather than left as a private method only
## `TierMusicController` has) once a second, unrelated caller
## (`MenuMusicPlayer`, the main menu's title screen music) needed the
## exact same fix — copy-pasting a fix this non-obvious a second time
## risks it silently drifting or regressing in one copy but not the
## other.

static func force_full_loop(stream: AudioStream) -> void:
	var wav: AudioStreamWAV = stream as AudioStreamWAV
	if wav == null:
		return
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = int(wav.get_length() * wav.mix_rate)
