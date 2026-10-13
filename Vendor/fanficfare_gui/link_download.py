"""Story-page and bounded direct-EPUB downloads for FanFic to Audio.
Copyright 2026 Matt and contributors. Licensed under Apache 2.0.
"""
from pathlib import Path, PurePosixPath
import posixpath
import re
import tempfile
import time
from urllib.parse import urlsplit, unquote
from xml.etree import ElementTree as ET
import zipfile

import requests
from fanficfare.exceptions import UnknownSite, InvalidStoryURL
from .engine import execute, publish_new, validate_output

MAX_DOWNLOAD = 256 * 1024 * 1024
MAX_RESOURCE = 32 * 1024 * 1024


def checked_url(source):
    parsed = urlsplit(source)
    if parsed.scheme.lower() not in {"http", "https"} or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("Use a complete http or https link without embedded login credentials.")
    return parsed


def download_link(request, emit, session):
    source = request["source"]
    parsed = checked_url(source)
    kind = request.get("source_kind", "auto")
    if kind not in {"auto", "story", "epub"}:
        raise ValueError("Choose automatic detection, story page, or direct EPUB.")
    if kind == "epub" or (kind == "auto" and parsed.path.lower().endswith(".epub")):
        return direct_epub(request, emit)
    try:
        return execute(request, emit, session)
    except (UnknownSite, InvalidStoryURL):
        if kind != "auto":
            raise
        # Adapter lookup fails before downloading chapters. Do not fall back
        # on login, network, or chapter errors from a recognized story site.
        return direct_epub(request, emit)


def epub_metadata(path):
    def xml(data):
        if re.search(br"<!\s*ENTITY\b", data, re.I):
            raise ValueError("EPUB XML entity declarations are unsupported.")
        return ET.fromstring(data)

    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        names = [item.filename for item in entries]
        if len(names) != len(set(names)):
            raise ValueError("EPUB contains duplicate ZIP entries.")
        if any(PurePosixPath(name).is_absolute() or ".." in PurePosixPath(name).parts or "\\" in name for name in names):
            raise ValueError("EPUB contains an unsafe ZIP path.")
        if any(item.file_size > MAX_RESOURCE for item in entries) or sum(item.file_size for item in entries) > MAX_DOWNLOAD:
            raise ValueError("EPUB resources exceed the supported size limit.")
        validate_output(path, "epub")
        container = xml(archive.read("META-INF/container.xml"))
        rootfile = container.find(".//{*}rootfile")
        if rootfile is None:
            raise ValueError("EPUB is missing its package document.")

        def resolve(href, document=""):
            parts = urlsplit(unquote(href))
            if parts.scheme or parts.netloc:
                raise ValueError("EPUB reading order cannot use an external resource.")
            name = posixpath.normpath(posixpath.join(posixpath.dirname(document), parts.path))
            if name.startswith("../") or name.startswith("/") or name not in names:
                raise ValueError("EPUB is missing a reading-order resource.")
            return name

        package_path = resolve(rootfile.get("full-path", ""))
        package = xml(archive.read(package_path))
        manifest = {item.get("id"): item for item in package.findall("./{*}manifest/{*}item")}
        spine = package.findall("./{*}spine/{*}itemref")
        if not spine:
            raise ValueError("EPUB has no reading order.")
        for ref in spine:
            item = manifest.get(ref.get("idref"))
            if item is None:
                raise ValueError("EPUB references a missing chapter.")
            resource = resolve(item.get("href", ""), package_path)
            if item.get("media-type") in {"application/xhtml+xml", "text/html"}:
                xml(archive.read(resource))
        def value(name):
            node = package.find("./{*}metadata/{*}" + name)
            return " ".join("".join(node.itertext()).split()) if node is not None else ""
        return {"title": value("title") or path.stem, "author": value("creator")}


def direct_epub(request, emit):
    source = request["source"]
    checked_url(source)
    directory = Path(request["output"]).expanduser().resolve()
    directory.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".fff-", dir=request.get("work_dir") or directory) as work:
        staged = Path(work) / "download.epub"
        emit({"type": "activity", "message": "Downloading EPUB file…"})
        with requests.Session() as connection:
            connection.trust_env = False  # No ambient .netrc credentials.
            connection.max_redirects = 10
            connection.headers["User-Agent"] = "FanFicToAudio/1.4"
            with connection.get(source, stream=True, timeout=(15, 30)) as response:
                checked_url(response.url)
                if not 200 <= response.status_code < 300:
                    raise ValueError(f"EPUB download failed (HTTP {response.status_code}).")
                length = response.headers.get("Content-Length", "")
                expected = int(length) if length.isdigit() else 0
                if expected > MAX_DOWNLOAD:
                    raise ValueError("EPUB download exceeds the 256 MB limit.")
                size = 0
                next_update = 0.0
                with staged.open("wb") as stream:
                    for chunk in response.iter_content(65536):
                        if not chunk:
                            continue
                        size += len(chunk)
                        if size > MAX_DOWNLOAD:
                            raise ValueError("EPUB download exceeds the 256 MB limit.")
                        stream.write(chunk)
                        if time.monotonic() >= next_update:
                            next_update = time.monotonic() + 0.2
                            emit({"type": "progress", "percent": min(95, size * 95 / expected) if expected else None,
                                  "message": f"Downloaded {size / 1048576:.1f} MB…"})
        if not zipfile.is_zipfile(staged):
            raise ValueError("The link returned a web page or another file, not an EPUB. Use a supported story page or a direct EPUB download link.")
        metadata = epub_metadata(staged)
        emit({"type": "metadata", "metadata": metadata})
        emit({"type": "progress", "percent": 99, "message": "Saving verified EPUB…", "finalizing": True})
        # Bound UTF-8 filenames as well as character count before publication.
        name = metadata["title"] + (" - " + metadata["author"] if metadata["author"] else "")
        name = name.encode("utf-8")[:180].decode("utf-8", errors="ignore")
        target = publish_new(staged, directory, name, ".epub")
        return {"status": "done", "metadata": metadata, "path": str(target)}
