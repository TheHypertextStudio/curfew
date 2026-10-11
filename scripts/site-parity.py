#!/usr/bin/env python3
"""Verify Astro output against the retained pre-migration HTML contract."""
import hashlib
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

class Contract(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.text = []
        self.links = []
        self.images = []
        self.ids = []
        self.title = []
        self.skip = 0
        self.in_title = False
        self.scripts = []
        self.script_attributes = []
        self.script = None
        self.body_class = None
        self.metas = []
        self.canonical = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in ('script', 'style'):
            self.skip += 1
        if tag == 'script':
            self.script = []
            self.script_attributes.append({key: value for key, value in attrs.items()
                                           if key not in ('is:inline', 'is:raw')})
        if tag == 'title':
            self.in_title = True
        if tag == 'body':
            self.body_class = attrs.get('class')
        if 'id' in attrs:
            self.ids.append(attrs['id'])
        if tag == 'a':
            self.links.append(attrs.get('href'))
        if tag == 'img':
            self.images.append({key: attrs.get(key) for key in ('src', 'alt', 'width', 'height')})
        if tag == 'meta':
            self.metas.append(attrs)
        if tag == 'link' and attrs.get('rel') == 'canonical':
            self.canonical.append(attrs.get('href'))

    def handle_endtag(self, tag):
        if tag in ('script', 'style'):
            self.skip -= 1
        if tag == 'script' and self.script is not None:
            self.scripts.append(hashlib.sha256(''.join(self.script).strip().encode()).hexdigest())
            self.script = None
        if tag == 'title':
            self.in_title = False

    def handle_data(self, data):
        if self.script is not None:
            self.script.append(data)
        if self.in_title:
            self.title.append(data)
        if not self.skip:
            self.text.append(data)

    def result(self):
        return {'text': re.sub(r'\s+', ' ', ' '.join(self.text)).strip(), 'title': ''.join(self.title),
                'links': self.links, 'images': self.images, 'ids': self.ids,
                'body_class': self.body_class, 'metas': self.metas, 'canonical': self.canonical,
                'scripts': self.scripts, 'script_attributes': self.script_attributes}

def contract(path):
    parser = Contract()
    parser.feed(path.read_text())
    return parser.result()

def verify():
    expected = json.loads((ROOT / 'verification/website/content-baseline.json').read_text())
    failed = []
    for page, baseline in expected['pages'].items():
        output = ROOT / 'landing/dist' / page
        if not output.is_file():
            failed.append(f'{page}: missing output')
            continue
        actual = contract(output)
        for field, value in baseline.items():
            if actual[field] != value:
                failed.append(f'{page}: changed {field}')
    for name, digest in expected['public_assets'].items():
        output = ROOT / 'landing/dist' / name
        if not output.is_file() or hashlib.sha256(output.read_bytes()).hexdigest() != digest:
            failed.append(f'{name}: changed asset bytes')
    if failed:
        raise SystemExit('\n'.join(failed))
    print(f"Astro preserves {len(expected['pages'])} pages, scripts, anchors, metadata, links and {len(expected['public_assets'])} asset byte digests")

if __name__ == '__main__':
    verify()
