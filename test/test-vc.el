;;; test-vc.el --- test cases

;; Copyright (C) 2014 jaypei
;; Copyright (C) 2026 Olivia

;; Maintainer: Olivia <oliviawolfie@pm.me>
;; URL: https://codeberg.org/LunarWatcher/emacs-nyaatree

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;; Code:

(require 'nyaatree)
(require 'nyaatree-test)

(nyaatree-test--try-open
 nyaatree-test-vc-mode-with-face
 (shell-command-to-string "git init")
 (setq nyaatree-vc-integration '(face)))

(nyaatree-test--try-open
 nyaatree-test-vc-mode-with-char
 (shell-command-to-string "git init")
 (setq nyaatree-vc-integration '(char)))

(nyaatree-test--try-open
 nyaatree-test-vc-mode-with-char-face
 (shell-command-to-string "git init")
 (setq nyaatree-vc-integration '(char face)))


;;; test-vc.el ends here
