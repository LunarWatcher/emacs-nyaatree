# Changelog
## [v1.0.0]

### Changed

* The `neo` prefix is now `nyaatree`
* The `neotree` prefix is now `nyatree`

### Fixed

* `nyaatree-rename` will no longer fail in version-controlled folders when the buffer being renamed is opened.
* `fboundp` all the things so the compiler shuts up

### Removed

* Removed support for popwin. The plugin [only exists in the emacs orphanage](https://github.com/emacsorphanage/popwin), a registry for dead plugins kept on life support because they're still technically in use.
* Removed the toggle for `linum-mode` in the nyaatree buffer. Steamrolling user preference is bad, and linum-mode has been nuked in later versions of emacs.

## v0.6.0

The last upstream release at fork time. https://github.com/jaypei/emacs-neotree/releases/tag/0.6.0

<!-- TODO on release -->
<!-- [v1.0.0]: -->
