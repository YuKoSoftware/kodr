# Kodr for VS Code

Language support for [Kodr](https://github.com/YuKoSoftware/kodr) — a compiled, memory-safe programming language that transpiles to Zig.

## Features

- Syntax highlighting for `.kodr` files
- Real-time diagnostics via the built-in language server
- Error and warning squiggles as you code

## Requirements

Install the `kodr` compiler and ensure it's on your `PATH`:

```bash
kodr addtopath
```

## Usage

Open any `.kodr` file. The extension automatically starts the language server and shows diagnostics on save.

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `kodr.lsp.enabled` | `true` | Enable the language server |
| `kodr.lsp.path` | `"kodr"` | Path to the kodr binary |
