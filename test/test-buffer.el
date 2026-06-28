;;; test-buffer.el --- summary

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

(ert-deftest nyaatree-test-save-current-pos ()
  (nyaatree)
  (nyaatree-global--select-window)
  (beginning-of-line)
  (condition-case err
      (while t
        (next-line)
        (nyaatree-buffer--save-cursor-pos)
        (let ((current-file-path (nyaatree-buffer--get-filename-current-line))
              (current-line-number (line-number-at-pos)))
          (should (eq (car nyaatree-buffer--cursor-pos) current-file-path))
          (should (eq (cdr nyaatree-buffer--cursor-pos) current-line-number))))
    (error
     (should (equal err '(end-of-buffer)))))
  (nyaatree-buffer--save-cursor-pos "/tmp/nbs" 192)
  (should (equal nyaatree-buffer--cursor-pos (cons "/tmp/nbs" 192))))

(ert-deftest nyaatree-test-set-node-list ()
  (nyaatree)
  (nyaatree-global--select-window)
  (nyaatree-buffer--node-list-clear)
  (should (equal nyaatree-buffer--node-list nil))
  (nyaatree-buffer--node-list-set 10 "foo")
  (should (equal nyaatree-buffer--node-list
                 [nil nil nil nil nil nil nil nil nil "foo"]))
  (nyaatree-buffer--node-list-set 3 "bar")
  (nyaatree-buffer--node-list-set 15 "foobar")
  (should (equal nyaatree-buffer--node-list
                 [nil nil "bar" nil nil
                      nil nil nil nil "foo"
                      nil nil nil nil "foobar"]))
  (nyaatree-buffer--node-list-clear)
  (should (equal nyaatree-buffer--node-list nil)))

(ert-deftest nyaatree-test-set-node-list-current-line-number ()
  (nyaatree)
  (nyaatree-global--select-window)
  (end-of-line)
  (let ((n (line-number-at-pos)))
    (nyaatree-buffer--node-list-set nil "DUMMY")
    (beginning-of-line)
    (should (string= (elt nyaatree-buffer--node-list (1- n)) "DUMMY"))))


(provide 'test-buffer)
;;; test-buffer.el ends here
