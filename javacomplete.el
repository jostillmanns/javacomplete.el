(require 's)
(require 'json)
(require 'ido)

(defcustom javacomplete-begin-after-member-access t
  "When non-nil, automatic completion will start whenever the current
symbol is preceded by a \".\", ignoring `company-minimum-prefix-length'."
  :group 'javacomplete
  :type 'boolean)

(defun javacomplete--clear-buffer()
  "clear completion buffer"
  (when (get-buffer "*JAVA COMPLETION*")
    (save-current-buffer
      (set-buffer "*JAVA COMPLETION*")
      (delete-region (point-min) (point-max)))))

(defun javacomplete--at-empty-statement()
  "return t if looking at an empty statement"
  (save-excursion
    (let ((pos (point))
	  (last-sep (+ 1 (re-search-backward "[;{}]"))))
      (let ((isempty (s-equals? (s-trim (buffer-substring last-sep pos)) "")))
	(cond (isempty t)
	      ((not isempty) nil))))))

(defun javacomplete--begin-statement ()
  "uses c-mode beginning of statement"
  (save-excursion
    (c-beginning-of-statement-1)
    (point)))

(defun javacomplete--inside-for ()
  (or (looking-back "for[ ]*([^;{}]*;[^;{}]*")
      (looking-back "for[ ]*([^;{}]*;[^;{}]*;[^;{}]*")))

(defun javacomplete--begin-of-outer-statement ()
  "reads through parentheses"
  (if (not (javacomplete--inside-for))
      (c-beginning-of-statement 1)
    (search-backward "for")))

(defun javacomplete--begin-of-outer-statement-p ()
  ""
  (if (looking-back "[};][ \n\t]*")
      (point)
    (save-excursion
    (javacomplete--begin-of-outer-statement)
    (when (looking-at "{") (forward-char 2))
    (point))))

(defun javacomplete--end-of-outer-statement ()
  "reads through parentheses"
    (c-end-of-statement 1)
    (when (looking-back "}\\s-*") (backward-char 2))
    (when (looking-back "{") (backward-char 1)))

(defun javacomplete--end-of-outer-statement-p ()
  (save-excursion
    (while (looking-at ")")
      (forward-char))
    (if (or (looking-at "[ \n\t]*\\(if\\|for\\|while\\|try\\|switch\\)[ ]*(")
	    (looking-at "[ \n\t]*\\(public\\|private\\|protected\\|class\\)[ ]+")
	    (looking-at "[ \n\t]*\\(try\\)[ ]*{"))
	(point)

      (javacomplete--end-of-outer-statement)
      (point))))

(defun javacomplete--grab-symbol ()
  (save-excursion
    (let ((end (point))
	  (start (javacomplete--begin-statement))
	  (isempty (javacomplete--at-empty-statement)))
      (cond (isempty "")
	    ((not isempty) (s-trim (buffer-substring-no-properties start end)))))))

(defun javacomplete--read-candidates ()
  "parse java completion candidates"
  (let ((el)
	(els (javacomplete--raw-candidates))
	(res '()))
    (dolist (el els res)
      (add-to-ordered-list 'res (nth 0 (s-split "!" el)))
      (add-text-properties
       0
       (- (length (car res)) 1)
       (list 'type (nth 1 (s-split "!" el)) 'parameters (nth 2 (s-split "!" el)))
       (car res)))
    res))

(defun javacomplete--raw-candidates ()
  "read completion candidates from output buffer"
  (save-current-buffer
    (set-buffer "*JAVA COMPLETION*")
    (goto-char (point-min))
    (let ((num (buffer-substring-no-properties (point) (point-at-eol)))
	  (candidates))
      (when (> (string-to-int num) 0)
	(set 'candidates (s-lines
			  (buffer-substring-no-properties
			   (javacomplete--point-nth-line 2)
			   (javacomplete--point-nth-line (+ 1 (string-to-int num)) t))))
	(goto-char (point-min))
	candidates))))

(defun javacomplete--point-nth-line (line &optional eol)
  "return point at nth line"
  (save-excursion
    (goto-char (point-min))
    (dotimes (number (- line 1))
      (next-line))
    (forward-line 0)
    (if eol
	(point-at-eol)
      (point))))

(defun javacomplete--candidates (arg)
  "retrieve java completion candidates"
  (javacomplete--clear-buffer)
  (let ((type-prefix (s-chop-suffix arg (javacomplete--grab-symbol))))
    (javacomplete--call-process-socket type-prefix arg "complete")
    (javacomplete--read-candidates)))

(defun javacomplete--current-line ()
  "current column equivalent"
  (count-lines 1 (point)))

(defun javacomplete--begin-of-decl-point()
  (save-excursion
    (c-beginning-of-decl-1)
    (point)))

(defun javacomplete--create-process ()
  "create process"
  (make-network-process
   :name "javacomplete"
   :service "/tmp/javacomplete.sock"
   :family 'local
   :buffer "*JAVA COMPLETION*"))

(defun javacomplete--create-request (type-prefix prefix api)
  "initate request"
  (list
   :file (buffer-file-name)
   :expression type-prefix
   :prefix prefix
   :apicall api
   :line (javacomplete--current-line)
   :buffer (s-concat (buffer-substring-no-properties (point-min) (javacomplete--begin-of-outer-statement-p))
		     (buffer-substring-no-properties (javacomplete--end-of-outer-statement-p) (point-max)))))

(defun javacomplete-add-import ()
  "replace word at point with the fully qualified class name"
  (interactive)
  (let ((request (list
		  :file (buffer-file-name)
		  :expression (thing-at-point 'word)
		  :prefix "foo"
		  :apicall "addimport"
		  :line 0
		  :buffer "foo"))
	(process (javacomplete--create-process)))
    (javacomplete--clear-buffer)
    (process-send-string process (json-encode request))
    (accept-process-output process 1))

    (when (not (eq nil (javacomplete--raw-candidates)))
      (let ((import (progn (if (eq 1 (length (javacomplete--raw-candidates)))
			       (car (javacomplete--raw-candidates))
			     (ido-completing-read "select import" (javacomplete--raw-candidates)))))
		    (point-at-bow (save-excursion (backward-word)(point)))
		    (point-at-eow (save-excursion (forward-word) (point))))
      (delete-region point-at-bow point-at-eow)
      (insert import))))

(defun javacomplete-signature()
  "get signatur for word at point"
  (interactive)
  (let ((request (list
		  :file (buffer-file-name)
		  :expression (save-excursion
				(when (eq nil (looking-at "\\>"))
				  (forward-word))
				(s-chop-suffix (thing-at-point 'word) (javacomplete--grab-symbol)))
		  :prefix (thing-at-point 'word)
		  :apicall "definition"
		  :line (javacomplete--current-line)
		  :buffer (buffer-substring-no-properties (point-min) (point-max))))
	(process (javacomplete--create-process)))
    (javacomplete--clear-buffer)
    (process-send-string process (json-encode request))
    (accept-process-output process 1))

  (let ((definition (javacomplete--read-candidates))
	(res ""))
    (when (not (eq nil definition))
      (dolist (d definition res)
	(set 'res (s-append res (format "%s %s%s\n"
			 (get-text-property 0 'type d)
			 (substring-no-properties d)
			 (get-text-property 0 'parameters d)))))
      (message res))))


(defun javacomplete-clean-imports ()
  ""
  (let ((request (json-encode (javacomplete--create-request "" "" "cleanimports")))
	(process (javacomplete--create-process)))
    (process-send-string process request)))

(defun javacomplete--prefix ()
  (if javacomplete-begin-after-member-access
      (company-grab-symbol-cons "\\." 1)
    (company-grab-symbol)))

(defun javacomplete--call-process-socket (type-prefix prefix api)
  "write on javacomplete socket"
  (let
      ((request (json-encode (javacomplete--create-request type-prefix prefix api)))
       (process (javacomplete--create-process)))
    (process-send-string process request)
    (accept-process-output process 0 100)))

(defun javacomplete--annotation (arg)
  (let ((annotation "")
	(parameters (get-text-property 0 'parameters arg))
	(type (get-text-property 0 'type arg)))
    (when (not (string-equal "" parameters))
      (setq annotation (s-append annotation parameters)))
    (when (not (string-equal "" type))
      (setq annotation (s-append (format " : %s" type) annotation)))
    annotation))

(defun company-javacomplete (command &optional arg &rest ignored)
  (interactive (list 'interactive))
  (case command
    (interactive (company-begin-backend 'company-javacomplete))
    (prefix (and (derived-mode-p 'java-mode 'jde-mode)
		 (or (javacomplete--prefix) 'stop)))
    (candidates (javacomplete--candidates arg))
    (meta (format "%s" arg))
    (annotation (javacomplete--annotation arg))))

(provide 'javacomplete)
