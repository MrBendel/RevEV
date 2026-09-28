"""Create a dedicated local upload identity, or materialize CI signing secrets."""
import argparse
import base64
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ci', action='store_true')
    args = parser.parse_args()
    private = ROOT / 'secrets'
    private.mkdir(exist_ok=True)
    key = private / 'revev-upload.jks'
    config = private / 'android-upload.json'
    if args.ci:
        names = ['ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEYSTORE_ALIAS']
        missing = [name for name in names if not os.environ.get(name)]
        if missing:
            raise SystemExit('Missing GitHub secrets: ' + ', '.join(missing))
        key.write_bytes(base64.b64decode(os.environ[names[0]], validate=True))
        data = {'password': os.environ[names[1]], 'alias': os.environ[names[2]]}
    elif key.exists() and config.exists():
        data = json.loads(config.read_text())
    elif key.exists() or config.exists():
        raise SystemExit('Incomplete signing identity: restore its matching key/config; nothing overwritten.')
    else:
        data = {'password': secrets.token_hex(32), 'alias': 'revev-upload'}
        keytool = shutil.which('keytool')
        if not keytool and os.environ.get('JAVA_HOME'):
            keytool = str(Path(os.environ['JAVA_HOME']) / 'bin' / ('keytool.exe' if os.name == 'nt' else 'keytool'))
        if not keytool:
            raise SystemExit('Set JAVA_HOME to a JDK before creating the upload key.')
        env = dict(os.environ, REVEV_KEY_PASSWORD=data['password'])
        subprocess.run([keytool, '-genkeypair', '-keystore', str(key), '-storetype', 'PKCS12',
                        '-alias', data['alias'], '-keyalg', 'RSA', '-keysize', '4096', '-validity', '10000',
                        '-dname', 'CN=RevEV Upload', '-storepass:env', 'REVEV_KEY_PASSWORD',
                        '-keypass:env', 'REVEV_KEY_PASSWORD'], env=env, check=True, capture_output=True)
        config.write_text(json.dumps(data), encoding='utf-8')
    if not data['password'].isalnum() or not data['alias'].replace('-', '').isalnum():
        raise SystemExit('Signing fields must use alphanumeric characters (hyphens allowed in alias).')
    (ROOT / 'android/key.properties').write_text(
        f'storeFile={key.as_posix()}\nstorePassword={data["password"]}\n'
        f'keyAlias={data["alias"]}\nkeyPassword={data["password"]}\n', encoding='utf-8')
    print('Upload signing configured. Back up secrets/revev-upload.jks and secrets/android-upload.json together.')

if __name__ == '__main__':
    main()
