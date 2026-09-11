"""Fetch the pinned CC0 instrument subset; no executable content is downloaded."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import urllib.request

HERE = Path(__file__).resolve().parent
MANIFEST = HERE / 'vsco_source_manifest.json'
CACHE = HERE / '.sample-cache' / 'vsco'


def main():
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    CACHE.mkdir(parents=True, exist_ok=True)
    (CACHE.parent / '.gitignore').write_text('*\n')
    (CACHE.parent / '.gdignore').write_text('')
    base = 'https://raw.githubusercontent.com/sgossner/VSCO-2-CE/' + manifest['revision'] + '/'

    def fetch(item):
        assert item['url'].startswith(base)
        path = (CACHE / item['path']).resolve()
        assert path.is_relative_to(CACHE.resolve())
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists() or path.stat().st_size != item['size_bytes']:
            with urllib.request.urlopen(item['url'], timeout=45) as response:
                data = response.read(item['size_bytes'] + 1)
            assert len(data) == item['size_bytes'], item['path']
            assert data[:4] == b'RIFF' and data[8:12] == b'WAVE', item['path']
            path.write_bytes(data)
        return {'path': item['path'], 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'size_bytes': path.stat().st_size}

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        receipt = list(pool.map(fetch, manifest['samples']))
    assert manifest['license_url'].startswith(base)
    with urllib.request.urlopen(manifest['license_url'], timeout=30) as response:
        license_text = response.read().decode('utf-8')
    assert 'CC0' in license_text
    (CACHE / 'LICENSE.txt').write_text(license_text, encoding='utf-8')
    (CACHE / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'cache': str(CACHE), 'samples': len(receipt),
                      'bytes': sum(s['size_bytes'] for s in receipt)}, indent=2))


if __name__ == '__main__':
    main()
