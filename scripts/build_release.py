"""Build a tested, signed Play bundle. Does not upload or publish."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--flutter', default=shutil.which('flutter') or 'flutter')
    parser.add_argument('--version-code', type=int)
    args = parser.parse_args()
    code = args.version_code or int(time.time()) - 1577836800
    if not 1 <= code <= 2100000000:
        raise SystemExit('Version code must be within Play limits.')
    if not (ROOT / 'android/key.properties').is_file():
        raise SystemExit('Run scripts/setup_signing.py first.')
    for command in [['pub', 'get'], ['analyze'], ['test'],
                    ['build', 'appbundle', '--release', f'--build-number={code}']]:
        subprocess.run([args.flutter, *command], cwd=ROOT, check=True)
    bundle = ROOT / 'build/app/outputs/bundle/release/app-release.aab'
    (ROOT / 'build/release.json').write_text(json.dumps({'versionCode': code, 'bundle': str(bundle),
                                                      'packageName': 'com.platypus.revev'}, indent=2))
    print(f'Signed bundle ready: {bundle} (version code {code}). No upload performed.')

if __name__ == '__main__':
    main()
