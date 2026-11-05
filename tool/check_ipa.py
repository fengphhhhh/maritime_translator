"""Fail the build if the deliverable IPA omits or corrupts offline assets."""
import argparse
import hashlib
from pathlib import Path
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parent.parent
ASSETS = 'Payload/Runner.app/Frameworks/App.framework/flutter_assets/assets/'
MODELS = {
    'ggml-large-v3-turbo-q5_0.bin': (
        574041195,
        '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2',
    ),
    'qwen2.5-1.5b-instruct-q4_k_m.gguf': (
        1117320736,
        '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e',
    ),
}


def digest(stream):
    result = hashlib.sha256()
    while chunk := stream.read(1024 * 1024):
        result.update(chunk)
    return result.hexdigest()


def verify(ipa):
    with ZipFile(ipa) as archive:
        for name, (size, expected_hash) in MODELS.items():
            info = archive.getinfo(ASSETS + 'models/' + name)
            if info.file_size != size:
                raise ValueError(f'Incorrect bundled model size: {name}')
            with archive.open(info) as stream:
                if digest(stream) != expected_hash:
                    raise ValueError(f'Incorrect bundled model SHA-256: {name}')
            print(f'Verified IPA model: {name}')
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
