# Native formatters

`native.py` formats stdin to stdout with pinned native tools. Run the setup commands
listed in `native-rules.json` once during repository setup; formatting never installs
or downloads tools. Missing tools stop the commit with a setup instruction.

SwiftFormat reuses `.swiftformat` when present. Curfew keeps its verified 0.63.1
wrapper and cache; other Swift repositories pin 0.64.0 with archive and executable
SHA-256 verification. The reviewed SwiftFormat archives require macOS.

Rust uses the exact rustup toolchain 1.98.1 and each manifest's edition. It formats
the staged source without resolving module files from the working tree and does not
change Cargo target directories. Meson 1.10.2 uses a dedicated cached Python
environment. Blueprint 0.22.2 uses its upstream pure Python formatter from a
checksum-verified source archive; it needs no GTK installation or running VM.

`python3 .hypertext/formatter-tools/test_native.py` verifies the native adapters.

`extras.py` provides Rubyfmt 0.14.1, Nanaimo 0.4.0 for annotated OpenStep
Xcode projects, Just 1.59.0, Mermaid Formatter 0.3.0, and .NET SDK 10.0.402
whitespace formatting. Archives are checksum verified during setup and each use.
The Xcode formatter rejects any change to the complete parsed property-list data.
.NET runs against an isolated folder with exact SDK selection and no project
restore. Run the applicable `extras.py setup-TOOL` commands from `native-rules.json`.
