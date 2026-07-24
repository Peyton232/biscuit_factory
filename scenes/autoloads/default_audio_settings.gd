extends Node
## Seeds the player's saved audio slider positions (`PlayerConfig`'s
## `AudioSettings` section) with this project's intended defaults, but
## only for keys that don't already exist — never overwrites a value a
## player (or this dev, on their own machine) has already set.
##
## **Must run before `AppConfig`** (see `project.godot`'s `[autoload]`
## order — this is listed first) so `PlayerConfig` already has these
## values by the time `AppConfig._ready()` calls
## `AppSettings.set_from_config_and_window()`, which is what actually
## reads them onto the audio buses.
##
## **Why seed `PlayerConfig` instead of just setting `default_bus_layout.
## tres`'s own `volume_db` to the intended default** (the approach used
## the first time this project set non-default audio levels) **— that
## approach has a real bug in the template's own `AppSettings.
## set_audio_from_config()`**: on a genuinely fresh install (no saved
## `PlayerConfig` entry yet), it computes its "no saved value" fallback
## default from the *current* `AudioServer` bus volume (i.e. whatever
## `default_bus_layout.tres` set) — but that exact same current-bus-volume
## reading is *also* what it records as the 100%-reference every future
## slider position gets scaled against. Feeding a non-unity bus layout
## default through this path means the fallback default (call it `L`) gets
## applied *relative to itself*, so a fresh player's actual resulting
## volume comes out as `L²`, not `L` — quieter than intended, and quieter
## than what the slider itself displays (which shows the correct `L`,
## since the display math and the applied math diverge). Invisible in the
## template's own stock config (`L = 1.0`, and `1.0² = 1.0`), which is
## presumably why it's never been hit before. Not something this project
## can fix directly (`AppSettings.gd` is vendored, `addons/` isn't edited)
## — seeding `PlayerConfig` directly sidesteps the bug instead: once a
## real saved value exists, `AppSettings` uses it as-is rather than
## falling back to the self-referential computation, so the bus layout's
## own `volume_db` can now cleanly represent an actual 100%-slider
## reference (see decisions.md) with no hidden squaring.

const _AUDIO_SECTION: StringName = &"AudioSettings"

## Half of this project's original intended defaults (Master 0.7 / Music
## 0.8 / SFX 0.6) — halved because `default_bus_layout.tres`'s own
## reference volume was doubled in the same change (see decisions.md), so
## a fresh player's actual resulting loudness lands exactly where it
## always has, while the slider itself now sits at the midpoint of its
## range instead of near the top, leaving headroom to go louder.
const _DEFAULTS: Dictionary[StringName, float] = {
	&"Master": 0.35,
	&"Music": 0.4,
	&"Sfx": 0.3,
}


func _ready() -> void:
	for key: StringName in _DEFAULTS:
		if not PlayerConfig.has_section_key(_AUDIO_SECTION, key):
			PlayerConfig.set_config(_AUDIO_SECTION, key, _DEFAULTS[key])
