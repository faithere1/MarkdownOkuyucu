<div align="center">

# Markdown Okuyucu

**A tiny, native Markdown reader & editor for macOS.**

Single Swift file · No dependencies to install · Under 1 MB

</div>

---

## Features

- **Three view modes**: Read, Split (edit + live preview), and Edit-only
- **GitHub-style rendering**, with tables, task lists, and syntax-highlighted code blocks
- **Light & dark mode** that follow your system appearance
- **Native macOS document app**: tabs, autosave, undo, find, and full screen
- **Linked `.md` files open in the app**, so you can browse docs like a wiki
- **Relative images** load from the document's folder
- **Safe by default**: rendered HTML is sanitized with DOMPurify, and clicked links never run local files

## Install

Requires macOS 12+ and the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/faithere1/MarkdownOkuyucu.git
cd MarkdownOkuyucu
./build.sh
```

The app is built and installed to `~/Applications/Markdown Okuyucu.app`.
To make it your default, right-click any `.md` file → **Get Info** → **Open with** → *Markdown Okuyucu* → **Change All…**

## Shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘1` / `⌘2` / `⌘3` | Read / Split / Edit mode |
| `⌘E` | Toggle Read ↔ Edit |
| `⌘+` / `⌘-` / `⌘0` | Zoom in / out / reset |
| `⌘F` | Find |
| `⌘⇧R` | Reveal in Finder |

## Built with

[marked](https://github.com/markedjs/marked) · [DOMPurify](https://github.com/cure53/DOMPurify) · [highlight.js](https://highlightjs.org) · [github-markdown-css](https://github.com/sindresorhus/github-markdown-css)

## License

[MIT](LICENSE)
