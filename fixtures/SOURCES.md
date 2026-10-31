# Third-party test stories

`czech/czech.z5` is the unmodified compiled story from Czech 0.8.
`czech/czech.z3` was compiled from the same archive's `czech.inf` using Inform 6.44:

```
inform6 -v3 czech.inf czech.z3
```

- Czech archive: https://ifarchive.org/if-archive/infocom/interpreters/tools/czech_0_8.zip
- SHA-256: `d0795723e98563050575c4d3c08fdd29ade2543e132d8190255763e3bf6fef6a`
- Inform Windows archive: https://ifarchive.org/if-archive/infocom/compilers/inform6/executables/inform644_win32.zip
- SHA-256: `70900ea74795e8b7cccc39f7666cf9e26112dfda71845c99b569f79fd1f8ebc3`
- Retrieved 2026-10-31. Czech's full notice and license are preserved in `czech/README.txt`.

Czech permits use, modification and redistribution for any purpose with its notice preserved.
It is test data; no interpreter implementation was copied from Czech, Inform or another VM.

Praxix is downloaded only when `tools/conformance.py --praxix` is requested. The script verifies its archive hash. Praxix is interactive; the runner feeds `all` and `quit` and checks its own assertion summary. Its Standard 1.1 visual colour test and Standard 1.2 capability test are skipped because this interpreter intentionally advertises revision 0.0. This is not a claim of complete Z-machine conformance.

The included `examples/lantern.inf` and `.z3` / `.z5` builds are original Apache-2.0 material. They use no Inform library. Zork and other proprietary games are not included.
