# HGSS Save Editor

## Motivation
This idea came to me after watching a liveoverflow's video about saves and pokemon RED, so please don't expect much from this beyond a hobby project to understand a bit more about RE.

## References:

[LiveOverflow Video](https://www.youtube.com/watch?v=VVbRe7wr3G4)

[PKHex](https://github.com/kwsch/PKHeX)
----

## Development

For now the raylib is a straight import without using zig fetch and zig zon, might change later, i did this to learn a bit more about the way the compilation with c works

Enter the development shell:

```bash
nix develop
zig build run
zig build -Dwindows run
```

Or can be also built using nix.
```bash
nix develop
nix build
nix run
```
