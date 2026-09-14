# Contributing

Thanks for helping improve Vibe Terminal. By submitting a contribution, you
confirm that you have the right to submit it and agree that the copyright
holder may use, modify, relicense, and distribute the contribution as part of
the project.

## Before opening a pull request

1. Open an issue first for substantial changes so the direction can be agreed.
2. Keep changes focused and do not include generated binaries, local runtime
   state, credentials, or secrets.
3. Run `flutter analyze`.
4. Explain the problem, solution, and validation in the pull request template.

## Development setup

```sh
flutter pub get
flutter analyze
```

Note: this repository does not carry its test suite (see `README.md`); a
pull request here changes the released app source, not the internal
maintenance repository.

## Licensing of contributions

The repository is source-available under [LICENSE](LICENSE), rather than an
OSI-approved open-source license. Contributions do not grant permission to
reuse the code outside that license. Contact the copyright holder through a
private GitHub discussion before reusing, distributing, or relicensing code.
