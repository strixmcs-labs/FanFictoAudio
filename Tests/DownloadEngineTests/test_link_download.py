"""Real localhost HTTP transfers, EPUB integrity, and publication boundaries."""
import io
import json
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
import subprocess
import sys
import threading
import zipfile

import pytest
from fanficfare_gui import link_download
from fanficfare_gui.session import Session


def epub(missing=False):
    result = io.BytesIO()
    with zipfile.ZipFile(result, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("mimetype", "application/epub+zip")
        archive.writestr("META-INF/container.xml", '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>')
        archive.writestr("book.opf", '<package xmlns="http://www.idpf.org/2007/opf"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Link Demo</dc:title><dc:creator>Test Author</dc:creator></metadata><manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="one"/></spine></package>')
        if not missing:
            archive.writestr("one.xhtml", '<html><body><h1>One</h1><p>An original book for testing link downloads and narration.</p></body></html>')
    return result.getvalue()


@pytest.fixture
def server():
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/redirect":
                self.send_response(302); self.send_header("Location", "/book.epub"); self.end_headers(); return
            body = b"<html>Login required</html>" if self.path == "/web" else epub(self.path == "/missing.epub")
            self.send_response(404 if self.path == "/not-found" else 200)
            if self.path != "/stream":
                self.send_header("Content-Length", str(link_download.MAX_DOWNLOAD + 1) if self.path == "/oversized.epub" else str(len(body)))
            self.end_headers(); self.wfile.write(body)
        def log_message(self, *args): pass
    service = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=service.serve_forever, daemon=True); thread.start()
    yield f"http://127.0.0.1:{service.server_port}"
    service.shutdown(); service.server_close(); thread.join()


def run(root, source, kind="auto", emit=lambda event: None):
    session = Session()
    try:
        return link_download.download_link({"operation": "download", "source": source, "output": str(root), "source_kind": kind}, emit, session)
    finally: session.close()


def test_direct_downloads_and_preserves_existing_books(tmp_path, server):
    events = []
    first = run(tmp_path, server + "/book.epub", emit=events.append)
    original = Path(first["path"]).read_bytes()
    second = run(tmp_path, server + "/redirect", kind="epub")
    assert first["path"] != second["path"]
    assert Path(first["path"]).read_bytes() == original == epub()
    assert second["metadata"] == {"title": "Link Demo", "author": "Test Author"}
    assert any(e.get("finalizing") for e in events)
    assert not list(tmp_path.glob(".fff-*"))


def test_auto_accepts_opaque_epub_endpoints(tmp_path, server):
    result = run(tmp_path, server + "/download?book=123")
    assert Path(result["path"]).read_bytes() == epub()


@pytest.mark.parametrize("path", ["/web", "/not-found", "/missing.epub", "/oversized.epub"])
def test_bad_responses_do_not_publish(tmp_path, server, path):
    with pytest.raises((ValueError, KeyError)):
        run(tmp_path, server + path, kind="epub")
    assert not list(tmp_path.iterdir())


def test_streaming_download_enforces_limit_without_content_length(tmp_path, server, monkeypatch):
    monkeypatch.setattr(link_download, "MAX_DOWNLOAD", 64)
    with pytest.raises(ValueError, match="limit"):
        run(tmp_path, server + "/stream", kind="epub")
    assert not list(tmp_path.iterdir())


def test_zip_bombs_and_unsafe_xml_are_rejected_before_publication(tmp_path):
    path = tmp_path / "bomb.epub"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("large", b"0" * (link_download.MAX_RESOURCE + 1))
    with pytest.raises(ValueError, match="size limit"):
        link_download.epub_metadata(path)
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("mimetype", "application/epub+zip")
        archive.writestr("META-INF/container.xml", '<!DOCTYPE container [<!ENTITY secret SYSTEM "file:///etc/passwd">]><container>&secret;</container>')
    with pytest.raises(ValueError, match="entity"):
        link_download.epub_metadata(path)


def test_bundled_protocol_needs_ack_for_direct_epub(tmp_path, server):
    root = Path(__file__).resolve().parents[2]
    request = tmp_path / "request.json"
    request.write_text(json.dumps({"operation": "download", "source": server + "/book.epub", "output": str(tmp_path)}))
    result = subprocess.run([sys.executable, str(root / "Scripts/download-worker.py"), "--request", str(request)], input="", text=True, capture_output=True, timeout=30, env=dict(os.environ, PYTHONPATH=str(root / "Vendor")))
    assert result.returncode == 1
    assert json.loads(result.stdout.splitlines()[-1])["type"] == "error"
    assert not list(tmp_path.glob("*.epub")) and not list(tmp_path.glob(".fff-*"))


def test_story_adapter_remains_supported(tmp_path):
    result = run(tmp_path, "http://test1.com?sid=1[1-2]")
    assert result["metadata"]["title"]
    assert Path(result["path"]).is_file()


@pytest.mark.parametrize("source", ["file:///etc/passwd", "ftp://example.com/book.epub", "https://user:password@example.com/book.epub"])
def test_bad_urls_are_rejected(source):
    with pytest.raises(ValueError): link_download.checked_url(source)


def test_standard_external_doctype_does_not_block_valid_epub(tmp_path):
    path = tmp_path / "book.epub"
    with zipfile.ZipFile(io.BytesIO(epub())) as source, zipfile.ZipFile(path, "w") as target:
        for name in source.namelist():
            data = source.read(name)
            if name == "one.xhtml":
                data = b'<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">' + data
            target.writestr(name, data)
    assert link_download.epub_metadata(path)["title"] == "Link Demo"
