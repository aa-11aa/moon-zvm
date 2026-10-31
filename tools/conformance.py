"""Run independent story tests. No interpreter logic lives in this script."""
from pathlib import Path
import argparse
import hashlib
import re
import shutil
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "test-results"


def run_story(path, commands="", timeout=30):
    program = ROOT / "_build/js/debug/build/cmd/main/main.js"
    result = subprocess.run(["node", str(program), str(path)], input=commands,
                            text=True, encoding="utf-8", capture_output=True, timeout=timeout, cwd=ROOT)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--praxix", action="store_true", help="Download pinned Praxix archive and run its interactive 'all' command")
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
        archive = RESULTS / "praxix.zip"
        expected = "c654d656fb426ae1b386e5ab9c44cc5062eade4a8c3bce69c9e61191221501ad"
        if not archive.exists():
            urls = [f"https://{host}/if-archive/infocom/interpreters/tools/praxix.zip"
                    for host in ["ifarchive.org", "mirror.ifarchive.org"]]
            for url in urls:
                try:
                    with urllib.request.urlopen(url, timeout=30) as response:
                        archive.write_bytes(response.read())
                    break
                except OSError:
                    continue
        assert archive.exists(), "Praxix download failed"
        assert hashlib.sha256(archive.read_bytes()).hexdigest() == expected, "Praxix archive hash mismatch"
        with zipfile.ZipFile(archive) as z:
            # Do not extract arbitrary paths from a remote archive.
            story = next(name for name in z.namelist() if name.endswith("praxix.z5"))
            (RESULTS / "praxix.z5").write_bytes(z.read(story))
        transcript = run_story(RESULTS / "praxix.z5", "all\nquit\n")
        (RESULTS / "praxix.txt").write_text(transcript, encoding="utf8")
        assert "All tests passed." in transcript and "FAIL" not in transcript, transcript
        assert "Stopping, interpreter is only version 0.0." in transcript
        print("Praxix: automatic groups passed; Standard 1.1/1.2 visual/capability groups skipped")


if __name__ == "__main__":
    main()
