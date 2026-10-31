"""Compare original story behavior and exchange Quetzal saves with external Frotz.

Frotz is a test-only, independently installed reference. No reference code or
executable is part of the module. Requires dfrotz compatible with -p/-w/-h.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile
from conformance import ROOT, RESULTS, run_story


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dfrotz", required=True, type=Path)
    args = parser.parse_args()
    reference = args.dfrotz.resolve()
    assert reference.is_file(), "Specify a local dfrotz executable"
    RESULTS.mkdir(exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix="interop-", dir=RESULTS))
    for version in [3, 5]:
        story = ROOT / f"examples/lantern.z{version}"
        moon_save = run_dir / f"exchange-moon-v{version}.sav"
        frotz_save = run_dir / f"exchange-frotz-v{version}.sav"
        moon_commands = f"north\ntake\nsave\n{moon_save.relative_to(ROOT).as_posix()}\nquit\n"
        moon_log = run_story(story, moon_commands)
        assert moon_save.exists() and "You take the lantern." in moon_log, moon_log
        frotz_commands = (
            f"restore\n{moon_save.relative_to(ROOT).as_posix()}\n"
            f"look\ninventory\nsave\n{frotz_save.relative_to(ROOT).as_posix()}\n"
            "south\nsouth\nquit\n"
        )
        result = subprocess.run(
            [str(reference), "-p", "-w", "120", "-h", "200", str(story.relative_to(ROOT))],
            input=frotz_commands, encoding="utf-8", errors="replace", capture_output=True,
            cwd=ROOT, timeout=30,
        )
        assert result.returncode == 0, result.stdout + result.stderr
        frotz_log = result.stdout
        assert "You carry a brass lantern." in frotz_log, frotz_log
        assert "You have found the lost keeper's key!" in frotz_log, frotz_log
        assert frotz_save.exists(), frotz_log
        resumed = run_story(story,
            f"restore\n{frotz_save.relative_to(ROOT).as_posix()}\n"
            "look\ninventory\nsouth\nsouth\nquit\n")
        assert "You carry a brass lantern." in resumed, resumed
        assert "The watchtower overlooks" in resumed, resumed
        assert "You have found the lost keeper's key!" in resumed, resumed
        (RESULTS / f"interop-frotz-v{version}.txt").write_text(frotz_log, encoding="utf8")
        (RESULTS / f"interop-moon-v{version}.txt").write_text(resumed, encoding="utf8")
        assert moon_save.read_bytes()[8:12] == b"IFZS"
        assert frotz_save.read_bytes()[8:12] == b"IFZS"
        print(f"v{version}: moon-zvm -> Frotz -> moon-zvm Quetzal exchange passed")


if __name__ == "__main__":
    main()
