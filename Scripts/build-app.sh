#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
cd "$project_root"
# Override with a build environment containing requirements-build.txt.
python_path="${FANFIC_BUILD_PYTHON:-$project_root/.venv/bin/python}"
if [[ ! -x "$python_path" ]]; then
    print -u2 'Create .venv and install requirements-build.txt, or set FANFIC_BUILD_PYTHON.'
    exit 1
fi
"$python_path" "$project_root/Scripts/build-worker.py"
"$project_root/Scripts/swift.sh" build -c release --product FanFicToAudio
if ! python3 - "$project_root" <<'ENCODER'
from pathlib import Path
import hashlib, json, platform, sys
root=Path(sys.argv[1])
try:
    record=json.loads((root/'.build/encoder/build.json').read_text())
    assert record['build_script_sha256']==hashlib.sha256((root/'Scripts/build-encoder.sh').read_bytes()).hexdigest()
    assert record['architecture']==platform.machine()
    assert (root/'.build/encoder/prefix/bin/ffmpeg').is_file()
except (OSError, ValueError, KeyError, AssertionError): raise SystemExit(1)
ENCODER
then
    "$project_root/Scripts/build-encoder.sh"
fi
mkdir -p "$project_root/dist"
stage_path="$(mktemp -d "$project_root/dist/.app-build.XXXXXX")"
trap 'rm -rf "$stage_path"' EXIT
app_path="$stage_path/FanFic to Audio.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
binary_dir=$("$project_root/Scripts/swift.sh" build -c release --show-bin-path)
cp "$binary_dir/FanFicToAudio" "$app_path/Contents/MacOS/FanFicToAudio"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_root/Resources/AppIcon.icns" "$app_path/Contents/Resources/"
cp "$project_root/.build/encoder/prefix/bin/ffmpeg" "$app_path/Contents/Resources/ffmpeg"
cp -R "$project_root/.build/encoder/licenses" "$app_path/Contents/Resources/EncoderLicenses"
mkdir -p "$app_path/Contents/Resources/EncoderSources"
cp "$project_root/.build/encoder/sources/ffmpeg-8.1.2.tar.xz" "$project_root/.build/encoder/sources/lame-3.100.tar.gz" "$app_path/Contents/Resources/EncoderSources/"
cp -R "$project_root/build/worker/fanfic-download" "$app_path/Contents/Resources/Downloader"
cp "$project_root/LICENSE" "$project_root/NOTICE" "$app_path/Contents/Resources/"
# Preserve the notices delivered with the original downloader sources.
cp "$project_root/Resources/FanFicFare-Desktop-NOTICE.txt" "$app_path/Contents/Resources/"
"$python_path" "$project_root/Scripts/collect-notices.py" "$app_path/Contents/Resources/ThirdPartyNotices"
"$python_path" "$project_root/Scripts/sign-app.py" "$app_path" --identity "${SIGNING_IDENTITY:--}"
final_path="$project_root/dist/FanFic to Audio.app"
if [[ -d "$final_path" ]]; then
    backup_dir="$project_root/dist/Previous Builds"
    mkdir -p "$backup_dir"
    backup_path="$backup_dir/FanFic to Audio-$(date +%Y%m%d-%H%M%S)-$(uuidgen).app"
    mv "$final_path" "$backup_path"
fi
if ! mv "$app_path" "$final_path"; then
    if [[ -n "${backup_path:-}" ]]; then mv "$backup_path" "$final_path"; fi
    exit 1
fi
print "Built: $final_path"
