;;; flycheck-package.el --- Flycheck checker for elisp package metadata  -*- lexical-binding: t; -*-

;; Copyright (C) 2014  Steve Purcell

;; Author: Steve Purcell <steve@sanityinc.com>
;; Keywords: lisp
;; Version: DEV
;; Package-Requires: ((cl-lib "0.5") (flycheck "0.22-cvs1"))

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

;; Provides feedback via flycheck about issues with the package metadata
;; of a file, e.g. the package dependencies it requires.

;; To enable, use something like this:

;;    (eval-after-load 'flycheck
;;      '(flycheck-package-setup))

;; Checks will currently be enabled only if a "Package-Requires:" header
;; is present in the file.

;;; Code:

(require 'flycheck)
(require 'cl-lib)
(require 'package)

(flycheck-define-generic-checker 'emacs-lisp-package
  "A checker for \"Package-Requires\" headers."
  :start #'emacs-lisp-package-start
  :modes '(emacs-lisp-mode))

;; Disclaimer: this is currently very hacky and will be cleaned up as & when it grows in scope.
;;
;; Once this is more useful, the plan is to extract the checks into a separate
;; `package-lint.el', which can then be used by this checker and also by
;; MELPA -- this will probably be essential in order to check multi-file packages
;; helpfully anyway.
;;
;; Checks to add in the short term:
;;
;; - WARN: If `lexical-binding' is declared, then `(emacs "24.something")' should be a dependency
;; - WARN: Stable version numbers should be used in dependencies when possible
;; - WARN: "0" dependency version are discouraged
;;
;; Further checks for a future package-lint.el, some of which are currently
;; performed by other flycheck checkers:
;;
;; - WARN: header line formatting / length / capitalisation / use of "Emacs"
;; - trailing line presence / formatting
;; - Version header presence
;; - URL header presence
;; - WARN: suggest cl-lib vs cl
;; - use of non-snapshot dependencies
;; - keywords separated by only spaces
;; - use of non-standard keywords
;; - non-use of standard keywords
;; - checkdoc failures for interactive functions / defcustoms
;; - presence of :group for each defcustom / defgroup
;; - trailing whitespace?
;; - themes which aren't in a matching *-theme.el file
;; - files lacking a (provide ...) which matches their name
;; - use of unsafe local variables
;; - use of emacs version dependencies
;; - using `lexical-binding: t` without an "emacs 24" dependency
;; - `lexical-binding: t` set on a line other than the first
;; - local variable set in header line
;; - non-empty commentary
;; - using commentary to talk about load[- ]path and installation
;; - lack of autoloads
;; - references to README files which won't be bundled in a package
;; - dependencies on unavailable packages / versions
;; - use of CamelCase identifiers
(defun emacs-lisp-package-start (checker callback)
  "Flycheck start function for checking metadata used by package.el."
  (let (errors)
    (save-excursion
      (widen)
      (goto-char (point-min))
      (when (re-search-forward "^;+ *Package-Requires *: *\\(.*?\\) *$" nil t)
        (match-string 1)
        ;; Behold this horrible code. This is why monads, folks.
        (let* ((line-no (line-number-at-pos))
               (deps (match-string 1))
               (parse-result ))
          (condition-case err
              (cl-destructuring-bind (parsed-deps . parse-end-pos)
                  (read-from-string deps)
                (unless (eq parse-end-pos (length deps))
                  (push (list line-no 0 'error (format "More than one expression provided")) errors))
                (dolist (entry parsed-deps)
                  (if (and (listp entry)
                           (= (length entry) 2)
                           (symbolp (car entry))
                           (stringp (nth 1 entry)))
                      (let ((package-name (car entry))
                            (package-version (nth 1 entry)))
                        (unless (ignore-errors (version-to-list package-version))
                          (push (list line-no 0 'error (format "%S is not a valid version string: see version-to-string" package-version)) errors))
                        (unless (or (eq 'emacs package-name)
                                    (assq package-name package-archive-contents))
                          (push (list line-no 0 'error (format "Package %S is unknown in the current package list." package-name)) errors)))
                    (push (list line-no 0 'error (format "Expected (package-name \"version-num\"), but found %S" entry)) errors))))
            (error
             (push (list line-no 0 'error (format "Couldn't parse \"Package-Requires\" header: %s" (error-message-string err))) errors)
             (cons nil 0)))
          (condition-case err
              (package-buffer-info)
            (error
             (push (list 0 0 'warning (format "package.el cannot parse this buffer: %s" (error-message-string err))) errors)
             nil))

          ))
      (funcall callback 'finished
               (mapcar (lambda (e) (apply #'flycheck-error-new-at (append e (list :checker checker)))) errors))
      )))

;;;###autoload
(defun flycheck-package-setup ()
  "Setup flycheck-package.
Add `flycheck-emacs-lisp-package' to `flycheck-checkers'."
  (interactive)
  (add-to-list 'flycheck-checkers 'emacs-lisp-package))


(provide 'flycheck-package)
;;; flycheck-package.el ends here