# QML common errors

## Build / packaging errors

### File not found after rename

If a `.qml` file in `lib/` is renamed, the build will fail because `flake.nix` copies files by explicit path:

```
error: path '/nix/store/...-source/lib/OldName.qml' does not exist
```

Fix: update the file reference in `flake.nix` to match the new name.

### NixConfig / NixBins missing properties

If `config.nix` or `ffi.nix` is edited and a property is removed or renamed, QML will fail at runtime with binding errors. These are not caught by `nix flake check` — you'll see them in the screenshot step or at launch.

```
TypeError: Cannot read property 'fontFamily' of undefined
```

Fix: ensure the property name in `config.nix`/`ffi.nix` matches what the QML references via `cfg.*` or `bin.*`.

## Runtime / logic errors

### Binding loop

```
QML <type>: Binding loop detected for property "<name>"
```

A property depends on itself, directly or transitively. Common when a computed property reads and writes the same state. Break the cycle by caching the intermediate value in a local variable inside the binding expression.

### View stuck / not switching

If `root.view` is set to a string that doesn't match any `visible:` condition, all content panels go invisible. Check for typos in the view name string — valid values are documented in [qml-structure.md](qml-structure.md).

### IPC call has no effect

If a `quickshell ipc call` command silently does nothing:
- Confirm the daemon is running: `quickshell ipc list`
- Confirm the target name matches the `IpcHandler { target: "..." }` value
- Confirm the function name and argument types match the handler's signature

## Screenshot validation

QML errors often only surface visually. After any QML edit, use `/validate-changes` step 4 (screenshot) to confirm:

- The targeted view renders correctly
- Text is readable and not clipped
- Font sizes look proportionate
- Colors match the expected palette role (see [qml-structure.md](qml-structure.md))
