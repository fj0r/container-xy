# Ferron: Lightweight Upload Gateway

> `box.conf` and `php.conf` are configuration files prepared for **ferron3**.

## Overview
Ferron includes a minimal, high-performance upload gateway component. It leverages Nushell's native capabilities and the local filesystem to trigger automated post-upload hooks with zero external dependencies (no Redis, no message queues).

## Core Feature: Path-Based Hooks (`box.nu`)
When a file is uploaded, the gateway dynamically resolves and executes a corresponding Nushell hook script based on the request path.

### How it works
1. **Dynamic Resolution**: Combines `DOCUMENT_ROOT`, the `box` directory, and `HOOKS_PATH` with the virtual request path to locate the hook.
2. **Sandbox Isolation**: Each hook runs in a fresh `mktemp -d` workspace to prevent cross-request pollution or deadlocks.
3. **Stream Execution**: The hook receives upload metadata as JSON via stdin and streams real-time progress output back to the client.
4. **Auto-Cleanup**: Temporary workspaces and generated scripts are instantly deleted after execution.

### Hook Contract
Hooks are standard Nushell scripts. The gateway wraps them in a `main` function that accepts structured JSON metadata:
```json
{
  "filename": "task.zip",
  "location": "/path/to/uploaded/file"
}
```

### Example Hook: Streaming Unpack (`run.nu`)
The gateway receives the raw binary stream via `$in`. Instead of saving a temporary archive, it pipes the network stream directly to the extractor for zero-latency unpacking:

```nushell
def uploaded [o] {
    # $in is the raw network byte stream
    let dest = $o.location | path parse | get stem

    # Stream directly from network -> decompress -> extract
    # No intermediate tar.zst file written to disk
    $in | zstd -d -c | tar -xf - -C $dest

    print $"==> Extracted ($dest) from stream."
}
```

## Streaming Architecture (`tar + zstd`)
**Zip is an Anti-pattern:** Zip requires full download and seeking the Central Directory, forcing a temporary file.
**The Solution:** `tar -cvf - src/ | zstd -T0 | curl -T -`

### Why it's superior
- **Zero Disk IO (Client)**: No temporary zip file created on the uploader side.
- **Streaming Unpack (Server)**: The CGI script receives `$in` as a byte stream and pipes it directly: `$in | zstd -d -c | tar -xf -`. Decompression happens while the network transfer is still ongoing.
- **Pipeline All The Way**: Maximum throughput bounded only by CPU and Network.
