#!/bin/zsh
set -euo pipefail
export MACOSX_DEPLOYMENT_TARGET=14.0
project_root="${0:A:h:h}"
encoder_root="$project_root/.build/encoder"
source_root="$encoder_root/sources"
build_root="$(mktemp -d /private/tmp/epub-encoder.XXXXXX)"
trap 'rm -rf "$build_root"' EXIT
prefix="$build_root/prefix"
mkdir -p "$source_root" "$prefix"
cd "$source_root"
download() {
    if [[ ! -f "$2" ]]; then /usr/bin/curl --fail --location --retry 2 "$1" -o "$2.download"; mv "$2.download" "$2"; fi
}
download https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz ffmpeg-8.1.2.tar.xz
download https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz lame-3.100.tar.gz
python3 - "$project_root/Resources/EncoderSources.lock.json" "$source_root" <<'PY'
import json, hashlib, sys
from pathlib import Path
for name,expected in json.load(open(sys.argv[1])).items():
    actual=hashlib.sha256((Path(sys.argv[2])/name).read_bytes()).hexdigest()
    if actual!=expected: raise SystemExit('Encoder source checksum mismatch: '+name)
PY
cd "$build_root"
/usr/bin/tar -xf "$source_root/lame-3.100.tar.gz"
/usr/bin/tar -xf "$source_root/ffmpeg-8.1.2.tar.xz"
jobs=8
cd "$build_root/lame-3.100"
if [[ ! -f "$prefix/lib/libmp3lame.a" ]]; then
    ./configure --prefix="$prefix" --disable-shared --enable-static --disable-frontend > "$encoder_root/lame-configure.log" 2>&1
    make -j "$jobs" > "$encoder_root/lame-build.log" 2>&1
    make install > "$encoder_root/lame-install.log" 2>&1
fi
cd "$build_root/ffmpeg-8.1.2"
./configure --prefix="$prefix" --disable-everything --disable-autodetect --disable-network --disable-doc --disable-debug \
    --disable-shared --enable-static --disable-gpl --disable-nonfree --enable-ffmpeg --disable-ffplay --disable-ffprobe \
    --enable-libmp3lame --enable-zlib --enable-encoder=libmp3lame,aac,flac,mjpeg,pcm_s16le \
    --enable-decoder=flac,pcm_s16be,pcm_s16le,png,mjpeg,mp3,mp3float,aac \
    --enable-demuxer=aiff,concat,flac,image2,image_png_pipe,image_jpeg_pipe,mp3,wav,mov,ffmetadata \
    --enable-parser=png,mjpeg,flac,mpegaudio,aac \
    --enable-muxer=mp3,flac,mp4,ipod,wav,null --enable-protocol=file,pipe \
    --enable-filter=aformat,anull,apad,atempo,aresample,scale,format --enable-swresample --enable-swscale \
    --extra-cflags="-I$prefix/include" --extra-ldflags="-L$prefix/lib" > "$encoder_root/ffmpeg-configure.log" 2>&1
make -j "$jobs" > "$encoder_root/ffmpeg-build.log" 2>&1
make install > "$encoder_root/ffmpeg-install.log" 2>&1
/usr/bin/otool -L "$prefix/bin/ffmpeg" > "$encoder_root/dependencies.txt"
if /usr/bin/grep -E '/opt/|/usr/local/|@rpath' "$encoder_root/dependencies.txt"; then
    print -u2 "Encoder still has non-system dynamic dependencies. Refusing to bundle it."
    exit 1
fi
mkdir -p "$encoder_root/licenses"
cp COPYING.LGPLv2.1 LICENSE.md "$encoder_root/licenses/"
cp "$build_root/lame-3.100/COPYING" "$encoder_root/licenses/LAME-LICENSE.txt"
cp "$project_root/Scripts/build-encoder.sh" "$encoder_root/licenses/BUILD.txt"
cp "$project_root/Resources/EncoderSources.lock.json" "$encoder_root/licenses/"
print "FFmpeg 8.1.2 and LAME 3.100; audio/image codecs only, network and GPL components disabled. Source archives are included in the application bundle for rebuilding the executable." > "$encoder_root/licenses/NOTICE.txt"
mkdir -p "$encoder_root/prefix/bin"
cp "$prefix/bin/ffmpeg" "$encoder_root/prefix/bin/ffmpeg"
python3 - "$project_root" <<'PY'
from pathlib import Path
import hashlib, json, platform, sys
root=Path(sys.argv[1])
record={'build_script_sha256':hashlib.sha256((root/'Scripts/build-encoder.sh').read_bytes()).hexdigest(),
        'architecture':platform.machine(),'minimum_macos':'14.0'}
(root/'.build/encoder/build.json').write_text(json.dumps(record,indent=2)+'\n')
PY
print "Built standalone encoder: $encoder_root/prefix/bin/ffmpeg"
