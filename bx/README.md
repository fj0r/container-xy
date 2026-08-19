# bx Framework

The `bx` framework is a Nushell-based container image building framework that wraps `buildah` functionality. It is the core engine of the [xy](../README.md) image repository, replacing traditional Dockerfiles with programmable Nushell scripts.

## Build Context Fields

The `build` function accepts a record as context (passed via pipeline `$in`). Below are all the context fields used by the build process.

### Required Fields

| Field | Type | Description | Usage Location |
|-------|------|-------------|----------------|
| `from` | string | Base image name used for `buildah from` | `build.nu#L18` |
| `image` | string | Image name (without tag) used to construct the full image reference | `build.nu#L55` |

### Optional Fields

| Field | Type | Default | Description | Usage Location |
|-------|------|---------|-------------|----------------|
| `tag` | string | `'latest'` | Image tag | `build.nu#L52` |
| `author` | string | - | Image author, used for configuration and push authentication (paired with `password` for `--creds`) | `build.nu#L21`, `build.nu#L59` |
| `password` | string | - | Password used with `author` for `--creds` authentication when pushing | `build.nu#L59` |
| `skip_push` | bool | `false` | Whether to skip image push | `build.nu#L59` |

### Context Usage Example

```nu
{
    from: 'ghcr.io/orbsh/xy:py'        # Required: base image
    image: 'test-skill'               # Required: image name
    tag: 'latest'                     # Optional: tag, defaults to latest
    author: 'master'                  # Optional: author
    password: 'master'                # Optional: password (required for push)
    skip_push: true                   # Optional: skip push
}
| build {|ctx|
    # Build logic
    conf cmd ["python3", "libs/cli.py", "serve"]
    conf workdir /app
}
```

### Important Notes

1. **Minimum Required Fields**: Only `from` and `image` are strictly required to complete a basic build.

2. **Push-Related Fields**: If you need to push the image (`skip_push` is false or not set), then `author` and `password` are effectively required for authentication.

3. **Default Behaviors**:
   - `tag`: defaults to `latest` if not specified
   - `skip_push`: defaults to `false` (will attempt to push)

4. **Project-Specific Fields**: Additional fields like `ci` may be used by specific projects built on top of bx, but are not part of the core bx framework.

5. **Environment Variables**: During build, the following environment variables are available:
   - `BX_WORKDIR`: Working directory (defaults to `$env.PWD`)
   - `BX_DATADIR`: Data directory
   - `BUILDAH_WORKING_CONTAINER`: Working container name
   - `BUILDAH_WORKING_MOUNTPOINT`: Mount point path
   - `OS_RELEASE_ID`: OS identifier from the container
   - `SSH_WORKING_HOST`: Working host for SSH (reserved for future use)

6. **hub.install Command**: The `hub install` command supports the following options:
   - `--target(-t)`: Installation target directory (default: `/usr/local`)
   - `--cache(-c)`: Cache directory for downloaded packages
   - `--bundle`: Bundle mode - creates compressed archives (`.tar.zst`) instead of installing, useful for providing download/installation services (e.g., CGI-based installation services as demonstrated in `images/service/ferron/vessel.nu`)
   - `--arch`: Target architecture (default: system architecture)
   - `--with-python`: Include Python version detection
   - `--option(-o)`: Custom options closure for package configuration

7. **Build Function Parameters**: The `build` function supports the following optional parameters:
   - `--expose`: Debug mode - injects environment variables and returns without committing
   - `--no-commit`: Skip the commit step
   - `--squash`: Use squash mode when committing
   - `--workdir(-w)`: Specify working directory
   - `--datadir(-d)`: Specify data directory

## Module Exports

The `bx` module exports the following submodules:

- `build.nu` - Core build functionality
- `b.nu` - Helper commands (`copy`, `exec` (with `--with-nu` flag), `commit`, `with-mount`) and `conf` submodule (`env`, `expose`, `volume`, `workdir`, `entrypoint`, `cmd`, `user`)
- `trace.nu` - Logging and tracing utilities
- `pkg.nu` - Package management
- `rust.nu` - Rust toolchain setup
- `nushell.nu` - Nushell installation and configuration
- `setup.nu` - General setup utilities
- `hub.nu` - Package installation and management (`get-version`, `install`, `sync`, `run-script`, `gen-script`)
- `transformer.nu` - Data transformation utilities
- `extract.nu` - Extraction utilities
- `ghcr.nu` - GitHub Container Registry operations
- `reverse.nu` - Reverse proxy utilities
- `upterm.nu` - Uterm terminal utilities
- `utils.nu` - Utility functions (`relative-path`, `into-tree`)

## Best Practices

### `hub.yaml` unpack Actions

The `unpack` field in `hub.yaml` defines a pipeline of transformations applied after extracting a downloaded archive. Each item is a string parsed into an action name and arguments (see `bx/extract.nu`).

**Supported actions:**

| Action | Arguments | Description |
|--------|-----------|-------------|
| `strip` | `<N>` (default: 1) | Strip N leading directory components (like `tar --strip-components`) |
| `filter` | `<glob>...` | Keep only matching files/directories, copy to a temp dir |
| `wrap` | `<dir>` (default: `bin`) | Move all contents into a subdirectory |
| `mv` | `<source> <target>` | Rename/move a single file or directory |
| `chmodx` | `<file>...` | Add executable permission to listed files |

**Key rules:**

* **`rename` is not a valid action** — use `mv` instead.
* **`mv` does NOT support glob patterns** — it moves exactly one source to one target. If the source name contains version or architecture placeholders, use variable interpolation (`{version}`, `{arch}`) which `hub.yaml` resolves at runtime.

```yaml
# Good: explicit filename with variable interpolation
unpack:
  - mv warpgate-{version}-{arch}-linux warpgate
  - wrap bin

# Bad: glob patterns don't work with mv
unpack:
  - mv 'warpgate*' warpgate   # ❌ mv doesn't support globs

# Bad: rename is not a recognized action
unpack:
  - rename warpgate-{version}-{arch}-linux warpgate   # ❌ action not found
```

This design follows the **explicit over implicit** principle: the manifest declares exactly which file is being moved, eliminating ambiguity when archive contents change.

### `with-mount` Execution Context
`with-mount` is executed **on the host machine**, but the path context is the **container's filesystem** (mounted via buildah).

This is a major paradigm shift from Dockerfiles:
*   **Dockerfile**: `RUN` commands execute *inside* the build container layer.
*   **bx**: You have full access to the mounted container directory from the host. You can use the host's powerful tools (like Nushell) to generate, modify, and organize files directly into the image layers without running a shell inside the build context.

**Critical: Build-time vs Runtime paths**

```nushell
# with-mount blocks (build-time): use RELATIVE paths
# The block runs on the host, targeting the container's mounted filesystem.
# A leading '/' would resolve to the HOST's root directory — permission denied.
with-mount {
    mkdir data/ssh-keys          # ✓ relative → container's /data/ssh-keys
    mkdir data/recordings        # ✓
    mkdir data/db                # ✓

    # mkdir /data/ssh-keys       # ✗ absolute → host's /data/ssh-keys (EPERM)
}

# Entrypoint script content (runtime): use ABSOLUTE paths
# The script runs inside the container at startup, so paths resolve to the container root.
r#'^warpgate --config /data/warpgate.yaml run'#   # ✓ runtime context
```

```nushell
# Generates a config on the host, but saves it into the container's /etc/
with-mount {
    r#':8080 { root "/srv" }'#
    | save etc/ferron.conf
}
```
