class_name MenuMusicPlayer
extends AudioStreamPlayer
## Script override for `main_menu_with_animations.tscn`'s
## `BackgroundMusicPlayer` (an instance of the template's own
## `background_music_player.tscn` — `autoplay = true`, bus `Music`
## already set there; not edited, per this project's "don't edit
## addons/" convention). That scene has no loop-forcing logic of its own,
## so without this, `stream` would play through once and then go silent
## — the addon's `ProjectMusicController` autoload only crossfades
## between music players as they enter/exit the tree, it doesn't restart
## a track that reaches its natural end. See `LoopingAudioStream`'s own
## class doc for why the loop has to be forced here in code rather than
## via `stream`'s own `.wav.import` settings.

func _ready() -> void:
	LoopingAudioStream.force_full_loop(stream)
