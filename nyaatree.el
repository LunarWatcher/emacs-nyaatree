;;; nyaatree.el --- A tree plugin like NerdTree for Vim

;; Copyright (C) 2014 jaypei
;; Copyright (C) 2026 Olivia

;; Maintainer: Olivia <oliviawolfie@pm.me>
;; URL: https://codeberg.org/LunarWatcher/emacs-nyaatree
;; Version: 1.0.0
;; Package-Requires: ((cl-lib "0.5"))

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

(require 'cl-lib)

;;
;; Constants
;;

(defconst nyaatree-buffer-name " *NyaaTree*"
  "Name of the buffer where nyaatree shows directory contents.")

(defconst nyaatree-dir
  (expand-file-name (if load-file-name
                        (file-name-directory load-file-name)
                      default-directory)))

(defconst nyaatree-header-height 5)

(eval-and-compile

  ;; Added in Emacs 24.3
  (unless (fboundp 'user-error)
    (defalias 'user-error 'error))

  ;; Added in Emacs 24.3 (mirrors/emacs@b335efc3).
  (unless (fboundp 'setq-local)
    (defmacro setq-local (var val)
      "Set variable VAR to value VAL in current buffer."
      (list 'set (list 'make-local-variable (list 'quote var)) val)))

  ;; Added in Emacs 24.3 (mirrors/emacs@b335efc3).
  (unless (fboundp 'defvar-local)
    (defmacro defvar-local (var val &optional docstring)
      "Define VAR as a buffer-local variable with default value VAL.
Like `defvar' but additionally marks the variable as being automatically
buffer-local wherever it is set."
      (declare (debug defvar) (doc-string 3))
      (list 'progn (list 'defvar var val docstring)
            (list 'make-variable-buffer-local (list 'quote var))))))

;; Add autoload function for vc (#153).
(autoload 'vc-responsible-backend "vc.elc")

;;
;; Macros
;;

(defmacro nyaatree-util--to-bool (obj)
  "If OBJ is non-nil, return t, else return nil."
  `(and ,obj t))

(defmacro nyaatree-global--with-buffer (&rest body)
  "Execute the forms in BODY with global NyaaTree buffer."
  (declare (indent 0) (debug t))
  `(let ((nyaatree-buffer (nyaatree-global--get-buffer)))
     (unless (null nyaatree-buffer)
       (with-current-buffer nyaatree-buffer
         ,@body))))

(defmacro nyaatree-global--with-window (&rest body)
  "Execute the forms in BODY with global NyaaTree window."
  (declare (indent 0) (debug t))
  `(save-selected-window
     (nyaatree-global--select-window)
     ,@body))

(defmacro nyaatree-global--when-window (&rest body)
  "Execute the forms in BODY when selected window is NyaaTree window."
  (declare (indent 0) (debug t))
  `(when (eq (selected-window) nyaatree-global--window)
     ,@body))

(defmacro nyaatree-global--switch-to-buffer ()
  "Switch to NyaaTree buffer."
  `(let ((nyaatree-buffer (nyaatree-global--get-buffer)))
     (unless (null nyaatree-buffer)
       (switch-to-buffer nyaatree-buffer))))

(defmacro nyaatree-buffer--with-editing-buffer (&rest body)
  "Execute BODY in nyaatree buffer without read-only restriction."
  `(let (rlt)
     (nyaatree-global--with-buffer
       (setq buffer-read-only nil)
       (setq rlt (progn ,@body))
       (setq buffer-read-only t))
     rlt))

(defmacro nyaatree-buffer--with-resizable-window (&rest body)
  "Execute BODY in nyaatree window without `window-size-fixed' restriction."
  `(let (rlt)
     (nyaatree-global--with-buffer
       (nyaatree-buffer--unlock-width))
     (setq rlt (progn ,@body))
     (nyaatree-global--with-buffer
       (nyaatree-buffer--lock-width))
     rlt))

(defmacro nyaatree-make-executor (&rest fn-form)
  "Make an open event handler, FN-FORM is event handler form."
  (let* ((get-args-fn
          (lambda (sym) (or (plist-get fn-form sym) (lambda (&rest _)))))
         (file-fn (funcall get-args-fn :file-fn))
         (dir-fn (funcall get-args-fn :dir-fn)))
    `(lambda (&optional arg)
       (interactive "P")
       (nyaatree-global--select-window)
       (nyaatree-buffer--execute arg ,file-fn ,dir-fn))))


;;
;; Customization
;;

(defgroup nyaatree nil
  "Options for nyaatree."
  :prefix "nyaatree-"
  :group 'files)

(defgroup nyaatree-vc-options nil
  "Nyaatree-VC customizations."
  :prefix "nyaatree-vc-"
  :group 'nyaatree
  :link '(info-link "(nyaatree)Configuration"))

(defgroup nyaatree-confirmations nil
  "Nyaatree confirmation customizations."
  :prefix "nyaatree-confirm-"
  :group 'nyaatree)

(defcustom nyaatree-window-position 'left
  "*The position of NyaaTree window."
  :group 'nyaatree
  :type '(choice (const left)
                 (const right)))

(defcustom nyaatree-display-action '(nyaatree-default-display-fn)
  "*Action to use for displaying NyaaTree window.
If you change the action so it doesn't use
`nyaatree-default-display-fn', then other variables such as
`nyaatree-window-position' won't be respected when opening NyaaTree
window."
  :type 'sexp
  :group 'nyaatree)

(defcustom nyaatree-create-file-auto-open nil
  "*If non-nil, the file will auto open when created."
  :type 'boolean
  :group 'nyaatree)

(defcustom nyaatree-banner-message nil
  "*The banner message of nyaatree window."
  :type 'string
  :group 'nyaatree)

(defcustom nyaatree-show-updir-line t
  "*If non-nil, show the updir line (..)."
  :type 'boolean
  :group 'nyaatree)

(defcustom nyaatree-show-slash-for-folder t
  "*If non-nil, show the slash at the end of folder (folder/)"
  :type 'boolean
  :group 'nyaatree)

(defcustom nyaatree-reset-size-on-open nil
  "*If non-nil, the width of the noetree window will be reseted every time a file is open."
  :type 'boolean
  :group 'nyaatree)

(defcustom nyaatree-theme 'classic
  "*The tree style to display.
`classic' use icon to display, it only it suitable for GUI mode.
`ascii' is the simplest style, it will use +/- to display the fold state,
it suitable for terminal.
`arrow' use unicode arrow.
`nerd' use the nerdtree indentation mode and arrow.
`icons' use icons from `all-the-icons' when installed.
`nerd-icons' use icons from `nerd-icons' when installed."
  :group 'nyaatree
  :type '(choice (const classic)
                 (const ascii)
                 (const arrow)
                 (const icons)
                 (const nerd-icons)
                 (const nerd)))

(defcustom nyaatree-mode-line-type 'nyaatree
  "*The mode-line type to display, `default' is a non-modified mode-line, \
`nyaatree' is a compact mode-line that shows useful information about the
 current node like the parent directory and the number of nodes,
`custom' uses the format stored in `nyaatree-mode-line-custom-format',
`none' hide the mode-line."
  :group 'nyaatree
  :type '(choice (const default)
                 (const nyaatree)
                 (const custom)
                 (const none)))

(defcustom nyaatree-mode-line-custom-format nil
  "*If `nyaatree-mode-line-type' is set to `custom', this variable specifiy \
the mode-line format."
  :type 'sexp
  :group 'nyaatree)

(defcustom nyaatree-smart-open nil
  "*If non-nil, every time when the nyaatree window is opened, it will try to find current file and jump to node."
  :type 'boolean
  :group 'nyaatree)

(defcustom nyaatree-show-hidden-files nil
  "*If non-nil, the hidden files are shown by default."
  :type 'boolean
  :group 'nyaatree)

(defcustom nyaatree-autorefresh nil
  "*If non-nil, the nyaatree buffer will auto refresh."
  :type 'boolean
  :group 'nyaatree)

(defcustom nyaatree-window-width 25
  "*Specifies the width of the NyaaTree window."
  :type 'integer
  :group 'nyaatree)

(defcustom nyaatree-window-fixed-size t
  "*If the nyaatree windows is fixed, it won't be resize when rebalance windows."
  :type 'boolean
  :group 'nyaatree)

(defcustom nyaatree-keymap-style 'default
  "*The default keybindings for nyaatree-mode-map."
  :group 'nyaatree
  :type '(choice (const default)
                 (const concise)))

(defcustom nyaatree-cwd-line-style 'text
  "*The default header style."
  :group 'nyaatree
  :type '(choice (const text)
                 (const button)))

(defcustom nyaatree-help-echo-style 'default
  "The message NyaaTree displays when the mouse moves onto nodes.
`default' means the node name is displayed if it has a
width (including the indent) larger than `nyaatree-window-width', and
`none' means NyaaTree doesn't display any messages."
  :group 'nyaatree
  :type '(choice (const default)
                 (const none)))

(defcustom nyaatree-click-changes-root nil
  "*If non-nil, clicking on a directory will change the current root to the directory."
  :type 'boolean
  :group 'nyaatree)

(defcustom nyaatree-auto-indent-point nil
  "*If non-nil the point is autmotically put on the first letter of a node."
  :type 'boolean
  :group 'nyaatree)

(defcustom nyaatree-hidden-regexp-list
  '("^\\." "\\.pyc$" "~$" "^#.*#$" "\\.elc$" "\\.o$")
  "*The regexp list matching hidden files."
  :type  '(repeat (choice regexp))
  :group 'nyaatree)

(defcustom nyaatree-enter-hook nil
  "Functions to run if enter node occured."
  :type 'hook
  :group 'nyaatree)

(defcustom nyaatree-after-create-hook nil
  "Hooks called after creating the nyaatree buffer."
  :type 'hook
  :group 'nyaatree)

(defcustom nyaatree-vc-integration nil
  "If non-nil, show VC status."
  :group 'nyaatree-vc
  :type '(set (const :tag "Use different faces" face)
              (const :tag "Use different characters" char)))

(defcustom nyaatree-vc-state-char-alist
  '((up-to-date       . ?\s)
    (edited           . ?E)
    (added            . ?+)
    (removed          . ?-)
    (missing          . ?!)
    (needs-merge      . ?M)
    (conflict         . ?!)
    (unlocked-changes . ?!)
    (needs-update     . ?U)
    (ignored          . ?\s)
    (user             . ?U)
    (unregistered     . ?\s)
    (nil              . ?\s))
  "Alist of vc-states to indicator characters.
This variable is used in `nyaatree-vc-for-node' when
`nyaatree-vc-integration' contains `char'."
  :group 'nyaatree-vc
  :type '(alist :key-type symbol
                :value-type character))

(defcustom nyaatree-confirm-change-root 'yes-or-no-p
  "Confirmation asking for permission to change root if file was not found in root path."
  :type '(choice (function-item :tag "Verbose" yes-or-no-p)
                 (function-item :tag "Succinct" y-or-n-p)
                 (function-item :tag "Off" off-p))
  :group 'nyaatree-confirmations)

(defcustom nyaatree-confirm-create-file 'yes-or-no-p
  "Confirmation asking whether *NyaaTree* should create a file."
  :type '(choice (function-item :tag "Verbose" yes-or-no-p)
                 (function-item :tag "Succinct" y-or-n-p)
                 (function-item :tag "Off" off-p))
  :group 'nyaatree-confirmations)

(defcustom nyaatree-confirm-create-directory 'yes-or-no-p
  "Confirmation asking whether *NyaaTree* should create a directory."
  :type '(choice (function-item :tag "Verbose" yes-or-no-p)
                 (function-item :tag "Succinct" y-or-n-p)
                 (function-item :tag "Off" off-p))
  :group 'nyaatree-confirmations)

(defcustom nyaatree-confirm-delete-file 'yes-or-no-p
  "Confirmation asking whether *NyaaTree* should delete the file."
  :type '(choice (function-item :tag "Verbose" yes-or-no-p)
                 (function-item :tag "Succinct" y-or-n-p)
                 (function-item :tag "Off" off-p))
  :group 'nyaatree-confirmations)

(defcustom nyaatree-confirm-delete-directory-recursively 'yes-or-no-p
  "Confirmation asking whether the directory should be deleted recursively."
  :type '(choice (function-item :tag "Verbose" yes-or-no-p)
                 (function-item :tag "Succinct" y-or-n-p)
                 (function-item :tag "Off" off-p))
  :group 'nyaatree-confirmations)

(defcustom nyaatree-confirm-kill-buffers-for-files-in-directory 'yes-or-no-p
  "Confirmation asking whether *NyaaTree* should kill buffers for the directory in question."
  :type '(choice (function-item :tag "Verbose" yes-or-no-p)
                 (function-item :tag "Succinct" y-or-n-p)
                 (function-item :tag "Off" off-p))
  :group 'nyaatree-confirmations)

(defcustom nyaatree-toggle-window-keep-p nil
  "If not nil, not switch to *NyaaTree* buffer when executing `nyaatree-toggle'."
  :type 'boolean
  :group 'nyaatree)

(defcustom nyaatree-force-change-root t
  "If not nil, do not prompt when switching root."
  :type 'boolean
  :group 'nyaatree)

(defcustom nyaatree-filepath-sort-function 'string<
  "Function to be called when sorting nyaatree nodes."
  :type '(symbol (const :tag "Normal" string<)
                 (const :tag "Sort Hidden at Bottom" nyaatree-sort-hidden-last)
                 (function :tag "Other"))
  :group 'nyaatree)

(defcustom nyaatree-default-system-application "xdg-open"
  "*Name of the application that is used to open a file under point.
By default it is xdg-open."
  :type 'string
  :group 'nyaatree)

(defcustom nyaatree-hide-cursor nil
  "If not nil, hide cursor in NyaaTree buffer and turn on line higlight."
  :type 'boolean
  :group 'nyaatree)

;;
;; Faces
;;

(defface nyaatree-banner-face
  '((((background dark)) (:foreground "lightblue" :weight bold))
    (t                   (:foreground "DarkMagenta")))
  "*Face used for the banner in nyaatree buffer."
  :group 'nyaatree :group 'font-lock-highlighting-faces)
(defvar nyaatree-banner-face 'nyaatree-banner-face)

(defface nyaatree-header-face
  '((((background dark)) (:foreground "White"))
    (t                   (:foreground "DarkMagenta")))
  "*Face used for the header in nyaatree buffer."
  :group 'nyaatree :group 'font-lock-highlighting-faces)
(defvar nyaatree-header-face 'nyaatree-header-face)

(defface nyaatree-root-dir-face
  '((((background dark)) (:foreground "lightblue" :weight bold))
    (t                   (:foreground "DarkMagenta")))
  "*Face used for the root dir in nyaatree buffer."
  :group 'nyaatree :group 'font-lock-highlighting-faces)
(defvar nyaatree-root-dir-face 'nyaatree-root-dir-face)

(defface nyaatree-dir-link-face
  '((((background dark)) (:foreground "DeepSkyBlue"))
    (t                   (:foreground "MediumBlue")))
  "*Face used for expand sign [+] in nyaatree buffer."
  :group 'nyaatree :group 'font-lock-highlighting-faces)
(defvar nyaatree-dir-link-face 'nyaatree-dir-link-face)

(defface nyaatree-file-link-face
  '((((background dark)) (:foreground "White"))
    (t                   (:foreground "Black")))
  "*Face used for open file/dir in nyaatree buffer."
  :group 'nyaatree :group 'font-lock-highlighting-faces)
(defvar nyaatree-file-link-face 'nyaatree-file-link-face)

(defface nyaatree-button-face
  '((t (:underline nil)))
  "*Face used for open file/dir in nyaatree buffer."
  :group 'nyaatree :group 'font-lock-highlighting-faces)
(defvar nyaatree-button-face 'nyaatree-button-face)

(defface nyaatree-expand-btn-face
  '((((background dark)) (:foreground "SkyBlue"))
    (t                   (:foreground "DarkCyan")))
  "*Face used for open file/dir in nyaatree buffer."
  :group 'nyaatree :group 'font-lock-highlighting-faces)
(defvar nyaatree-expand-btn-face 'nyaatree-expand-btn-face)

(defface nyaatree-vc-default-face
  '((((background dark)) (:foreground "White"))
    (t                   (:foreground "Black")))
  "*Face used for unknown files in the nyaatree buffer.
Used only when \(vc-state node\) returns nil."
  :group 'nyaatree-vc :group 'font-lock-highlighting-faces)
(defvar  nyaatree-vc-default-face 'nyaatree-vc-default-face)

(defface nyaatree-vc-user-face
  '((t                   (:foreground "Red" :slant italic)))
  "*Face used for user-locked files in the nyaatree buffer."
  :group 'nyaatree-vc :group 'font-lock-highlighting-faces)
(defvar  nyaatree-vc-user-face 'nyaatree-vc-user-face)

(defface nyaatree-vc-up-to-date-face
  '((((background dark)) (:foreground "LightGray"))
    (t                   (:foreground "DarkGray")))
  "*Face used for vc-up-to-date files in the nyaatree buffer."
  :group 'nyaatree-vc :group 'font-lock-highlighting-faces)
(defvar  nyaatree-vc-up-to-date-face 'nyaatree-vc-up-to-date-face)

(defface nyaatree-vc-edited-face
  '((((background dark)) (:foreground "Magenta"))
    (t                   (:foreground "DarkMagenta")))
  "*Face used for vc-edited files in the nyaatree buffer."
  :group 'nyaatree-vc :group 'font-lock-highlighting-faces)
(defvar  nyaatree-vc-edited-face 'nyaatree-vc-edited-face)

(defface nyaatree-vc-needs-update-face
  '((t                   (:underline t)))
  "*Face used for vc-needs-update files in the nyaatree buffer."
  :group 'nyaatree-vc :group 'font-lock-highlighting-faces)
(defvar  nyaatree-vc-needs-update-face 'nyaatree-vc-needs-update-face)

(defface nyaatree-vc-needs-merge-face
  '((((background dark)) (:foreground "Red1"))
    (t                   (:foreground "Red3")))
  "*Face used for vc-needs-merge files in the nyaatree buffer."
  :group 'nyaatree-vc :group 'font-lock-highlighting-faces)
(defvar  nyaatree-vc-needs-merge-face 'nyaatree-vc-needs-merge-face)

(defface nyaatree-vc-unlocked-changes-face
  '((t                   (:foreground "Red" :background "Blue")))
  "*Face used for vc-unlocked-changes files in the nyaatree buffer."
  :group 'nyaatree-vc :group 'font-lock-highlighting-faces)
(defvar  nyaatree-vc-unlocked-changes-face 'nyaatree-vc-unlocked-changes-face)

(defface nyaatree-vc-added-face
  '((((background dark)) (:foreground "LightGreen"))
    (t                   (:foreground "DarkGreen")))
  "*Face used for vc-added files in the nyaatree buffer."
  :group 'nyaatree-vc :group 'font-lock-highlighting-faces)
(defvar  nyaatree-vc-added-face 'nyaatree-vc-added-face)

(defface nyaatree-vc-removed-face
  '((t                    (:strike-through t)))
  "*Face used for vc-removed files in the nyaatree buffer."
  :group 'nyaatree-vc :group 'font-lock-highlighting-faces)
(defvar  nyaatree-vc-removed-face 'nyaatree-vc-removed-face)

(defface nyaatree-vc-conflict-face
  '((((background dark)) (:foreground "Red1"))
    (t                   (:foreground "Red3")))
  "*Face used for vc-conflict files in the nyaatree buffer."
  :group 'nyaatree-vc :group 'font-lock-highlighting-faces)
(defvar  nyaatree-vc-conflict-face 'nyaatree-vc-conflict-face)

(defface nyaatree-vc-missing-face
  '((((background dark)) (:foreground "Red1"))
    (t                   (:foreground "Red3")))
  "*Face used for vc-missing files in the nyaatree buffer."
  :group 'nyaatree-vc :group 'font-lock-highlighting-faces)
(defvar  nyaatree-vc-missing-face 'nyaatree-vc-missing-face)

(defface nyaatree-vc-ignored-face
  '((((background dark)) (:foreground "DarkGrey"))
    (t                   (:foreground "LightGray")))
  "*Face used for vc-ignored files in the nyaatree buffer."
  :group 'nyaatree-vc :group 'font-lock-highlighting-faces)
(defvar  nyaatree-vc-ignored-face 'nyaatree-vc-ignored-face)

(defface nyaatree-vc-unregistered-face
  nil
  "*Face used for vc-unregistered files in the nyaatree buffer."
  :group 'nyaatree-vc :group 'font-lock-highlighting-faces)
(defvar  nyaatree-vc-unregistered-face 'nyaatree-vc-unregistered-face)

;;
;; Variables
;;

(defvar nyaatree-global--buffer nil)

(defvar nyaatree-global--window nil)

(defvar nyaatree-global--autorefresh-timer nil)

(defvar nyaatree-mode-line-format
  (list
   '(:eval
     (let* ((fname (nyaatree-buffer--get-filename-current-line))
            (current (if fname fname nyaatree-buffer--start-node))
            (parent (if fname (file-name-directory current) current))
            (nodes (nyaatree-buffer--get-nodes parent))
            (dirs (car nodes))
            (files (cdr nodes))
            (ndirs (length dirs))
            (nfiles (length files))
            (index
             (when fname
               (1+ (if (file-directory-p current)
                       (nyaatree-buffer--get-node-index current dirs)
                     (+ ndirs (nyaatree-buffer--get-node-index current files)))))))
       (nyaatree-mode-line--compute-format parent index ndirs nfiles))))
  "Nyaatree mode-line displaying information on the current node.
This mode-line format is used if `nyaatree-mode-line-type' is set to `nyaatree'")

(defvar-local nyaatree-buffer--start-node nil
  "Start node(i.e. directory) for the window.")

(defvar-local nyaatree-buffer--start-line nil
  "Index of the start line of the root.")

(defvar-local nyaatree-buffer--cursor-pos (cons nil 1)
  "To save the cursor position.
The car of the pair will store fullpath, and cdr will store line number.")

(defvar-local nyaatree-buffer--last-window-pos (cons nil 1)
  "To save the scroll position for NyaaTree window.")

(defvar-local nyaatree-buffer--show-hidden-file-p nil
  "Show hidden nodes in tree.")

(defvar-local nyaatree-buffer--expanded-node-list nil
  "A list of expanded dir nodes.")

(defvar-local nyaatree-buffer--node-list nil
  "The model of current NyaaTree buffer.")

(defvar-local nyaatree-buffer--node-list-1 nil
  "The model of current NyaaTree buffer (temp).")

;;
;; Major mode definitions
;;

(defvar nyaatree-file-button-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-2]
      (nyaatree-make-executor
       :file-fn 'nyaatree-open-file))
    map)
  "Keymap for file-node button.")

(defvar nyaatree-dir-button-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-2]
      (nyaatree-make-executor :dir-fn  'nyaatree-open-dir))
    map)
  "Keymap for dir-node button.")

(defvar nyaatree-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "TAB")     (nyaatree-make-executor
                                     :dir-fn  'nyaatree-open-dir))
    (define-key map (kbd "RET")     (nyaatree-make-executor
                                     :file-fn 'nyaatree-open-file
                                     :dir-fn  'nyaatree-open-dir))
    (define-key map (kbd "|")       (nyaatree-make-executor
                                     :file-fn 'nyaatree-open-file-vertical-split))
    (define-key map (kbd "-")       (nyaatree-make-executor
                                     :file-fn 'nyaatree-open-file-horizontal-split))
    (define-key map (kbd "a")       (nyaatree-make-executor
                                     :file-fn 'nyaatree-open-file-ace-window))
    (define-key map (kbd "d")       (nyaatree-make-executor
                                     :dir-fn 'nyaatree-open-dired))
    (define-key map (kbd "O")       (nyaatree-make-executor
                                     :dir-fn  'nyaatree-open-dir-recursive))
    (define-key map (kbd "SPC")     'nyaatree-quick-look)
    (define-key map (kbd "g")       'nyaatree-refresh)
    (define-key map (kbd "q")       'nyaatree-hide)
    (define-key map (kbd "p")       'nyaatree-previous-line)
    (define-key map (kbd "C-p")     'nyaatree-previous-line)
    (define-key map (kbd "n")       'nyaatree-next-line)
    (define-key map (kbd "C-n")     'nyaatree-next-line)
    (define-key map (kbd "A")       'nyaatree-stretch-toggle)
    (define-key map (kbd "U")       'nyaatree-select-up-node)
    (define-key map (kbd "D")       'nyaatree-select-down-node)
    (define-key map (kbd "H")       'nyaatree-hidden-file-toggle)
    (define-key map (kbd "S")       'nyaatree-select-previous-sibling-node)
    (define-key map (kbd "s")       'nyaatree-select-next-sibling-node)
    (define-key map (kbd "o")       'nyaatree-open-file-in-system-application)
    (define-key map (kbd "C-x C-f") 'find-file-other-window)
    (define-key map (kbd "C-x 1")   'nyaatree-empty-fn)
    (define-key map (kbd "C-x 2")   'nyaatree-empty-fn)
    (define-key map (kbd "C-x 3")   'nyaatree-empty-fn)
    (define-key map (kbd "C-c C-f") 'find-file-other-window)
    (define-key map (kbd "C-c C-c") 'nyaatree-change-root)
    (define-key map (kbd "C-c c")   'nyaatree-dir)
    (define-key map (kbd "C-c C-a")  'nyaatree-collapse-all)
    (cond
     ((eq nyaatree-keymap-style 'default)
      (define-key map (kbd "C-c C-n") 'nyaatree-create-node)
      (define-key map (kbd "C-c C-d") 'nyaatree-delete-node)
      (define-key map (kbd "C-c C-r") 'nyaatree-rename-node)
      (define-key map (kbd "C-c C-p") 'nyaatree-copy-node))
     ((eq nyaatree-keymap-style 'concise)
      (define-key map (kbd "C") 'nyaatree-change-root)
      (define-key map (kbd "c") 'nyaatree-create-node)
      (define-key map (kbd "+") 'nyaatree-create-node)
      (define-key map (kbd "d") 'nyaatree-delete-node)
      (define-key map (kbd "r") 'nyaatree-rename-node)
      (define-key map (kbd "e") 'nyaatree-enter)))
    map)
  "Keymap for `nyaatree-mode'.")

(define-derived-mode nyaatree-mode special-mode "NyaaTree"
  "A major mode for displaying the directory tree in text mode."
  (setq indent-tabs-mode nil            ; only spaces
        buffer-read-only t              ; read only
        truncate-lines -1
        nyaatree-buffer--show-hidden-file-p nyaatree-show-hidden-files)
  (when nyaatree-hide-cursor
    (progn
      (setq cursor-type nil)
      (hl-line-mode +1)))
  (pcase nyaatree-mode-line-type
    (`nyaatree
     (setq-local mode-line-format nyaatree-mode-line-format)
     (add-hook 'post-command-hook 'force-mode-line-update nil t))
    (`none (setq-local mode-line-format nil))
    (`custom
     (setq-local mode-line-format nyaatree-mode-line-custom-format)
     (add-hook 'post-command-hook 'force-mode-line-update nil t))
    (_ nil))
  ;; fix for electric-indent-mode
  ;; for emacs 24.4
  (if (fboundp 'electric-indent-local-mode)
      (electric-indent-local-mode -1)
    ;; for emacs 24.3 or less
    (add-hook 'electric-indent-functions
              (lambda (arg) 'no-indent) nil 'local))
  (when nyaatree-auto-indent-point
    (add-hook 'post-command-hook 'nyaatree-hook--node-first-letter nil t)))

;;
;; Global methods
;;

(defun nyaatree-global--window-exists-p ()
  "Return non-nil if nyaatree window exists."
  (and (not (null (window-buffer nyaatree-global--window)))
       (eql (window-buffer nyaatree-global--window) (nyaatree-global--get-buffer))))

(defun nyaatree-global--select-window ()
  "Select the NyaaTree window."
  (interactive)
  (let ((window (nyaatree-global--get-window t)))
    (select-window window)))

(defun nyaatree-global--get-window (&optional auto-create-p)
  "Return the nyaatree window if it exists, else return nil.
But when the nyaatree window does not exist and AUTO-CREATE-P is non-nil,
it will create the nyaatree window and return it."
  (unless (nyaatree-global--window-exists-p)
    (setf nyaatree-global--window nil))
  (when (and (null nyaatree-global--window)
             auto-create-p)
    (setq nyaatree-global--window
          (nyaatree-global--create-window)))
  nyaatree-global--window)

(defun nyaatree-default-display-fn (buffer _alist)
  "Display BUFFER to the left or right of the root window.
The side is decided according to `nyaatree-window-position'.
The root window is the root window of the selected frame.
_ALIST is ignored."
  (let ((window-pos (if (eq nyaatree-window-position 'left) 'left 'right)))
    (display-buffer-in-side-window buffer `((side . ,window-pos)))))

(defun nyaatree-global--create-window ()
  "Create global nyaatree window."
  (let ((window nil)
        (buffer (nyaatree-global--get-buffer t)))
    (setq window
          (select-window
           (display-buffer buffer nyaatree-display-action)))
    (nyaatree-window--init window buffer)
    (nyaatree-global--attach)
    (nyaatree-global--reset-width)
    window))

(defun nyaatree-global--get-buffer (&optional init-p)
  "Return the global nyaatree buffer if it exists.
If INIT-P is non-nil and global NyaaTree buffer not exists, then create it."
  (unless (equal (buffer-name nyaatree-global--buffer)
                 nyaatree-buffer-name)
    (setf nyaatree-global--buffer nil))
  (when (and init-p
             (null nyaatree-global--buffer))
    (save-window-excursion
      (setq nyaatree-global--buffer
            (nyaatree-buffer--create))))
  nyaatree-global--buffer)

(defun nyaatree-global--file-in-root-p (path)
  "Return non-nil if PATH in root dir."
  (nyaatree-global--with-buffer
    (and (not (null nyaatree-buffer--start-node))
         (nyaatree-path--file-in-directory-p path nyaatree-buffer--start-node))))

(defun nyaatree-global--alone-p ()
  "Check whether the global nyaatree window is alone with some other window."
  (let ((windows (window-list)))
    (and (= (length windows)
            2)
         (member nyaatree-global--window windows))))

(defun nyaatree-global--do-autorefresh ()
  "Do auto refresh."
  (interactive)
  (when (and nyaatree-autorefresh (nyaatree-global--window-exists-p)
             (buffer-file-name))
    (nyaatree-refresh t)))

(defun nyaatree-global--open ()
  "Show the NyaaTree window."
  (let ((valid-start-node-p nil))
    (nyaatree-global--with-buffer
      (setf valid-start-node-p (nyaatree-buffer--valid-start-node-p)))
    (if (not valid-start-node-p)
        (nyaatree-global--open-dir (nyaatree-path--get-working-dir))
      (nyaatree-global--get-window t))))

(defun nyaatree-global--open-dir (path)
  "Show the NyaaTree window, and change root to PATH."
  (nyaatree-global--get-window t)
  (nyaatree-global--with-buffer
    (nyaatree-buffer--change-root path)))

(defun nyaatree-global--open-and-find (path)
  "Quick select node which specified PATH in NyaaTree."
  (let ((npath path)
        root-dir)
    (when (null npath)
      (throw 'invalid-path "Invalid path to select."))
    (setq root-dir (if (file-directory-p npath)
                       npath (nyaatree-path--updir npath)))
    (when (or (not (nyaatree-global--window-exists-p))
              (not (nyaatree-global--file-in-root-p npath)))
      (nyaatree-global--open-dir root-dir))
    (nyaatree-global--with-window
      (nyaatree-buffer--select-file-node npath t))))

(defun nyaatree-global--select-mru-window (arg)
  "Create or find a window to select when open a file node.
The description of ARG is in `nyaatree-enter'."
  (when (eq (safe-length (window-list)) 1)
    (nyaatree-buffer--with-resizable-window
     (split-window-horizontally)))
  (when nyaatree-reset-size-on-open
    (nyaatree-global--when-window
      (nyaatree-window--zoom 'minimize)))
  ;; select target window
  (cond
   ;; select window with winum
   ((and (integerp arg)
         (bound-and-true-p winum-mode)
         (fboundp 'winum-select-window-by-number))
    (winum-select-window-by-number arg))
   ;; select window with window numbering
   ((and (integerp arg)
         (boundp 'window-numbering-mode)
         (symbol-value window-numbering-mode)
         (fboundp 'select-window-by-number))
    (select-window-by-number arg))
   ;; open node in a new vertically split window
   ((and (stringp arg) (string= arg "a")
         (fboundp 'ace-select-window))
    (ace-select-window))
   ((and (stringp arg) (string= arg "|"))
    (select-window (get-mru-window))
    (split-window-right)
    (windmove-right))
   ;; open node in a new horizontally split window
   ((and (stringp arg) (string= arg "-"))
    (select-window (get-mru-window))
    (split-window-below)
    (windmove-down)))
  ;; open node in last active window
  (select-window (get-mru-window)))

(defun nyaatree-global--detach ()
  "Detach the global nyaatree buffer."
  (when nyaatree-global--autorefresh-timer
    (cancel-timer nyaatree-global--autorefresh-timer))
  (nyaatree-global--with-buffer
    (nyaatree-buffer--unlock-width))
  (setq nyaatree-global--buffer nil)
  (setq nyaatree-global--window nil))

(defun nyaatree-global--attach ()
  "Attach the global nyaatree buffer"
  (when nyaatree-global--autorefresh-timer
    (cancel-timer nyaatree-global--autorefresh-timer))
  (when nyaatree-autorefresh
    (setq nyaatree-global--autorefresh-timer
          (run-with-idle-timer 2 10 'nyaatree-global--do-autorefresh)))
  (setq nyaatree-global--buffer (get-buffer nyaatree-buffer-name))
  (setq nyaatree-global--window (get-buffer-window
                            nyaatree-global--buffer))
  (nyaatree-global--with-buffer
    (nyaatree-buffer--lock-width))
  (run-hook-with-args 'nyaatree-after-create-hook '(window)))

(defun nyaatree-global--set-window-width (width)
  "Set nyaatree window width to WIDTH."
  (nyaatree-global--with-window
    (nyaatree-buffer--with-resizable-window
     (nyaatree-util--set-window-width (selected-window) width))))

(defun nyaatree-global--reset-width ()
  "Set nyaatree window width to `nyaatree-window-width'."
  (nyaatree-global--set-window-width nyaatree-window-width))

;;
;; Advices
;;

(defadvice mouse-drag-vertical-line
    (around nyaatree-drag-vertical-line (start-event) activate)
  "Drag and drop is not affected by the lock."
  (nyaatree-buffer--with-resizable-window
   ad-do-it))

(defadvice balance-windows
    (around nyaatree-balance-windows activate)
  "Fix nyaatree inhibits balance-windows."
  (if (nyaatree-global--window-exists-p)
      (let (old-width)
        (nyaatree-global--with-window
          (setq old-width (window-width)))
        (nyaatree-buffer--with-resizable-window
         ad-do-it)
        (nyaatree-global--with-window
          (nyaatree-global--set-window-width old-width)))
    ad-do-it))

(eval-after-load 'popwin
  '(progn
     (defadvice popwin:create-popup-window
         (around nyaatree/popwin-popup-buffer activate)
       (let ((nyaatree-exists-p (nyaatree-global--window-exists-p)))
         (when nyaatree-exists-p
           (nyaatree-global--detach))
         ad-do-it
         (when nyaatree-exists-p
           (nyaatree-global--attach)
           (nyaatree-global--reset-width))))

     (defadvice popwin:close-popup-window
         (around nyaatree/popwin-close-popup-window activate)
       (let ((nyaatree-exists-p (nyaatree-global--window-exists-p)))
         (when nyaatree-exists-p
           (nyaatree-global--detach))
         ad-do-it
         (when nyaatree-exists-p
           (nyaatree-global--attach)
           (nyaatree-global--reset-width))))))

;;
;; Hooks
;;

(defun nyaatree-hook--node-first-letter ()
  "Move point to the first letter of the current node."
  (when (or (eq this-command 'next-line)
            (eq this-command 'previous-line))
    (nyaatree-point-auto-indent)))

;;
;; Util methods
;;

(defun nyaatree-util--filter (condp lst)
  "Apply CONDP to elements of LST keeping those that return non-nil.

Example:
    (nyaatree-util--filter 'symbolp '(a \"b\" 3 d4))
         => (a d4)

This procedure does not work when CONDP is the `null' function."
  (delq nil
        (mapcar (lambda (x) (and (funcall condp x) x)) lst)))

(defun nyaatree-util--find (where which)
  "Find element of the list WHERE matching predicate WHICH."
  (catch 'found
    (dolist (elt where)
      (when (funcall which elt)
        (throw 'found elt)))
    nil))

(defun nyaatree-util--make-printable-string (string)
  "Strip newline character from STRING, like 'Icon\n'."
  (replace-regexp-in-string "\n" "" string))

(defun nyaatree-util--walk-dir (path)
  "Return the subdirectories and subfiles of the PATH."
  (let* ((full-path (nyaatree-path--file-truename path)))
    (condition-case nil
        (directory-files
         path 'full directory-files-no-dot-files-regexp)
      ('file-error
       (message "Walk directory %S failed." path)
       nil))))

(defun nyaatree-util--hidden-path-filter (node)
  "A filter function, if the NODE can not match each item in \
`nyaatree-hidden-regexp-list', return t."
  (if (not nyaatree-buffer--show-hidden-file-p)
      (let ((shortname (nyaatree-path--file-short-name node)))
        (null (nyaatree-util--filter
               (lambda (x) (not (null (string-match-p x shortname))))
               nyaatree-hidden-regexp-list)))
    node))

(defun nyaatree-str--trim-left (s)
  "Remove whitespace at the beginning of S."
  (if (string-match "\\`[ \t\n\r]+" s)
      (replace-match "" t t s)
    s))

(defun nyaatree-str--trim-right (s)
  "Remove whitespace at the end of S."
  (if (string-match "[ \t\n\r]+\\'" s)
      (replace-match "" t t s)
    s))

(defun nyaatree-str--trim (s)
  "Remove whitespace at the beginning and end of S."
  (nyaatree-str--trim-left (nyaatree-str--trim-right s)))

(defun nyaatree-path--expand-name (path &optional current-dir)
  (expand-file-name (or (if (file-name-absolute-p path) path)
			(let ((r-path path))
			  (setq r-path (substitute-in-file-name r-path))
			  (setq r-path (expand-file-name r-path current-dir))
			  r-path))))

(defun nyaatree-path--shorten (path len)
  "Shorten a given PATH to a specified LEN.
This is needed for paths, which are to long for the window to display
completely.  The function cuts of the first part of the path to remain
the last folder (the current one)."
  (let ((result
         (if (> (length path) len)
             (concat "<" (substring path (- (- len 2))))
           path)))
    (when result
      (decode-coding-string result 'utf-8))))

(defun nyaatree-path--insert-chroot-button (label path face)
  (insert-button
   label
   'action '(lambda (x) (nyaatree-change-root))
   'follow-link t
   'face face
   'nyaatree-full-path path))

(defun nyaatree-path--insert-header-buttonized (path)
  "Shortens the PATH to (window-body-width) and displays any \
visible remains as buttons that, when clicked, navigate to that
parent directory."
  (let* ((dirs (reverse (cl-maplist 'identity (reverse (split-string path "/" :omitnulls)))))
         (last (car-safe (car-safe (last dirs)))))
    (nyaatree-path--insert-chroot-button "/" "/" 'nyaatree-root-dir-face)
    (dolist (dir dirs)
      (if (string= (car dir) last)
          (nyaatree-buffer--insert-with-face last 'nyaatree-root-dir-face)
        (nyaatree-path--insert-chroot-button
         (concat (car dir) "/")
         (apply 'nyaatree-path--join (cons "/" (reverse dir)))
         'nyaatree-root-dir-face))))
  ;;shorten the line if need be
  (when (> (current-column) (window-body-width))
    (forward-char (- (window-body-width)))
    (delete-region (point-at-bol) (point))
    (let* ((button (button-at (point)))
           (path (if button (overlay-get button 'nyaatree-full-path) "/")))
      (nyaatree-path--insert-chroot-button "<" path 'nyaatree-root-dir-face))
    (end-of-line)))

(defun nyaatree-path--updir (path)
  (let ((r-path (nyaatree-path--expand-name path)))
    (if (and (> (length r-path) 0)
             (equal (substring r-path -1) "/"))
        (setq r-path (substring r-path 0 -1)))
    (if (eq (length r-path) 0)
        (setq r-path "/"))
    (directory-file-name
     (file-name-directory r-path))))

(defun nyaatree-path--join (root &rest dirs)
  "Joins a series of directories together with ROOT and DIRS.
Like Python's os.path.join,
  (nyaatree-path--join \"/tmp\" \"a\" \"b\" \"c\") => /tmp/a/b/c ."
  (or (if (not dirs) root)
      (let ((tdir (car dirs))
            (epath nil))
        (setq epath
              (or (if (equal tdir ".") root)
                  (if (equal tdir "..") (nyaatree-path--updir root))
                  (nyaatree-path--expand-name tdir root)))
        (apply 'nyaatree-path--join
               epath
               (cdr dirs)))))

(defun nyaatree-path--file-short-name (file)
  "Base file/directory name by FILE.
Taken from http://lists.gnu.org/archive/html/emacs-devel/2011-01/msg01238.html"
  (or (if (string= file "/") "/")
      (nyaatree-util--make-printable-string (file-name-nondirectory (directory-file-name file)))))

(defun nyaatree-path--file-truename (path)
  (let ((rlt (file-truename path)))
    (if (not (null rlt))
        (progn
          (if (and (file-directory-p rlt)
                   (> (length rlt) 0)
                   (not (equal (substring rlt -1) "/")))
              (setq rlt (concat rlt "/")))
          rlt)
      nil)))

(defun nyaatree-path--has-subfile-p (dir)
  "To determine whether a directory(DIR) contain files."
  (and (file-exists-p dir)
       (file-directory-p dir)
       (nyaatree-util--walk-dir dir)
       t))

(defun nyaatree-path--match-path-directory (path)
  (let ((true-path (nyaatree-path--file-truename path))
        (rlt-path nil))
    (setq rlt-path
          (catch 'rlt
            (if (file-directory-p true-path)
                (throw 'rlt true-path))
            (setq true-path
                  (file-name-directory true-path))
            (if (file-directory-p true-path)
                (throw 'rlt true-path))))
    (if (not (null rlt-path))
        (setq rlt-path (nyaatree-path--join "." rlt-path "./")))
    rlt-path))

(defun nyaatree-path--get-working-dir ()
  "Return a directory name of the current buffer."
  (file-name-as-directory (file-truename default-directory)))

(defun nyaatree-path--strip (path)
  "Remove whitespace at the end of PATH."
  (let* ((rlt (nyaatree-str--trim path))
         (pos (string-match "[\\\\/]+\\'" rlt)))
    (when pos
      (setq rlt (replace-match "" t t rlt))
      (when (eq (length rlt) 0)
        (setq rlt "/")))
    rlt))

(defun nyaatree-path--path-equal-p (path1 path2)
  "Return non-nil if pathes PATH1 and PATH2 are the same path."
  (string-equal (nyaatree-path--strip path1)
                (nyaatree-path--strip path2)))

(defun nyaatree-path--file-equal-p (file1 file2)
  "Return non-nil if files FILE1 and FILE2 name the same file.
If FILE1 or FILE2 does not exist, the return value is unspecified."
  (unless (or (null file1)
              (null file2))
    (let ((nfile1 (nyaatree-path--strip file1))
          (nfile2 (nyaatree-path--strip file2)))
      (file-equal-p nfile1 nfile2))))

(defun nyaatree-path--file-in-directory-p (file dir)
  "Return non-nil if FILE is in DIR or a subdirectory of DIR.
A directory is considered to be \"in\" itself.
Return nil if DIR is not an existing directory."
  (let ((nfile (nyaatree-path--strip file))
        (ndir (nyaatree-path--strip dir)))
    (setq ndir (concat ndir "/"))
    (file-in-directory-p nfile ndir)))

(defun nyaatree-util--kill-buffers-for-path (path)
  "Kill all buffers for files in PATH."
  (let ((buffer (find-buffer-visiting path)))
    (when buffer
      (kill-buffer buffer)))
  (dolist (filename (directory-files path t directory-files-no-dot-files-regexp))
    (let ((buffer (find-buffer-visiting filename)))
      (when buffer
        (kill-buffer buffer))
      (when (and
             (file-directory-p filename)
             (nyaatree-path--has-subfile-p filename))
        (nyaatree-util--kill-buffers-for-path filename)))))

(defun nyaatree-util--set-window-width (window n)
  "Make WINDOW N columns width."
  (let ((w (max n window-min-width)))
    (unless (null window)
      (if (> (window-width) w)
          (shrink-window-horizontally (- (window-width) w))
        (if (< (window-width) w)
            (enlarge-window-horizontally (- w (window-width))))))))

(defun nyaatree-point-auto-indent ()
  "Put the point on the first letter of the current node."
  (when (nyaatree-buffer--get-filename-current-line)
    (beginning-of-line 1)
    (re-search-forward "[^-\s+]" (line-end-position 1) t)
    (backward-char 1)))

(defun off-p (msg)
  "Returns true regardless of message value in the argument."
  t)

(defun nyaatree-sort-hidden-last (x y)
  "Sort normally but with hidden files last."
  (let ((x-hidden (nyaatree-filepath-hidden-p x))
        (y-hidden (nyaatree-filepath-hidden-p y)))
    (cond
     ((and x-hidden (not y-hidden))
      nil)
     ((and (not x-hidden) y-hidden)
      t)
     (t
      (string< x y)))))

(defun nyaatree-filepath-hidden-p (node)
  "Return whether or not node is a hidden path."
  (let ((shortname (nyaatree-path--file-short-name node)))
    (nyaatree-util--filter
     (lambda (x) (not (null (string-match-p x shortname))))
     nyaatree-hidden-regexp-list)))

(defun nyaatree-get-unsaved-buffers-from-projectile ()
  "Return list of unsaved buffers from projectile buffers."
  (interactive)
  (if (fboundp 'projectile-project-buffers)
      (let ((rlist '())
            (rtag t))
        (condition-case nil
            (projectile-project-buffers)
          (error (setq rtag nil)))
        (when rtag
          (dolist (buf (projectile-project-buffers))
            (with-current-buffer buf
              (if (and (buffer-modified-p) buffer-file-name)
                  (setq rlist (cons (buffer-file-name) rlist))
                ))))
        rlist))
  (error "Projectile not installed")
  )

;;
;; Buffer methods
;;

(defun nyaatree-buffer--newline-and-begin ()
  "Insert new line."
  (newline)
  (beginning-of-line))

(defun nyaatree-buffer--get-icon (name)
  "Get image by NAME."
  (let ((icon-path (nyaatree-path--join nyaatree-dir "icons"))
        image)
    (setq image (create-image
                 (nyaatree-path--join icon-path (concat name ".xpm"))
                 'xpm nil :ascent 'center :mask '(heuristic t)))
    image))

(defun nyaatree--all-the-icons-icon-for-dir-with-chevron (dir &optional chevron)
  "Note: I have not tested that this function doesn't break all-the-icons"
  (if (fboundp 'all-the-icons-icon-for-dir-with-chevron)
      (all-the-icons-icon-for-dir-with-chevron dir chevron)
    (error "all-the-icons-icons is not installed")
    )
  )
(defun nyaatree--all-the-icons-icon-for-file (name)
  (if (fboundp 'all-the-icons-icon-for-file)
      (all-the-icons-icon-for-file name)
    (error "all-the-icons is not installed.")
    )
  )

(defun nyaatree--nerd-icons-icon-for-dir-with-chevron (dir &optional chevron padding)
  (if (and (fboundp 'nerd-icons-icon-for-dir) (fboundp 'nerd-icons-octicon))
      (let ((icon (nerd-icons-icon-for-dir dir))
            (chevron (if chevron (nerd-icons-octicon (format "nf-oct-chevron_%s" chevron) :height 0.8 :v-adjust -0.1) ""))
            (padding (or padding "\t")))
        (format "%s%s%s%s%s" padding chevron padding icon padding))
    (error "nerd-icons is not installed")
    )
  )
(defun nyaatree--nerd-icons-icon-for-file (name)
  (if (fboundp 'nerd-icons-icon-for-file)
      (nerd-icons-icon-for-file name)
    (error "nerd-icons is not installed")
    )
  )

(defun nyaatree-buffer--insert-fold-symbol (name &optional node-name)
  "Write icon by NAME, the icon style affected by nyaatree-theme.
`open' write opened folder icon.
`close' write closed folder icon.
`leaf' write leaf icon.
Optional NODE-NAME is used for the `icons' theme"
  (let ((n-insert-image (lambda (n)
                          (insert-image (nyaatree-buffer--get-icon n))))
        (n-insert-symbol (lambda (n)
                           (nyaatree-buffer--insert-with-face
                            n 'nyaatree-expand-btn-face))))
    (cond
     ((and (display-graphic-p) (equal nyaatree-theme 'classic))
      (or (and (equal name 'open)  (funcall n-insert-image "open"))
          (and (equal name 'close) (funcall n-insert-image "close"))
          (and (equal name 'leaf)  (funcall n-insert-image "leaf"))))
     ((equal nyaatree-theme 'arrow)
      (or (and (equal name 'open)  (funcall n-insert-symbol "▾"))
          (and (equal name 'close) (funcall n-insert-symbol "▸"))))
     ((equal nyaatree-theme 'nerd)
      (or (and (equal name 'open)  (funcall n-insert-symbol "▾ "))
          (and (equal name 'close) (funcall n-insert-symbol "▸ "))
          (and (equal name 'leaf)  (funcall n-insert-symbol "  "))))
     ((and (display-graphic-p) (equal nyaatree-theme 'icons))
      (unless (require 'all-the-icons nil 'noerror)
        (error "Package `all-the-icons' isn't installed"))
      (setq-local tab-width 1)
      (or (and (equal name 'open)  (insert (nyaatree--all-the-icons-icon-for-dir-with-chevron (directory-file-name node-name) "down")))
          (and (equal name 'close) (insert (nyaatree--all-the-icons-icon-for-dir-with-chevron (directory-file-name node-name) "right")))
          (and (equal name 'leaf)  (insert (format "\t\t\t%s\t" (nyaatree--all-the-icons-icon-for-file node-name))))))
     ((equal nyaatree-theme 'nerd-icons)
      (unless (require 'nerd-icons nil 'noerror)
        (error "Package `nerd-icons' isn't installed"))
      (setq-local tab-width 1)
      (or (and (equal name 'open)  (insert (nyaatree--nerd-icons-icon-for-dir-with-chevron (directory-file-name node-name) "down")))
          (and (equal name 'close) (insert (nyaatree--nerd-icons-icon-for-dir-with-chevron (directory-file-name node-name) "right")))
          (and (equal name 'leaf)  (insert (format "\t\t\t%s\t" (nyaatree--nerd-icons-icon-for-file node-name))))))
     (t
      (or (and (equal name 'open)  (funcall n-insert-symbol "- "))
          (and (equal name 'close) (funcall n-insert-symbol "+ ")))))))

(defun nyaatree-buffer--save-cursor-pos (&optional node-path line-pos)
  "Save cursor position.
If NODE-PATH and LINE-POS is nil, it will be save the current line node position."
  (let ((cur-node-path nil)
        (cur-line-pos nil)
        (ws-wind (selected-window))
        (ws-pos (window-start)))
    (setq cur-node-path (if node-path
                            node-path
                          (nyaatree-buffer--get-filename-current-line)))
    (setq cur-line-pos (if line-pos
                           line-pos
                         (line-number-at-pos)))
    (setq nyaatree-buffer--cursor-pos (cons cur-node-path cur-line-pos))
    (setq nyaatree-buffer--last-window-pos (cons ws-wind ws-pos))))

(defun nyaatree-buffer--goto-cursor-pos ()
  "Jump to saved cursor position."
  (let ((line-pos nil)
        (node (car nyaatree-buffer--cursor-pos))
        (line-pos (cdr nyaatree-buffer--cursor-pos))
        (ws-wind (car nyaatree-buffer--last-window-pos))
        (ws-pos (cdr nyaatree-buffer--last-window-pos)))
    (catch 'line-pos-founded
      (unless (null node)
        (setq line-pos 0)
        (mapc
         (lambda (x)
           (setq line-pos (1+ line-pos))
           (unless (null x)
             (when (nyaatree-path--path-equal-p x node)
               (throw 'line-pos-founded line-pos))))
         nyaatree-buffer--node-list))
      (setq line-pos (cdr nyaatree-buffer--cursor-pos))
      (throw 'line-pos-founded line-pos))
    ;; goto line
    (goto-char (point-min))
    (nyaatree-buffer--forward-line (1- line-pos))
    ;; scroll window
    (when (equal (selected-window) ws-wind)
      (set-window-start ws-wind ws-pos t))))

(defun nyaatree-buffer--node-list-clear ()
  "Clear node list."
  (setq nyaatree-buffer--node-list nil))

(defun nyaatree-buffer--node-list-set (line-num path)
  "Set value in node list.
LINE-NUM is the index of node list.
PATH is value."
  (let ((node-list-length (length nyaatree-buffer--node-list))
        (node-index line-num))
    (when (null node-index)
      (setq node-index (line-number-at-pos)))
    (when (< node-list-length node-index)
      (setq nyaatree-buffer--node-list
            (vconcat nyaatree-buffer--node-list
                     (make-vector (- node-index node-list-length) nil))))
    (aset nyaatree-buffer--node-list (1- node-index) path))
  nyaatree-buffer--node-list)

(defun nyaatree-buffer--insert-with-face (content face)
  (let ((pos-start (point)))
    (insert content)
    (set-text-properties pos-start
                         (point)
                         (list 'face face))))

(defun nyaatree-buffer--valid-start-node-p ()
  (and (not (null nyaatree-buffer--start-node))
       (file-accessible-directory-p nyaatree-buffer--start-node)))

(defun nyaatree-buffer--create ()
  "Create and switch to NyaaTree buffer."
  (switch-to-buffer
   (generate-new-buffer-name nyaatree-buffer-name))
  (nyaatree-mode)
  ;; disable linum-mode
  (when (and (fboundp 'linum-mode)
             (not (null linum-mode)))
    (linum-mode -1))
  ;; Use inside helm window in NyaaTree
  ;; Refs https://github.com/jaypei/emacs-nyaatree/issues/226
  (setq-local helm-split-window-inside-p t)
  (current-buffer))

(defun nyaatree-buffer--insert-banner ()
  (unless (null nyaatree-banner-message)
    (let ((start (point)))
      (insert nyaatree-banner-message)
      (set-text-properties start (point) '(face nyaatree-banner-face)))
    (nyaatree-buffer--newline-and-begin)))

(defun nyaatree-buffer--insert-root-entry (node)
  (nyaatree-buffer--node-list-set nil node)
  (cond ((eq nyaatree-cwd-line-style 'button)
         (nyaatree-path--insert-header-buttonized node))
        (t
         (nyaatree-buffer--insert-with-face (nyaatree-path--shorten node (window-body-width))
                                       'nyaatree-root-dir-face)))
  (nyaatree-buffer--newline-and-begin)
  (when nyaatree-show-updir-line
    (nyaatree-buffer--insert-fold-symbol 'close node)
    (insert-button ".."
                   'action '(lambda (x) (nyaatree-change-root))
                   'follow-link t
                   'face nyaatree-dir-link-face
                   'nyaatree-full-path (nyaatree-path--updir node))
    (nyaatree-buffer--newline-and-begin)))

(defun nyaatree-buffer--help-echo-message (node-name)
  (cond
   ((eq nyaatree-help-echo-style 'default)
    (if (<= (+ (current-column) (string-width node-name))
            nyaatree-window-width)
        nil
      node-name))
   (t nil)))

(defun nyaatree-buffer--insert-dir-entry (node depth expanded)
  (let ((node-short-name (nyaatree-path--file-short-name node)))
    (insert-char ?\s (* (- depth 1) 2)) ; indent
    (when (memq 'char nyaatree-vc-integration)
      (insert-char ?\s 2))
    (nyaatree-buffer--insert-fold-symbol
     (if expanded 'open 'close) node)
    (insert-button (if nyaatree-show-slash-for-folder (concat node-short-name "/") node-short-name)
                   'follow-link t
                   'face nyaatree-dir-link-face
                   'nyaatree-full-path node
                   'keymap nyaatree-dir-button-keymap
                   'help-echo (nyaatree-buffer--help-echo-message node-short-name))
    (nyaatree-buffer--node-list-set nil node)
    (nyaatree-buffer--newline-and-begin)))

(defun nyaatree-buffer--insert-file-entry (node depth)
  (let ((node-short-name (nyaatree-path--file-short-name node))
        (vc (when nyaatree-vc-integration (nyaatree-vc-for-node node))))
    (insert-char ?\s (* (- depth 1) 2)) ; indent
    (when (memq 'char nyaatree-vc-integration)
      (insert-char (car vc))
      (insert-char ?\s))
    (nyaatree-buffer--insert-fold-symbol 'leaf node-short-name)
    (insert-button node-short-name
                   'follow-link t
                   'face (if (memq 'face nyaatree-vc-integration)
                             (cdr vc)
                           nyaatree-file-link-face)
                   'nyaatree-full-path node
                   'keymap nyaatree-file-button-keymap
                   'help-echo (nyaatree-buffer--help-echo-message node-short-name))
    (nyaatree-buffer--node-list-set nil node)
    (nyaatree-buffer--newline-and-begin)))

(defun nyaatree-vc-for-node (node)
  (let* ((backend (ignore-errors
                    (vc-responsible-backend node)))
         (vc-state (when backend (vc-state node backend))))
    (cons (cdr (assoc vc-state nyaatree-vc-state-char-alist))
          (cl-case vc-state
            (up-to-date       nyaatree-vc-up-to-date-face)
            (edited           nyaatree-vc-edited-face)
            (needs-update     nyaatree-vc-needs-update-face)
            (needs-merge      nyaatree-vc-needs-merge-face)
            (unlocked-changes nyaatree-vc-unlocked-changes-face)
            (added            nyaatree-vc-added-face)
            (removed          nyaatree-vc-removed-face)
            (conflict         nyaatree-vc-conflict-face)
            (missing          nyaatree-vc-missing-face)
            (ignored          nyaatree-vc-ignored-face)
            (unregistered     nyaatree-vc-unregistered-face)
            (user             nyaatree-vc-user-face)
            (otherwise        nyaatree-vc-default-face)))))

(defun nyaatree-buffer--get-nodes (path)
  (let* ((nodes (nyaatree-util--walk-dir path))
         (comp nyaatree-filepath-sort-function)
         (nodes (nyaatree-util--filter 'nyaatree-util--hidden-path-filter nodes)))
    (cons (sort (nyaatree-util--filter 'file-directory-p nodes) comp)
          (sort (nyaatree-util--filter #'(lambda (f) (not (file-directory-p f))) nodes) comp))))

(defun nyaatree-buffer--get-node-index (node nodes)
  "Return the index of NODE in NODES.

NODES can be a list of directory or files.
Return nil if NODE has not been found in NODES."
  (let ((i 0)
        (l (length nodes))
        (cur (car nodes))
        (rest (cdr nodes)))
    (while (and cur (not (equal cur node)))
      (setq i (1+ i))
      (setq cur (car rest))
      (setq rest (cdr rest)))
    (if (< i l) i)))

(defun nyaatree-buffer--expanded-node-p (node)
  "Return non-nil if NODE is expanded."
  (nyaatree-util--to-bool
   (nyaatree-util--find
    nyaatree-buffer--expanded-node-list
    #'(lambda (x) (equal x node)))))

(defun nyaatree-buffer--set-expand (node do-expand)
  "Set the expanded state of the NODE to DO-EXPAND.
Return the new expand state for NODE (t for expanded, nil for collapsed)."
  (if (not do-expand)
      (setq nyaatree-buffer--expanded-node-list
            (nyaatree-util--filter
             #'(lambda (x) (not (equal node x)))
             nyaatree-buffer--expanded-node-list))
    (push node nyaatree-buffer--expanded-node-list))
  do-expand)

(defun nyaatree-buffer--toggle-expand (node)
  (nyaatree-buffer--set-expand node (not (nyaatree-buffer--expanded-node-p node))))

(defun nyaatree-buffer--insert-tree (path depth)
  (if (eq depth 1)
      (nyaatree-buffer--insert-root-entry path))
  (let* ((contents (nyaatree-buffer--get-nodes path))
         (nodes (car contents))
         (leafs (cdr contents))
         (default-directory path))
    (dolist (node nodes)
      (let ((expanded (nyaatree-buffer--expanded-node-p node)))
        (nyaatree-buffer--insert-dir-entry
         node depth expanded)
        (if expanded (nyaatree-buffer--insert-tree (concat node "/") (+ depth 1)))))
    (dolist (leaf leafs)
      (nyaatree-buffer--insert-file-entry leaf depth))))

(defun nyaatree-buffer--refresh (save-pos-p &optional non-nyaatree-buffer)
  "Refresh the NyaaTree buffer.
If SAVE-POS-P is non-nil, it will be auto save current line number."
  (let ((start-node nyaatree-buffer--start-node))
    (unless start-node
      (setq start-node default-directory))
    (nyaatree-buffer--with-editing-buffer
     ;; save context
     (when save-pos-p
       (nyaatree-buffer--save-cursor-pos))
     (when non-nyaatree-buffer
       (setq nyaatree-buffer--start-node start-node))
     ;; starting refresh
     (erase-buffer)
     (nyaatree-buffer--node-list-clear)
     (nyaatree-buffer--insert-banner)
     (setq nyaatree-buffer--start-line nyaatree-header-height)
     (nyaatree-buffer--insert-tree start-node 1))
    ;; restore context
    (nyaatree-buffer--goto-cursor-pos)))

(defun nyaatree-buffer--post-move ()
  "Reset current directory when position moved."
  (funcall
   (nyaatree-make-executor
    :file-fn
    '(lambda (path _)
       (setq default-directory (nyaatree-path--updir btn-full-path)))
    :dir-fn
    '(lambda (path _)
       (setq default-directory (file-name-as-directory path))))))

(defun nyaatree-buffer--get-button-current-line ()
  "Return the first button in current line."
  (let* ((btn-position nil)
         (pos-line-start (line-beginning-position))
         (pos-line-end (line-end-position))
         ;; NOTE: cannot find button when the button
         ;;       at beginning of the line
         (current-button (or (button-at (point))
                             (button-at pos-line-start))))
    (if (null current-button)
        (progn
          (setf btn-position
                (catch 'ret-button
                  (let* ((next-button (next-button pos-line-start))
                         (pos-btn nil))
                    (if (null next-button) (throw 'ret-button nil))
                    (setf pos-btn (overlay-start next-button))
                    (if (> pos-btn pos-line-end) (throw 'ret-button nil))
                    (throw 'ret-button pos-btn))))
          (if (null btn-position)
              nil
            (setf current-button (button-at btn-position)))))
    current-button))

(defun nyaatree-buffer--get-filename-current-line (&optional default)
  "Return filename for first button in current line.
If there is no button in current line, then return DEFAULT."
  (let ((btn (nyaatree-buffer--get-button-current-line)))
    (if (not (null btn))
        (button-get btn 'nyaatree-full-path)
      default)))

(defun nyaatree-buffer--lock-width ()
  "Lock the width size for NyaaTree window."
  (if nyaatree-window-fixed-size
      (setq window-size-fixed 'width)))

(defun nyaatree-buffer--unlock-width ()
  "Unlock the width size for NyaaTree window."
  (setq window-size-fixed nil))

(defun nyaatree-buffer--rename-node ()
  "Rename current node as another path."
  (interactive)
  (let* ((current-path (nyaatree-buffer--get-filename-current-line))
         (buffer (find-buffer-visiting current-path))
         to-path
         msg)
    (unless (null current-path)
      (setq msg (format "Rename [%s] to: " (nyaatree-path--file-short-name current-path)))
      (setq to-path (read-file-name msg (file-name-directory current-path)))
      (if (vc-registered current-path)
          (vc-rename-file current-path to-path)
          (rename-file current-path to-path 1))
      (if buffer
          (with-current-buffer buffer
            (set-visited-file-name to-path nil t)))
      (nyaatree-buffer--refresh t)
      (message "Rename successful."))))

(defun nyaatree-buffer--copy-node ()
  "Copies current node as another path."
  (interactive)
  (let* ((current-path (nyaatree-buffer--get-filename-current-line))
         (buffer (find-buffer-visiting current-path))
         to-path
         msg)
    (unless (null current-path)
      (setq msg (format "Copy [%s] to: " (nyaatree-path--file-short-name current-path)))
      (setq to-path (read-file-name msg (file-name-directory current-path)))
      (if (file-directory-p current-path)
          (copy-directory current-path to-path)
        (copy-file current-path to-path))
      (nyaatree-buffer--refresh t)
      (message "Copy successful."))))

(defun nyaatree-buffer--select-file-node (file &optional recursive-p)
  "Select the node that corresponds to the FILE.
If RECURSIVE-P is non nil, find files will recursively."
  (let ((efile file)
        (iter-curr-dir nil)
        (file-node-find-p nil)
        (file-node-list nil))
    (unless (file-name-absolute-p efile)
      (setq efile (expand-file-name efile)))
    (setq iter-curr-dir efile)
    (catch 'return
      (while t
        (setq iter-curr-dir (nyaatree-path--updir iter-curr-dir))
        (push iter-curr-dir file-node-list)
        (when (nyaatree-path--file-equal-p iter-curr-dir nyaatree-buffer--start-node)
          (setq file-node-find-p t)
          (throw 'return nil))
        (let ((niter-curr-dir (file-remote-p iter-curr-dir 'localname)))
          (unless niter-curr-dir
            (setq niter-curr-dir iter-curr-dir))
          (when (nyaatree-path--file-equal-p niter-curr-dir "/")
            (setq file-node-find-p nil)
            (throw 'return nil)))))
    (when file-node-find-p
      (dolist (p file-node-list)
        (nyaatree-buffer--set-expand p t))
      (nyaatree-buffer--save-cursor-pos file)
      (nyaatree-buffer--refresh nil))))

(defun nyaatree-buffer--change-root (root-dir)
  "Change the tree root to ROOT-DIR."
  (let ((path root-dir)
        start-path)
    (unless (and (file-exists-p path)
                 (file-directory-p path))
      (throw 'error "The path is not a valid directory."))
    (setq start-path (expand-file-name (substitute-in-file-name path)))
    (setq nyaatree-buffer--start-node start-path)
    (cd start-path)
    (nyaatree-buffer--save-cursor-pos path nil)
    (nyaatree-buffer--refresh nil)))

(defun nyaatree-buffer--get-nodes-for-select-down-node (path)
  "Return the node list for the down dir selection."
  (if path
      (when (file-name-directory path)
        (if (nyaatree-buffer--expanded-node-p path)
            (nyaatree-buffer--get-nodes path)
          (nyaatree-buffer--get-nodes (file-name-directory path))))
    (nyaatree-buffer--get-nodes (file-name-as-directory nyaatree-buffer--start-node))))

(defun nyaatree-buffer--get-nodes-for-sibling (path)
  "Return the node list for the sibling selection. Return nil of no nodes can
be found.
The returned list is a directory list if path is a directory, otherwise it is
a file list."
  (when path
    (let ((nodes (nyaatree-buffer--get-nodes (file-name-directory path))))
      (if (file-directory-p path)
          (car nodes)
        (cdr nodes)))))

(defun nyaatree-buffer--sibling (path &optional previous)
  "Return the next sibling of node PATH.
If PREVIOUS is non-nil the previous sibling is returned."
  (let* ((nodes (nyaatree-buffer--get-nodes-for-sibling path)))
    (when nodes
      (let ((i (nyaatree-buffer--get-node-index path nodes))
            (l (length nodes)))
        (if i (nth (mod (+ i (if previous -1 1)) l) nodes))))))

(defun nyaatree-buffer--execute (arg &optional file-fn dir-fn)
  "Define the behaviors for keyboard event.
ARG is the parameter for command.
If FILE-FN is non-nil, it will executed when a file node.
If DIR-FN is non-nil, it will executed when a dir node."
  (interactive "P")
  (let* ((btn-full-path (nyaatree-buffer--get-filename-current-line))
         is-file-p
         enter-fn)
    (unless (null btn-full-path)
      (setq is-file-p (not (file-directory-p btn-full-path))
            enter-fn (if is-file-p file-fn dir-fn))
      (unless (null enter-fn)
        (funcall enter-fn btn-full-path arg)
        (run-hook-with-args
         'nyaatree-enter-hook
         (if is-file-p 'file 'directory)
         btn-full-path
         arg)))
    btn-full-path))

(defun nyaatree-buffer--set-show-hidden-file-p (show-p)
  "If SHOW-P is non-nil, show hidden nodes in tree."
  (setq nyaatree-buffer--show-hidden-file-p show-p)
  (nyaatree-buffer--refresh t))

(defun nyaatree-buffer--forward-line (n)
  "Move N lines forward in NyaaTree buffer."
  (forward-line (or n 1))
  (nyaatree-buffer--post-move))

;;
;; Mode-line methods
;;

(defun nyaatree-mode-line--compute-format (parent index ndirs nfiles)
  "Return a formated string to be used in the `nyaatree' mode-line."
  (let* ((nall (+ ndirs nfiles))
         (has-dirs (> ndirs 0))
         (has-files (> nfiles 0))
         (msg-index (when index (format "[%s/%s] " index nall)))
         (msg-ndirs (when has-dirs (format (if has-files " (D:%s" " (D:%s)") ndirs)))
         (msg-nfiles (when has-files (format (if has-dirs " F:%s)" " (F:%s)") nfiles)))
         (msg-directory (file-name-nondirectory (directory-file-name parent)))
         (msg-directory-max-length (- (window-width)
                                      (length msg-index)
                                      (length msg-ndirs)
                                      (length msg-nfiles))))
    (setq msg-directory (if (<= (length msg-directory) msg-directory-max-length)
                            msg-directory
                          (concat (substring msg-directory
                                             0 (- msg-directory-max-length 3))
                                  "...")))
    (propertize
     (decode-coding-string (concat msg-index msg-directory msg-ndirs msg-nfiles) 'utf-8)
     'help-echo (decode-coding-string parent 'utf-8))))

;;
;; Window methods
;;

(defun nyaatree-window--init (window buffer)
  "Make WINDOW a NyaaTree window.
NyaaTree buffer is BUFFER."
  (nyaatree-buffer--with-resizable-window
   (switch-to-buffer buffer)
   (set-window-parameter window 'no-delete-other-windows t)
   (set-window-dedicated-p window t))
  window)

(defun nyaatree-window--zoom (method)
  "Zoom the NyaaTree window, the METHOD should one of these options:
'maximize 'minimize 'zoom-in 'zoom-out."
  (nyaatree-buffer--unlock-width)
  (cond
   ((eq method 'maximize)
    (maximize-window))
   ((eq method 'minimize)
    (nyaatree-util--set-window-width (selected-window) nyaatree-window-width))
   ((eq method 'zoom-in)
    (shrink-window-horizontally 2))
   ((eq method 'zoom-out)
    (enlarge-window-horizontally 2)))
  (nyaatree-buffer--lock-width))

(defun nyaatree-window--minimize-p ()
  "Return non-nil when the NyaaTree window is minimize."
  (<= (window-width) nyaatree-window-width))

;;
;; Interactive functions
;;

(defun nyaatree-next-line (&optional count)
  "Move next line in NyaaTree buffer.
Optional COUNT argument, moves COUNT lines down."
  (interactive "p")
  (nyaatree-buffer--forward-line (or count 1)))

(defun nyaatree-previous-line (&optional count)
  "Move previous line in NyaaTree buffer.
Optional COUNT argument, moves COUNT lines up."
  (interactive "p")
  (nyaatree-buffer--forward-line (- (or count 1))))

;;;###autoload
(defun nyaatree-find (&optional path default-path)
  "Quick select node which specified PATH in NyaaTree.
If path is nil and no buffer file name, then use DEFAULT-PATH,"
  (interactive)
  (let* ((ndefault-path (if default-path default-path
                          (nyaatree-path--get-working-dir)))
         (npath (if path path
                  (or (buffer-file-name) ndefault-path)))
         (do-open-p nil))
    (if (and (not nyaatree-force-change-root)
             (not (nyaatree-global--file-in-root-p npath))
             (nyaatree-global--window-exists-p))
        (setq do-open-p (funcall nyaatree-confirm-change-root "File not found in root path, do you want to change root?"))
      (setq do-open-p t))
    (when do-open-p
      (nyaatree-global--open-and-find npath))
    (when nyaatree-auto-indent-point
      (nyaatree-point-auto-indent)))
  (nyaatree-global--select-window))

(defun nyaatree-click-changes-root-toggle ()
  "Toggle the variable nyaatree-click-changes-root.
If true, clicking on a directory will change the current root to
the directory instead of showing the directory contents."
  (interactive)
  (setq nyaatree-click-changes-root (not nyaatree-click-changes-root)))

(defun nyaatree-open-dir (full-path &optional arg)
  "Toggle fold a directory node.

FULL-PATH is the path of the directory.
ARG is ignored."
  (if nyaatree-click-changes-root
      (nyaatree-change-root)
    (progn
      (let ((new-state (nyaatree-buffer--toggle-expand full-path)))
        (nyaatree-buffer--refresh t)
        (when nyaatree-auto-indent-point
          (when new-state (forward-line 1))
          (nyaatree-point-auto-indent))))))


(defun nyaatree--expand-recursive (path state)
  "Set the state of children recursively.

The children of PATH will have state STATE."
  (let ((children (car (nyaatree-buffer--get-nodes path) )))
    (dolist (node children)
      (nyaatree-buffer--set-expand node state)
      (nyaatree--expand-recursive node state ))))

(defun nyaatree-open-dir-recursive (full-path &optional arg)  
  "Toggle fold a directory node recursively.

The children of the node will also be opened recursively.
FULL-PATH is the path of the directory.
ARG is ignored."
  (if nyaatree-click-changes-root
      (nyaatree-change-root)    
    (let ((new-state (nyaatree-buffer--toggle-expand full-path))
          (children (car (nyaatree-buffer--get-nodes full-path))))
      (dolist (node children)
        (nyaatree-buffer--set-expand node new-state)
        (nyaatree--expand-recursive node new-state))
      (nyaatree-buffer--refresh t))))

(defun nyaatree-open-dired (full-path &optional arg)
  "Open file or directory node in `dired-mode'.

FULL-PATH is the path of node.
ARG is same as `nyaatree-open-file'."
  (nyaatree-global--select-mru-window arg)
  (dired full-path))

(defun nyaatree-open-file (full-path &optional arg)
  "Open a file node.

FULL-PATH is the file path you want to open.
If ARG is an integer then the node is opened in a window selected via
`winum' or`window-numbering' (if available) according to the passed number.
If ARG is `|' then the node is opened in new vertically split window.
If ARG is `-' then the node is opened in new horizontally split window."
  (nyaatree-global--select-mru-window arg)
  (find-file full-path))

(defun nyaatree-open-file-vertical-split (full-path arg)
  "Open the current node is a vertically split window.
FULL-PATH and ARG are the same as `nyaatree-open-file'."
  (nyaatree-open-file full-path "|"))

(defun nyaatree-open-file-horizontal-split (full-path arg)
  "Open the current node is horizontally split window.
FULL-PATH and ARG are the same as `nyaatree-open-file'."
  (nyaatree-open-file full-path "-"))

(defun nyaatree-open-file-ace-window (full-path arg)
  "Open the current node in a window chosen by ace-window.
FULL-PATH and ARG are the same as `nyaatree-open-file'."
  (nyaatree-open-file full-path "a"))

(defun nyaatree-open-file-in-system-application ()
  "Open a file under point in the system application."
  (interactive)
  (call-process nyaatree-default-system-application nil 0 nil
                (nyaatree-buffer--get-filename-current-line)))

(defun nyaatree-change-root ()
  "Change root to current node dir.
If current node is a file, then it will do nothing.
If cannot find any node in current line, it equivalent to using `nyaatree-dir'."
  (interactive)
  (nyaatree-global--select-window)
  (let ((btn-full-path (nyaatree-buffer--get-filename-current-line)))
    (if (null btn-full-path)
        (call-interactively 'nyaatree-dir)
      (nyaatree-global--open-dir btn-full-path))))

(defun nyaatree-select-up-node ()
  "Select the parent directory of the current node. Change the root if
necessary. "
  (interactive)
  (nyaatree-global--select-window)
  (let* ((btn-full-path (nyaatree-buffer--get-filename-current-line))
         (btn-parent-dir (if btn-full-path (file-name-directory btn-full-path)))
         (root-slash (file-name-as-directory nyaatree-buffer--start-node)))
    (cond
     ((equal btn-parent-dir root-slash) (nyaatree-global--open-dir root-slash))
     (btn-parent-dir (nyaatree-find btn-parent-dir))
     (t (nyaatree-global--open-dir (file-name-directory
                               (directory-file-name root-slash)))))))

(defun nyaatree-select-down-node ()
  "Select an expanded directory or content directory according to the
current node, in this order:
- select the first expanded child node if the current node has one
- select the content of current node if it is expanded
- select the next expanded sibling if the current node is not expanded."
  (interactive)
  (let* ((btn-full-path (nyaatree-buffer--get-filename-current-line))
         (path (if btn-full-path btn-full-path nyaatree-buffer--start-node))
         (nodes (nyaatree-buffer--get-nodes-for-select-down-node path)))
    (when nodes
      (if (or (equal path nyaatree-buffer--start-node)
              (nyaatree-buffer--expanded-node-p path))
          ;; select the first expanded child node
          (let ((expanded-dir (catch 'break
                                (dolist (node (car nodes))
                                  (if (nyaatree-buffer--expanded-node-p node)
                                      (throw 'break node)))
                                nil)))
            (if expanded-dir
                (nyaatree-find expanded-dir)
              ;; select the directory content if needed
              (let ((dirs (car nodes))
                    (files (cdr nodes)))
                (if (> (length dirs) 0)
                    (nyaatree-find (car dirs))
                  (when (> (length files) 0)
                    (nyaatree-find (car files)))))))
        ;; select the next expanded sibling
        (let ((sibling (nyaatree-buffer--sibling path)))
          (while (and (not (nyaatree-buffer--expanded-node-p sibling))
                      (not (equal sibling path)))
            (setq sibling (nyaatree-buffer--sibling sibling)))
          (when (not (string< sibling path))
            ;; select next expanded sibling
            (nyaatree-find sibling)))))))

(defun nyaatree-select-next-sibling-node ()
  "Select the next sibling of current node.
If the current node is the last node then the first node is selected."
  (interactive)
  (let ((sibling (nyaatree-buffer--sibling (nyaatree-buffer--get-filename-current-line))))
    (when sibling (nyaatree-find sibling))))

(defun nyaatree-select-previous-sibling-node ()
  "Select the previous sibling of current node.
If the current node is the first node then the last node is selected."
  (interactive)
  (let ((sibling (nyaatree-buffer--sibling (nyaatree-buffer--get-filename-current-line) t)))
    (when sibling (nyaatree-find sibling))))

(defun nyaatree-create-node (filename)
  "Create a file or directory use specified FILENAME in current node."
  (interactive
   (let* ((current-dir (nyaatree-buffer--get-filename-current-line nyaatree-buffer--start-node))
          (current-dir (nyaatree-path--match-path-directory current-dir))
          (filename (read-file-name "Filename: " current-dir)))
     (if (file-directory-p filename)
         (setq filename (concat filename "/")))
     (list filename)))
  (catch 'rlt
    (let ((is-file nil))
      (when (= (length filename) 0)
        (throw 'rlt nil))
      (setq is-file (not (equal (substring filename -1) "/")))
      (when (file-exists-p filename)
        (message "File %S already exists." filename)
        (throw 'rlt nil))
      (when (and is-file
                 (funcall nyaatree-confirm-create-file (format "Do you want to create file %S ?"
                                                          filename)))
        ;; ensure parent directory exist before saving
        (mkdir (substring filename 0 (+ 1 (cl-position ?/ filename :from-end t))) t)
        ;; NOTE: create a empty file
        (write-region "" nil filename)
        (nyaatree-buffer--save-cursor-pos filename)
        (nyaatree-buffer--refresh nil)
        (if nyaatree-create-file-auto-open
            (find-file-other-window filename)))
      (when (and (not is-file)
                 (funcall nyaatree-confirm-create-directory (format "Do you want to create directory %S?"
                                                               filename)))
        (mkdir filename t)
        (nyaatree-buffer--save-cursor-pos filename)
        (nyaatree-buffer--refresh nil)))))

(defun nyaatree-delete-node ()
  "Delete current node."
  (interactive)
  (let* ((filename (nyaatree-buffer--get-filename-current-line))
         (buffer (find-buffer-visiting filename))
         (deleted-p nil)
         (trash delete-by-moving-to-trash))
    (catch 'end
      (if (null filename) (throw 'end nil))
      (if (not (file-exists-p filename)) (throw 'end nil))
      (if (not (funcall nyaatree-confirm-delete-file (format "Do you really want to delete %S?"
                                                        filename)))
          (throw 'end nil))
      (if (file-directory-p filename)
          ;; delete directory
          (progn
            (unless (nyaatree-path--has-subfile-p filename)
              (delete-directory filename nil trash)
              (setq deleted-p t)
              (throw 'end nil))
            (when (funcall nyaatree-confirm-delete-directory-recursively
                           (format "%S is a directory, delete it recursively?"
                                   filename))
              (when (funcall nyaatree-confirm-kill-buffers-for-files-in-directory
                             (format "kill buffers for files in directory %S?"
                                     filename))
                (nyaatree-util--kill-buffers-for-path filename))
              (delete-directory filename t trash)
              (setq deleted-p t)))
        ;; delete file
        (progn
          (delete-file filename trash)
          (when buffer
            (kill-buffer-ask buffer))
          (setq deleted-p t))))
    (when deleted-p
      (message "%S deleted." filename)
      (nyaatree-buffer--refresh t))
    filename))

(defun nyaatree-rename-node ()
  "Rename current node."
  (interactive)
  (nyaatree-buffer--rename-node))

(defun nyaatree-copy-node ()
  "Copy current node."
  (interactive)
  (nyaatree-buffer--copy-node))

(defun nyaatree-hidden-file-toggle ()
  "Toggle show hidden files."
  (interactive)
  (nyaatree-buffer--set-show-hidden-file-p (not nyaatree-buffer--show-hidden-file-p)))

(defun nyaatree-empty-fn ()
  "Used to bind the empty function to the shortcut."
  (interactive))

(defun nyaatree-refresh (&optional is-auto-refresh)
  "Refresh the NyaaTree buffer."
  (interactive)
  (if (eq (current-buffer) (nyaatree-global--get-buffer))
      (nyaatree-buffer--refresh t)
    (save-excursion
      (let ((cw (selected-window)))  ;; save current window
        (if is-auto-refresh
            (let ((origin-buffer-file-name (buffer-file-name)))
              (when (and (fboundp 'projectile-project-p)
                         (projectile-project-p)
                         (fboundp 'projectile-project-root))
                (nyaatree-global--open-dir (projectile-project-root))
                (nyaatree-find (projectile-project-root)))
              (nyaatree-find origin-buffer-file-name))
          (nyaatree-buffer--refresh t t))
        (recenter)
        (when (or is-auto-refresh nyaatree-toggle-window-keep-p)
          (select-window cw))))))

(defun nyaatree-stretch-toggle ()
  "Make the NyaaTree window toggle maximize/minimize."
  (interactive)
  (nyaatree-global--with-window
    (if (nyaatree-window--minimize-p)
        (nyaatree-window--zoom 'maximize)
      (nyaatree-window--zoom 'minimize))))

(defun nyaatree-collapse-all ()
  (interactive)
  "Collapse all expanded folders in the nyaatree buffer"
  (setq list-of-expanded-folders nyaatree-buffer--expanded-node-list)
  (dolist (folder list-of-expanded-folders)
    (nyaatree-buffer--toggle-expand folder)
    (nyaatree-buffer--refresh t)
    )
  )
;;;###autoload
(defun nyaatree-projectile-action ()
  "Integration with `Projectile'.

Usage:
    (setq projectile-switch-project-action 'nyaatree-projectile-action).

When running `projectile-switch-project' (C-c p p), `nyaatree' will change root
automatically."
  (interactive)
  (cond
   ((fboundp 'projectile-project-root)
    (nyaatree-dir (projectile-project-root)))
   (t
    (error "Projectile is not available"))))

;;;###autoload
(defun nyaatree-toggle ()
  "Toggle show the NyaaTree window."
  (interactive)
  (if (nyaatree-global--window-exists-p)
      (nyaatree-hide)
    (nyaatree-show)))

;;;###autoload
(defun nyaatree-show ()
  "Show the NyaaTree window."
  (interactive)
  (let ((cw (selected-window))
        (path (buffer-file-name)))  ;; save current window and buffer
    (if nyaatree-smart-open
        (progn
          (when (and (fboundp 'projectile-project-p)
                     (projectile-project-p)
                     (fboundp 'projectile-project-root))
            (nyaatree-dir (projectile-project-root)))
          (nyaatree-find path))
      (nyaatree-global--open))
    (nyaatree-global--select-window)
    (when nyaatree-toggle-window-keep-p
      (select-window cw))))

;;;###autoload
(defun nyaatree-hide ()
  "Close the NyaaTree window."
  (interactive)
  (if (nyaatree-global--window-exists-p)
      (delete-window nyaatree-global--window)))

;;;###autoload
(defun nyaatree-dir (path)
  "Show the NyaaTree window, and change root to PATH."
  (interactive "DDirectory: ")
  (nyaatree-global--open-dir path)
  (nyaatree-global--select-window))

;;;###autoload
(defalias 'nyaatree 'nyaatree-show "Show the NyaaTree window.")

;;
;; backward compatible
;;

(defun nyaatree-bc--make-obsolete-message (from to)
  (message "Warning: `%S' is obsolete. Use `%S' instead." from to))

(defun nyaatree-buffer--enter-file (path)
  (nyaatree-bc--make-obsolete-message 'nyaatree-buffer--enter-file 'nyaatree-open-file))

(defun nyaatree-buffer--enter-dir (path)
  (nyaatree-bc--make-obsolete-message 'nyaatree-buffer--enter-dir 'nyaatree-open-dir))

(defun nyaatree-enter (&optional arg)
  "NyaaTree typical open event.
ARG are the same as `nyaatree-open-file'."
  (interactive "P")
  (nyaatree-buffer--execute arg 'nyaatree-open-file 'nyaatree-open-dir))

(defun nyaatree-quick-look (&optional arg)
  "Quick Look like NyaaTree open event.
ARG are the same as `nyaatree-open-file'."
  (interactive "P")
  (nyaatree-enter arg)
  (nyaatree-global--select-window))

(defun nyaatree-enter-vertical-split ()
  "NyaaTree open event, file node will opened in new vertically split window."
  (interactive)
  (nyaatree-buffer--execute nil 'nyaatree-open-file-vertical-split 'nyaatree-open-dir))

(defun nyaatree-enter-horizontal-split ()
  "NyaaTree open event, file node will opened in new horizontally split window."
  (interactive)
  (nyaatree-buffer--execute nil 'nyaatree-open-file-horizontal-split 'nyaatree-open-dir))

(defun nyaatree-enter-ace-window ()
  "NyaaTree open event, file node will be opened in window chosen by ace-window."
  (interactive)
  (nyaatree-buffer--execute nil 'nyaatree-open-file-ace-window 'nyaatree-open-dir))

(defun nyaatree-copy-filepath-to-yank-ring ()
  "Nyaatree convenience interactive function: file node path will be added to the kill ring."
  (interactive)
  (kill-new (nyaatree-buffer--get-filename-current-line)))

(defun nyaatree-split-window-sensibly (&optional window)
  "An nyaatree-version of split-window-sensibly,
which is used to fix issue #209.
(setq split-window-preferred-function 'nyaatree-split-window-sensibly)"
  (let ((window (or window (selected-window))))
    (or (split-window-sensibly window)
        (and (get-buffer-window nyaatree-buffer-name)
             (not (window-minibuffer-p window))
             ;; If WINDOW is the only window on its frame
             ;; (or only include Nyaa window) and is not the
             ;; minibuffer window, try to split it vertically disregarding
             ;; the value of `split-height-threshold'.
             (let ((split-height-threshold 0))
               (when (window-splittable-p window)
                 (with-selected-window window
                   (split-window-below))))))))

(provide 'nyaatree)
;;; nyaatree.el ends here

