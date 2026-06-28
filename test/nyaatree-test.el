;;; nyaatree-test.el --- test utilities

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

(defmacro nyaatree-test--with-temp-dir (&rest body)
  (declare (indent 0) (debug t))
  `(let* ((temp-cwd (file-name-as-directory (make-temp-file "dir" t)))
          (temp-pd (nyaatree-path--join temp-cwd "nyaatree-test" "./")))
     (mkdir temp-pd)
     (unwind-protect
         (let ((default-directory temp-cwd)) ,@body)
       (delete-directory temp-cwd t))))

(defun nyaatree-test--with-temp-dir-open ()
  (nyaatree-test--with-temp-dir
    (write-region "" nil "file-1")
    (write-region "hello" nil "file-2")
    (nyaatree-dir temp-cwd)))

(defmacro nyaatree-test--try-open (name &rest body)
  (declare (indent 0) (debug t))
  `(ert-deftest ,name ()
     ,@body
     (nyaatree-test--with-temp-dir-open)))

(provide 'nyaatree-test)
;;; nyaatree-test.el ends here
