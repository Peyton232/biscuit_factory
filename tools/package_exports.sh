#!/usr/bin/env bash
# Zips up Godot's Web/Linux/Windows exports into distributable archives.
#
# Run with: tools/package_exports.sh
# (after exporting all three platforms from the Godot editor as usual —
# this only packages whatever's already been exported, it doesn't invoke
# the Godot exporter itself).
#
# Reads from export_presets.cfg's own configured export_path for each
# preset — Linux/Windows each get their OWN dedicated Desktop subfolder
# (biscuit-factory-linux/, biscuit-factory-windows/), Web its own dev
# folder. That per-platform separation is deliberate, not incidental: see
# architecture.md's "Export & itch.io packaging" — Linux and Windows used
# to both export straight to loose `Desktop/Biscuit Factory.{x86_64,exe}`,
# and since Godot names a build's `.pck` after its executable minus the
# extension, both wrote the SAME `Desktop/Biscuit Factory.pck` (worked
# only by coincidence, since both presets happen to share identical
# texture_format settings; fixed by giving each platform its own folder
# so this can't silently mismatch if that ever changes).
#
# **Also checks for loose files directly in ~/Desktop as a fallback per
# platform**, and uses whichever of the two (folder vs. loose) is newer —
# in practice the export dialog doesn't always land in the configured
# folder (its destination can be changed at export time), so this is what
# actually keeps "run this after exporting" reliable. Packaging from the
# loose location prints a ⚠ warning: it pairs with a `.pck` that's
# genuinely ambiguous between platforms (there's only one loose
# `Biscuit Factory.pck` on the Desktop, shared by whichever exe sits next
# to it), which is exactly the risk the dedicated-folder fix above exists
# to avoid. Re-exporting via the preset's own remembered path (which
# already points at the safe per-platform folder) clears the warning.
#
# If export_presets.cfg's export_path ever changes, update
# LINUX_DIR/WINDOWS_DIR/WEB_DIR below to match.
#
# Output: Biscuit Factory-web.zip / -linux.zip / -windows.zip, written to
# ~/Desktop (overwriting any previous zip of the same name). A platform
# with no export found yet is skipped with a message, not a hard failure
# — run this after exporting only some platforms and it just does what it
# can.
#
# Override any default location without editing this file:
#   BISCUIT_DESKTOP="/some/other/dir" BISCUIT_WEB_DIR="/some/web/export" tools/package_exports.sh

set -euo pipefail

DESKTOP="${BISCUIT_DESKTOP:-$HOME/Desktop}"
WEB_DIR="${BISCUIT_WEB_DIR:-$HOME/dev/biscuit factory}"
LINUX_DIR="${BISCUIT_LINUX_DIR:-$DESKTOP/biscuit-factory-linux}"
WINDOWS_DIR="${BISCUIT_WINDOWS_DIR:-$DESKTOP/biscuit-factory-windows}"

PCK_NAME="Biscuit Factory.pck"

# Writes a zip containing exactly the given files, flattened (no folder
# prefix inside the archive) — matches how the exported .exe/.pck sit
# side by side when someone unzips and runs the game. Prefers the `zip`
# CLI; falls back to python3's zipfile module if `zip` isn't installed
# (it isn't on every machine this might run on).
make_zip() {
	local out="$1"
	shift
	rm -f "$out"
	if command -v zip >/dev/null 2>&1; then
		zip -j -q "$out" "$@"
	else
		python3 - "$out" "$@" <<'PYEOF'
import sys, zipfile, os
out, files = sys.argv[1], sys.argv[2:]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as zf:
	for f in files:
		zf.write(f, arcname=os.path.basename(f))
PYEOF
	fi
}

# Same idea as make_zip, but for a whole directory's worth of files
# (Web's export is many files, not a fixed exe+pck pair) — also
# flattened, since itch.io's HTML5 embed needs index.html at the zip
# root, not nested in a folder (see architecture.md).
make_zip_from_dir() {
	local out="$1" dir="$2"
	rm -f "$out"
	if command -v zip >/dev/null 2>&1; then
		(cd "$dir" && zip -q "$out" ./*)
	else
		python3 - "$out" "$dir" <<'PYEOF'
import sys, zipfile, os
out, src = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as zf:
	for name in sorted(os.listdir(src)):
		zf.write(os.path.join(src, name), arcname=name)
PYEOF
	fi
}

# Picks whichever of two same-purpose files is newer, echoing its path —
# empty output if neither exists.
newer_of() {
	local a="$1" b="$2"
	if [[ -e "$a" && -e "$b" ]]; then
		if [[ "$a" -nt "$b" ]]; then printf '%s' "$a"; else printf '%s' "$b"; fi
	elif [[ -e "$a" ]]; then
		printf '%s' "$a"
	elif [[ -e "$b" ]]; then
		printf '%s' "$b"
	fi
}

# $1 = display name, $2 = executable filename, $3 = that platform's own
# dedicated export folder, $4 = output zip path.
package_platform() {
	local display_name="$1" exe_name="$2" folder_dir="$3" out_zip="$4"
	local folder_exe="$folder_dir/$exe_name"
	local loose_exe="$DESKTOP/$exe_name"
	local chosen_exe
	chosen_exe="$(newer_of "$folder_exe" "$loose_exe")"

	if [[ -z "$chosen_exe" ]]; then
		echo "  [$display_name] no export found (checked '$folder_dir' and '$DESKTOP') - skipping"
		return
	fi

	local src_dir
	src_dir="$(dirname "$chosen_exe")"
	local pck="$src_dir/$PCK_NAME"
	if [[ ! -e "$pck" ]]; then
		echo "  [$display_name] found '$chosen_exe' but no '$PCK_NAME' next to it - skipping"
		return
	fi

	make_zip "$out_zip" "$chosen_exe" "$pck"
	if [[ "$src_dir" == "$DESKTOP" ]]; then
		echo "  [$display_name] packaged from loose Desktop files -> '$out_zip'"
		echo "    ⚠ that '$PCK_NAME' is shared/ambiguous between platforms — see this script's own header comment"
	else
		echo "  [$display_name] packaged from '$src_dir' -> '$out_zip'"
	fi
}

package_web() {
	local out_zip="$DESKTOP/Biscuit Factory-web.zip"
	if [[ ! -e "$WEB_DIR/index.html" ]]; then
		echo "  [Web] no export found at '$WEB_DIR' (looked for index.html) - skipping"
		return
	fi
	make_zip_from_dir "$out_zip" "$WEB_DIR"
	echo "  [Web] packaged from '$WEB_DIR' -> '$out_zip'"
}

echo "Packaging Biscuit Factory exports..."
package_platform "Linux" "Biscuit Factory.x86_64" "$LINUX_DIR" "$DESKTOP/Biscuit Factory-linux.zip"
package_platform "Windows" "Biscuit Factory.exe" "$WINDOWS_DIR" "$DESKTOP/Biscuit Factory-windows.zip"
package_web
echo "Done."
