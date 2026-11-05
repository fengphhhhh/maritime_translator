"""Verify reviewed corpus assets and reject model weights in the light IPA."""
import argparse
import hashlib
from pathlib import Path
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parent.parent
ASSETS = 'Payload/Runner.app/Frameworks/App.framework/flutter_assets/assets/'
MODEL_NAMES = (
    'ggml-large-v3-turbo-q5_0.bin',
    'qwen2.5-1.5b-instruct-q4_k_m.gguf',
)


def digest(stream):
    result = hashlib.sha256()
    while chunk := stream.read(1024 * 1024):
        result.update(chunk)
    return result.hexdigest()


def verify(ipa):
    with ZipFile(ipa) as archive:
        for name in archive.namelist():
            if (name.rsplit('/', 1)[-1] in MODEL_NAMES or
                    (name.startswith(ASSETS + 'models/') and
                     name.endswith(('.bin', '.gguf')))):
                raise ValueError(f'Model weights must not be bundled: {name}')
        print('Verified: no bundled model weights')
        for name in ('maritime_dialogues.json', 'maritime_turns.json'):
            with (ROOT / 'assets' / 'corpus' / name).open('rb') as stream:
                expected_hash = digest(stream)
            with archive.open(ASSETS + 'corpus/' + name) as stream:
                if digest(stream) != expected_hash:
                    raise ValueError(f'Bundled corpus differs from reviewed source: {name}')
            print(f'Verified IPA corpus: {name}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    args = parser.parse_args()
    try:
        verify(args.ipa)
    except (KeyError, ValueError, OSError) as error:
        parser.exit(1, f'IPA validation failed: {error}\n')
