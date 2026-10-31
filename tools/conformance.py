"""Run independent story tests. No interpreter logic lives in this script."""
from pathlib import Path
import argparse
import base64
import hashlib
import io
import json
import re
import shutil
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "test-results"


def load_praxix():
    """Fetch exactly the tested story, without relying on one archive host."""
    story = RESULTS / "praxix.z5"
    story_hash = "bef3bdc2543cc7161833062855aa9bb1682db9eca69d9d36e9101347c21b48ac"
    archive_hash = "c654d656fb426ae1b386e5ab9c44cc5062eade4a8c3bce69c9e61191221501ad"
    archive = RESULTS / "praxix.zip"
    if story.exists():
        assert hashlib.sha256(story.read_bytes()).hexdigest() == story_hash, "Cached Praxix story hash mismatch"
        return story

    def from_archive(data):
        assert hashlib.sha256(data).hexdigest() == archive_hash, "Praxix archive hash mismatch"
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            name = next(name for name in z.namelist() if name.endswith("praxix.z5"))
            return z.read(name)

    if archive.exists():
        payload = from_archive(archive.read_bytes())
    else:
        sources = [
            ("blob", "https://api.github.com/repos/curiousdannii/if/git/blobs/87f83a7ab4e33422807d0eff15d7b80c8e06771d"),
            ("zip", "https://ifarchive.org/if-archive/infocom/interpreters/tools/praxix.zip"),
            ("zip", "https://mirror.ifarchive.org/if-archive/infocom/interpreters/tools/praxix.zip"),
        ]
        failures = []
        payload = None
        for kind, url in sources:
            try:
                request = urllib.request.Request(url, headers={"User-Agent": "moon-zvm-conformance/0.1"})
                with urllib.request.urlopen(request, timeout=20) as response:
                    data = response.read(131073)
                assert len(data) <= 131072, "Praxix response exceeds expected size"
                if kind == "blob":
                    obj = json.loads(data)
                    assert obj["encoding"] == "base64", "Unexpected blob encoding"
                    payload = base64.b64decode(obj["content"])
                else:
                    payload = from_archive(data)
                assert hashlib.sha256(payload).hexdigest() == story_hash, "Praxix story hash mismatch"
                break
            except (OSError, ValueError, KeyError, AssertionError, zipfile.BadZipFile) as error:
                failures.append(f"{url}: {type(error).__name__}: {error}")
                payload = None
        if payload is None:
            raise AssertionError("Praxix download failed:\n" + "\n".join(failures))
    assert hashlib.sha256(payload).hexdigest() == story_hash, "Praxix story hash mismatch"
    story.write_bytes(payload)
    return story


def run_story(path, commands="", timeout=30):
    program = ROOT / "_build/js/debug/build/cmd/main/main.js"
    result = subprocess.run(["node", str(program), str(path)], input=commands,
                            text=True, encoding="utf-8", capture_output=True, timeout=timeout, cwd=ROOT)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--praxix", action="store_true", help="Download pinned Praxix story and run its interactive 'all' command")
    args = parser.parse_args()
    subprocess.run([shutil.which("moon"), "build", "cmd/main", "--target", "js"], cwd=ROOT, check=True)
    RESULTS.mkdir(exist_ok=True)
    for version, passed in [(3, 349), (5, 406)]:
        transcript = run_story(ROOT / f"fixtures/czech/czech.z{version}")
        (RESULTS / f"czech-v{version}.txt").write_text(transcript, encoding="utf8")
        assert re.search(rf"Passed: {passed}, Failed: 0, Print tests: 19", transcript), transcript
        assert "Last test: quit!" in transcript
        print(f"Czech v{version}: {passed} automatic assertions passed; 19 visual checks are not automated")
    for version in [3, 5]:
        savefile = RESULTS / f"lantern-v{version}.sav"
        transcript = run_story(ROOT / f"examples/lantern.z{version}",
                               f"north\ntake\nsave\n{savefile}\nsouth\nrestore\n{savefile}\nlook\nsouth\nsouth\nquit\n")
        (RESULTS / f"lantern-v{version}.txt").write_text(transcript, encoding="utf8")
        assert transcript.count("The watchtower overlooks") == 2, transcript
        assert "You have found the lost keeper's key!" in transcript, transcript
        data = savefile.read_bytes()
        assert data[:4] == b"FORM" and data[8:12] == b"IFZS"
        print(f"Original adventure v{version}: commands and Quetzal save/restore passed")
    if args.praxix:
        transcript = run_story(load_praxix(), "all\nquit\n")
        (RESULTS / "praxix.txt").write_text(transcript, encoding="utf8")
        assert "All tests passed." in transcript and "FAIL" not in transcript, transcript
        assert "Stopping, interpreter is only version 0.0." in transcript
        print("Praxix: automatic groups passed; Standard 1.1/1.2 visual/capability groups skipped")


if __name__ == "__main__":
    main()
