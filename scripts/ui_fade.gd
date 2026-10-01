class_name UiFade
extends RefCounted
## Fades a HUD panel out and hides it, instead of snapping it away.
##
## Exists because "the menu is finished with, get rid of it" happens in
## half a dozen places across FactoryHud (the Build flyout after a
## building is picked, the cat/building inspectors after a role or recipe
## is chosen, the adopt dialogs on confirm, the insufficient-funds
## warning) — "if players don't know to hit esc to close the menu those
## sub menus stay around and cause visual clutter". A plain `hide()` at
## each of those sites reads as a glitch at this speed; a short fade
## reads as the panel acknowledging the click and getting out of the way.
##
## Static rather than a node so it can be called from anywhere without
## wiring, same convention as SpritePicker/RoleColors/ItemVisuals. The
## in-flight Tween is parked in node metadata because that state belongs
## to the individual panel, not to a shared helper — a static var would
## be one global slot for all of them, and a member var would mean this
## had to be instantiated and wired per panel.

## Standard fade length for HUD panels dismissing themselves. Long enough
## to read as deliberate, short enough not to delay the next click.
const PANEL_SECONDS: float = 0.4

const _TWEEN_META: StringName = &"ui_fade_tween"


## Fades `control` to transparent over `duration`, then hides it and
## restores its alpha (so the next plain `show()` is fully opaque — a
## caller that never heard of this helper still behaves correctly).
## No-op for an already-hidden control, so it's safe to call on a
## dismissal path that may or may not have anything on screen.
static func out(control: Control, duration: float = PANEL_SECONDS) -> void:
	if control == null or not control.visible:
		return
	cancel(control)
	if duration <= 0.0:
		control.hide()
		return
	var tween: Tween = control.create_tween()
	control.set_meta(_TWEEN_META, tween)
	tween.tween_property(control, "modulate:a", 0.0, duration)
	tween.tween_callback(func() -> void:
		control.hide()
		control.modulate.a = 1.0
		if control.has_meta(_TWEEN_META):
			control.remove_meta(_TWEEN_META))


## Holds `control` fully visible for `hold` seconds, then fades it out —
## for a message that has to be readable before it leaves (see
## FactoryHud's insufficient-funds warning) rather than a panel the
## player already knows they're done with.
static func out_after(control: Control, hold: float, duration: float = PANEL_SECONDS) -> void:
	if control == null or not control.visible:
		return
	cancel(control)
	var tween: Tween = control.create_tween()
	control.set_meta(_TWEEN_META, tween)
	tween.tween_interval(hold)
	tween.tween_property(control, "modulate:a", 0.0, duration)
	tween.tween_callback(func() -> void:
		control.hide()
		control.modulate.a = 1.0
		if control.has_meta(_TWEEN_META):
			control.remove_meta(_TWEEN_META))


## Cancels any fade in flight and restores full opacity, leaving
## visibility alone. **Call this before re-showing anything that can
## fade**, or a panel shown again mid-fade keeps fading and vanishes on
## its own a moment later.
static func cancel(control: Control) -> void:
	if control == null:
		return
	if control.has_meta(_TWEEN_META):
		var tween: Tween = control.get_meta(_TWEEN_META) as Tween
		if tween != null and tween.is_valid():
			tween.kill()
		control.remove_meta(_TWEEN_META)
	control.modulate.a = 1.0


## Whether a fade is currently running on `control`. A fading panel is
## still `visible`, so a toggle that only checks visibility reads it as
## open and closes it again — clicking Build while the flyout fades
## would keep fading instead of reopening. Toggles should treat fading
## as "already on its way out", i.e. as closed.
static func is_fading(control: Control) -> bool:
	if control == null or not control.has_meta(_TWEEN_META):
		return false
	var tween: Tween = control.get_meta(_TWEEN_META) as Tween
	return tween != null and tween.is_valid()


## cancel() + show(), the pairing every re-show site wants.
static func show_now(control: Control) -> void:
	if control == null:
		return
	cancel(control)
	control.show()
