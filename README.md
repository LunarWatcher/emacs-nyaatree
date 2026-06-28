# emacs-nyaatree

A Emacs tree plugin like NerdTree for Vim. A fork of the seemingly unmaintained [emacs-neotree](https://github.com/jaypei/emacs-neotree)

## Fork notes

emacs-nyaatree is considered feature-complete at this time. The upstream version is _fine_, but this fork was spawned due to a bug where files _refuse_ to be renamed if I have a buffer of that file open, but only under certain circumstances. This pissed me off to the point where I figured maintaining an old elisp plugin was a good idea.

### Fork changes

Note that this section does not replace the changelog. This is meant as a summary for migration purposes, and only highlights changes that are incompatible with upstream.

* All `neo-`/`neotree-`-prefixes can be replaced with `nyaatree` (meow)
  * `neotree` -> `nyaatree`, including in all commands.
  * `neo` -> `nyaatree`, including in all variables.
  * **This affects themes**. I do not currently know how to alias `nyaatree-*-face` to `neo-*-face` by default

## Screenshots

TODO (but nothing major about the style has changed relative to upstream)

## Installation

```elisp
(use-package nyaatree
  :vc (:url "https://codeberg.org/LunarWatcher/emacs-nyaatree.git"
            :rev :newest)
  :ensure t
)
```

## Keybindings

Only in Neotree Buffer:

* `n` next line, `p` previous line。
* `SPC` or `RET` or `TAB` Open current item if it is a file. Fold/Unfold current item if it is a directory.
* `U` Go up a directory
* `g` Refresh
* `A` Maximize/Minimize the NeoTree Window
* `H` Toggle display hidden files
* `O` Recursively open a directory
* `C-c C-n` Create a file or create a directory if filename ends with a ‘/’
* `C-c C-d` Delete a file or a directory.
* `C-c C-r` Rename a file or a directory.
* `C-c C-c` Change the root directory.
* `C-c C-p` Copy a file or a directory.


## Configurations

### Theme config
NeoTree provides following themes: 
- *classic* (default)
- *ascii*
- *arrow*
- *icons*[^1]
- *nerd-icons*[^2]
- *nerd*

Theme can be configed by setting **nyaatree-theme**. For example, use *icons* for window
system and *arrow* terminal.

```elisp
(setq nyaatree-theme (if (display-graphic-p) 'icons 'arrow))
```


* all-the-icons theme screenshots

![](screenshots/icons.png "neotree icons theme")

## More documentation

[^1]: For users who want to use the `icons` theme. Please make sure you have installed the
[all-the-icons](https://github.com/domtronn/all-the-icons.el) package and its
[fonts](https://github.com/domtronn/all-the-icons.el/tree/master/fonts).

[^2]: For users who want to use the `nerd-icons` theme. Please make sure you have installed the
[nerd-icons](https://github.com/rainstormstudio/nerd-icons.el?tab=readme-ov-file) package and
one of its [fonts](https://www.nerdfonts.com/).
