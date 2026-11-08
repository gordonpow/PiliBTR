/// Release tag of this build. Raise the default before each release: the
/// update check compares it with the newest tag on GitHub. A test build
/// can set an older one with `--dart-define=btr.version=v2.2.0-btr.1`.
const String btrVersion = String.fromEnvironment(
  'btr.version',
  defaultValue: 'v2.2.4',
);
