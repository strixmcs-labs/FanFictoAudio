#!/usr/bin/env python3
"""Real local speech/encoder validation; retains authored fixtures and reports."""
import hashlib
import json
from pathlib import Path
import signal
import struct
import subprocess
import sys
import tempfile
import time
import zipfile
import zlib

project = Path(__file__).resolve().parent.parent
cli = Path(sys.argv[1]).resolve()
encoder = Path(sys.argv[2]).resolve()
probe = Path('/opt/homebrew/bin/ffprobe')
root = Path(tempfile.mkdtemp(prefix='v0.2-smoke-', dir=project/'dist'))

def cover_png():
    def chunk(kind, data):
        return struct.pack('>I', len(data))+kind+data+struct.pack('>I', zlib.crc32(kind+data)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR', struct.pack('>IIBBBBB',64,64,8,2,0,0,0))+chunk(b'IDAT',zlib.compress((b'\0'+bytes([50,110,120])*64)*64))+chunk(b'IEND',b'')

def book(path, long=False):
    prose = 'This original demonstration checks how a book becomes an audiobook. We keep the paragraphs in order, listen to the installed voice, and retain completed passages when conversion is interrupted. '
    text = prose*180 if long else prose
    with zipfile.ZipFile(path,'w') as archive:
        archive.writestr('mimetype','application/epub+zip')
        resources = {
            'META-INF/container.xml':'<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
            'book.opf':'<package xmlns="http://www.idpf.org/2007/opf"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Version Two Demo</dc:title><dc:creator>EPUB to MP3</dc:creator><dc:language>en-US</dc:language></metadata><manifest><item id="front" href="front.xhtml" media-type="application/xhtml+xml"/><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/><item id="two" href="two.xhtml" media-type="application/xhtml+xml"/><item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/></manifest><spine><itemref idref="front"/><itemref idref="one"/><itemref idref="two"/></spine></package>',
            'front.xhtml':'<html xmlns:epub="http://www.idpf.org/2007/ops"><body epub:type="titlepage"><h1>Title Page</h1><p>Version Two Demo</p></body></html>',
            'one.xhtml':'<html xmlns:epub="http://www.idpf.org/2007/ops"><body><h1>Chapter One</h1><p>'+text+'<a epub:type="noteref">1</a></p><aside epub:type="footnote">This note can be excluded.</aside></body></html>',
            'two.xhtml':'<html><body><h1>Chapter Two</h1><p>Our second chapter closes the demonstration. The exported audiobook carries both its chapter names and its cover image.</p></body></html>',
        }
        for name,data in resources.items(): archive.writestr(name,data,compress_type=zipfile.ZIP_DEFLATED)
        archive.writestr('cover.png',cover_png(),compress_type=zipfile.ZIP_DEFLATED)

def command(source, output, *extra):
    return [str(cli),'export',str(source),str(output),'--voice','Samantha','--rate','400','--ffmpeg',str(encoder),*extra]

def inspect(path):
    data=json.loads(subprocess.check_output([str(probe),'-v','error','-show_streams','-show_chapters','-show_format','-of','json',str(path)]))
    audio=[s for s in data['streams'] if s['codec_type']=='audio'][0]
    assert audio['sample_rate']=='44100'
    assert float(data['format']['duration'])>2
    subprocess.run([str(encoder),'-v','error','-i',str(path),'-map','0:a:0','-f','null','-'],check=True)
    return data

demo=root/'demo.epub'; book(demo)
report={}
for name,mode in [('single.mp3',[]),('chapters',['--chapters']),('book.m4b',['--m4b'])]:
    output=root/name
    subprocess.run(command(demo,output,*mode,'--bitrate','192','--pause-seconds','1.2','--skip-front-matter','--skip-footnotes'),check=True)
    paths=sorted(output.glob('*.mp3')) if output.is_dir() else [output]
    for path in paths:
        data=inspect(path)
        assert any(s.get('disposition',{}).get('attached_pic')==1 for s in data['streams']), 'Missing cover artwork'
        if path.suffix=='.m4b':
            assert [c['tags']['title'] for c in data['chapters']]==['Chapter One','Chapter Two']
            assert data['streams'][0]['codec_name']=='aac' or any(s.get('codec_name')=='aac' for s in data['streams'])
        report[str(path.relative_to(root))]={'duration':data['format']['duration'],'chapters':len(data.get('chapters',[]))}

long=root/'long.epub'; book(long,True)
cache=root/'checkpoint'; resumed=root/'resumed.mp3'
args=command(long,resumed,'--checkpoint',str(cache),'--skip-front-matter','--skip-footnotes')
log=(root/'pause.log').open('w')
process=subprocess.Popen(args,stdout=log,stderr=subprocess.STDOUT)
deadline=time.monotonic()+90
while time.monotonic()<deadline:
    if list(cache.glob('*/passages.json')): break
    if process.poll() is not None: raise RuntimeError('Export finished before checkpoint pause could be tested')
    time.sleep(0.01)
else: process.kill(); raise RuntimeError('No checkpoint was committed')
process.send_signal(signal.SIGINT)
assert process.wait(timeout=10)==130
log.close()
assert not resumed.exists(), 'Paused export published incomplete output'
assert not list(root.glob('.epub-audio-*')), 'Paused export left staging output'
with (root/'resume.log').open('w') as log:
    subprocess.run(args,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
assert 'Resumed completed passage' in (root/'resume.log').read_text()
assert not list(cache.glob('*/passages.json')), 'Successful export kept completed checkpoints'
inspect(resumed)
report['resume']='SIGINT interrupted export, completed passages reused, final audio decoded, checkpoints cleaned.'
(root/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('Verified MP3, chapter MP3, M4B with chapters/artwork, and real pause/resume:',root)
