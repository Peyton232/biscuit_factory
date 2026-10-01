class_name RoleColors
extends RefCounted
## One color per Cat.Role, used by HoverHighlight to tint a cat/station's
## hover outline by role — "color code the stations and outline cats in
## that color". Same "small static per-entity display helper" convention
## as ItemVisuals.
##
## Briefly had a second consumer, a per-cat role badge (a small always-on
## colored dot over each cat's head); that was removed 2026-09-17 on
## request — the outlines were kept, the dots weren't. See decisions.md.
##
## A validated categorical palette (not hand-picked): CVD-checked with
## this project's dataviz skill (OKLab ΔE, adjacent-pair scope — a player
## realistically compares a couple of nearby cats/stations at once, not
## all five roles in a single glance) across both this array's own
## adjacent order and every rotation, so no two roles that can plausibly
## sit next to each other on screen are the confusable pair. Oven reads
## as orange rather than literal red (Emily's own suggestion) specifically
## because red's closest validated slot clashed with another role under
## the same check — orange is the nearest validated stand-in for "hot."
const _COLORS: Dictionary[Cat.Role, Color] = {
	Cat.Role.DELIVERY: Color("e87ba4"), # magenta
	Cat.Role.MIXER: Color("2a78d6"), # blue
	Cat.Role.OVEN: Color("eb6834"), # orange
	Cat.Role.CUTTER: Color("1baf7a"), # aqua/green
	Cat.Role.ASSEMBLER: Color("eda100"), # yellow
}


static func color_for(role: Cat.Role) -> Color:
	return _COLORS.get(role, Color.WHITE)
