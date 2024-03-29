;;; org-odt.el --- OpenDocumentText export for Org-mode

;; Copyright (C) 2010-2011 Jambunathan <kjambunathan at gmail dot com>

;; Author: Jambunathan K <kjambunathan at gmail dot com>
;; Keywords: outlines, hypermedia, calendar, wp
;; Homepage: http://orgmode.org
;;
;; This file is not (yet) part of GNU Emacs.
;; However, it is distributed under the same license.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:

;;; Code:
(eval-when-compile (require 'cl))
(require 'org-lparse)

(defgroup org-export-odt nil
  "Options specific for ODT export of Org-mode files."
  :tag "Org Export ODT"
  :group 'org-export)

(defun org-odt-end-export ()
  (org-odt-fixup-label-references)

  ;; remove empty paragraphs
  (goto-char (point-min))
  (while (re-search-forward
	  "<text:p\\( text:style-name=\"Text_20_body\"\\)?>[ \r\n\t]*</text:p>"
	  nil t)
    (replace-match ""))
  (goto-char (point-min))

  ;; Convert whitespace place holders
  (goto-char (point-min))
  (let (beg end n)
    (while (setq beg (next-single-property-change (point) 'org-whitespace))
      (setq n (get-text-property beg 'org-whitespace)
	    end (next-single-property-change beg 'org-whitespace))
      (goto-char beg)
      (delete-region beg end)
      (insert (format "<span style=\"visibility:hidden;\">%s</span>"
		      (make-string n ?x)))))

  ;; Remove empty lines at the beginning of the file.
  (goto-char (point-min))
  (when (looking-at "\\s-+\n") (replace-match ""))

  ;; Remove display properties
  (remove-text-properties (point-min) (point-max) '(display t)))

(defvar org-odt-suppress-xref nil)
(defconst org-export-odt-special-string-regexps
  '(("\\\\-" . "&#x00ad;\\1")		; shy
    ("---\\([^-]\\)" . "&#x2014;\\1")	; mdash
    ("--\\([^-]\\)" . "&#x2013;\\1")	; ndash
    ("\\.\\.\\." . "&#x2026;"))		; hellip
  "Regular expressions for special string conversion.")

(defconst org-odt-lib-dir (file-name-directory load-file-name))
(defconst org-odt-data-dir
  (let ((dir1 (expand-file-name "../odt" org-odt-lib-dir))	   ; git
	(dir2 (expand-file-name "./" org-odt-lib-dir)))		   ; elpa
    (cond
     ((file-directory-p dir1) dir1)
     ((file-directory-p dir2) dir2)
     (t (error "Cannot find factory styles file. Check package dir layout"))))
  "Directory that holds auxiliary files used by the ODT exporter.

The 'styles' subdir contains the following xml files -
 'OrgOdtStyles.xml' and 'OrgOdtContentTemplate.xml' - which are
 used as factory settings of `org-export-odt-styles-file' and
 `org-export-odt-content-template-file'.

The 'etc/schema' subdir contains rnc files for validating of
OpenDocument xml files.")

(defvar org-odt-file-extensions
  '(("odt" . "OpenDocument Text")
    ("ott" . "OpenDocument Text Template")
    ("odm" . "OpenDocument Master Document")
    ("ods" . "OpenDocument Spreadsheet")
    ("ots" . "OpenDocument Spreadsheet Template")
    ("odg" . "OpenDocument Drawing (Graphics)")
    ("otg" . "OpenDocument Drawing Template")
    ("odp" . "OpenDocument Presentation")
    ("otp" . "OpenDocument Presentation Template")
    ("odi" . "OpenDocument Image")
    ("odf" . "OpenDocument Formula")
    ("odc" . "OpenDocument Chart")
    ("doc" . "Microsoft Text")
    ("docx" . "Microsoft Text")
    ("xls" . "Microsoft Spreadsheet")
    ("xlsx" . "Microsoft Spreadsheet")
    ("ppt" . "Microsoft Presentation")
    ("pptx" . "Microsoft Presentation")))

(defvar org-odt-ms-file-extensions
  '(("doc" . "Microsoft Text")
    ("docx" . "Microsoft Text")
    ("xls" . "Microsoft Spreadsheet")
    ("xlsx" . "Microsoft Spreadsheet")
    ("ppt" . "Microsoft Presentation")
    ("pptx" . "Microsoft Presentation")))

;; RelaxNG validation of OpenDocument xml files
(eval-after-load 'rng-nxml
  '(setq rng-nxml-auto-validate-flag t))

(eval-after-load 'rng-loc
  '(add-to-list 'rng-schema-locating-files
		(expand-file-name "etc/schema/schemas.xml" org-odt-data-dir)))

(mapc
 (lambda (desc)
   ;; Let Org open all OpenDocument files using system-registered app
   (add-to-list 'org-file-apps
		(cons (concat  "\\." (car desc) "\\'") 'system))
   ;; Let Emacs open all OpenDocument files in archive mode
   (add-to-list 'auto-mode-alist
		(cons (concat  "\\." (car desc) "\\'") 'archive-mode)))
 org-odt-file-extensions)

(mapc
 (lambda (desc)
   ;; Let Org open all Microsoft files using system-registered app
   (add-to-list 'org-file-apps
		(cons (concat  "\\." (car desc) "\\'") 'system)))
 org-odt-ms-file-extensions)

;; register the odt exporter with the pre-processor
(add-to-list 'org-export-backends 'odt)

;; register the odt exporter with org-lparse library
(org-lparse-register-backend 'odt)

(defun org-odt-unload-function ()
  (org-lparse-unregister-backend 'odt)
  (remove-hook 'org-export-preprocess-after-blockquote-hook
	       'org-export-odt-preprocess-latex-fragments)
  nil)

(defcustom org-export-odt-content-template-file nil
  "Template file for \"content.xml\".
The exporter embeds the exported content just before
\"</office:text>\" element.

If unspecified, the file named \"OrgOdtContentTemplate.xml\"
under `org-odt-data-dir' is used."
  :type 'file
  :group 'org-export-odt)

(defcustom org-export-odt-styles-file nil
  "Default styles file for use with ODT export.
Valid values are one of:
1. nil
2. path to a styles.xml file
3. path to a *.odt or a *.ott file
4. list of the form (ODT-OR-OTT-FILE (FILE-MEMBER-1 FILE-MEMBER-2
...))

In case of option 1, an in-built styles.xml is used. See
`org-odt-data-dir' for more information.

In case of option 3, the specified file is unzipped and the
styles.xml embedded therein is used.

In case of option 4, the specified ODT-OR-OTT-FILE is unzipped
and FILE-MEMBER-1, FILE-MEMBER-2 etc are copied in to the
generated odt file.  Use relative path for specifying the
FILE-MEMBERS.  styles.xml must be specified as one of the
FILE-MEMBERS.

Use options 1, 2 or 3 only if styles.xml alone suffices for
achieving the desired formatting.  Use option 4, if the styles.xml
references additional files like header and footer images for
achieving the desired formattting.

Use \"#+ODT_STYLES_FILE: ...\" directive to set this variable on
a per-file basis.  For example,

#+ODT_STYLES_FILE: \"/path/to/styles.xml\" or
#+ODT_STYLES_FILE: (\"/path/to/file.ott\" (\"styles.xml\" \"image/hdr.png\"))."
  :group 'org-export-odt
  :type
  '(choice
    (const :tag "Factory settings" nil)
    (file :must-match t :tag "styles.xml")
    (file :must-match t :tag "ODT or OTT file")
    (list :tag "ODT or OTT file + Members"
	  (file :must-match t :tag "ODF Text or Text Template file")
	  (cons :tag "Members"
		(file :tag "	Member" "styles.xml")
		(repeat (file :tag "Member"))))))

(eval-after-load 'org-exp
  '(add-to-list 'org-export-inbuffer-options-extra
		'("ODT_STYLES_FILE" :odt-styles-file)))

(defconst org-export-odt-tmpdir-prefix "%s-")
(defconst org-export-odt-bookmark-prefix "OrgXref.")

(defvar org-export-odt-embed-images t
  "Should the images be copied in to the odt file or just linked?")

(defvar org-export-odt-inline-images 'maybe) ; counterpart of
					     ; `org-export-html-inline-images'

(defcustom org-export-odt-inline-image-extensions
  '("png" "jpeg" "jpg" "gif")
  "Extensions of image files that can be inlined into HTML."
  :type '(repeat (string :tag "Extension"))
  :group 'org-export-odt)

(defcustom org-export-odt-pixels-per-inch display-pixels-per-inch
  ;; FIXME add docstring
  ""
  :type 'float
  :group 'org-export-odt)

(defvar org-export-odt-default-org-styles-alist
  '((paragraph . ((default . "Text_20_body")
		  (fixedwidth . "OrgFixedWidthBlock")
		  (verse . "OrgVerse")
		  (quote . "Quotations")
		  (blockquote . "Quotations")
		  (center . "OrgCenter")
		  (left . "OrgLeft")
		  (right . "OrgRight")
		  (title . "Heading_20_1.title")
		  (footnote . "Footnote")
		  (src . "OrgSrcBlock")
		  (illustration . "Illustration")
		  (table . "Table")
		  (definition-term . "Text_20_body_20_bold")
		  (horizontal-line . "Horizontal_20_Line")))
    (character . ((bold . "Bold")
		  (emphasis . "Emphasis")
		  (code . "OrgCode")
		  (verbatim . "OrgCode")
		  (strike . "Strikethrough")
		  (underline . "Underline")
		  (subscript . "OrgSubscript")
		  (superscript . "OrgSuperscript")))
    (list . ((ordered . "OrgNumberedList")
	     (unordered . "OrgBulletedList")
	     (description . "OrgDescriptionList"))))
  "Default styles for various entities.")

(defvar org-export-odt-org-styles-alist org-export-odt-default-org-styles-alist)
(defun org-odt-get-style-name-for-entity (category &optional entity)
  (let ((entity (or entity 'default)))
    (or
     (cdr (assoc entity (cdr (assoc category
				    org-export-odt-org-styles-alist))))
     (cdr (assoc entity (cdr (assoc category
				    org-export-odt-default-org-styles-alist))))
     (error "Cannot determine style name for entity %s of type %s"
	    entity category))))

(defcustom org-export-odt-preferred-output-format nil
  "Automatically post-process to this format after exporting to \"odt\".
Interactive commands `org-export-as-odt' and
`org-export-as-odt-and-open' export first to \"odt\" format and
then use `org-export-odt-convert-process' to convert the
resulting document to this format.  During customization of this
variable, the list of valid values are populated based on
`org-export-odt-convert-capabilities'."
  :group 'org-export-odt
  :type '(choice :convert-widget
		 (lambda (w)
		   (apply 'widget-convert (widget-type w)
			  (eval (car (widget-get w :args)))))
		 `((const :tag "None" nil)
		   ,@(mapcar (lambda (c)
			       `(const :tag ,c ,c))
			     (org-lparse-reachable-formats "odt")))))

;;;###autoload
(defun org-export-as-odt-and-open (arg)
  "Export the outline as ODT and immediately open it with a browser.
If there is an active region, export only the region.
The prefix ARG specifies how many levels of the outline should become
headlines.  The default is 3.  Lower levels will become bulleted lists."
  (interactive "P")
  (org-lparse-and-open
   (or org-export-odt-preferred-output-format "odt") "odt" arg))

;;;###autoload
(defun org-export-as-odt-batch ()
  "Call the function `org-lparse-batch'.
This function can be used in batch processing as:
emacs   --batch
        --load=$HOME/lib/emacs/org.el
        --eval \"(setq org-export-headline-levels 2)\"
        --visit=MyFile --funcall org-export-as-odt-batch"
  (org-lparse-batch "odt"))

;;;###autoload
(defun org-export-as-odt-to-buffer (arg)
  "Call `org-lparse-odt` with output to a temporary buffer.
No file is created.  The prefix ARG is passed through to `org-lparse-to-buffer'."
  (interactive "P")
  (org-lparse-to-buffer "odt" arg))

;;;###autoload
(defun org-replace-region-by-odt (beg end)
  "Assume the current region has org-mode syntax, and convert it to ODT.
This can be used in any buffer.  For example, you could write an
itemized list in org-mode syntax in an ODT buffer and then use this
command to convert it."
  (interactive "r")
  (org-replace-region-by "odt" beg end))

;;;###autoload
(defun org-export-region-as-odt (beg end &optional body-only buffer)
  "Convert region from BEG to END in org-mode buffer to ODT.
If prefix arg BODY-ONLY is set, omit file header, footer, and table of
contents, and only produce the region of converted text, useful for
cut-and-paste operations.
If BUFFER is a buffer or a string, use/create that buffer as a target
of the converted ODT.  If BUFFER is the symbol `string', return the
produced ODT as a string and leave not buffer behind.  For example,
a Lisp program could call this function in the following way:

  (setq odt (org-export-region-as-odt beg end t 'string))

When called interactively, the output buffer is selected, and shown
in a window.  A non-interactive call will only return the buffer."
  (interactive "r\nP")
  (org-lparse-region "odt" beg end body-only buffer))

;;; org-export-as-odt
;;;###autoload
(defun org-export-as-odt (arg &optional hidden ext-plist
			      to-buffer body-only pub-dir)
  "Export the outline as a OpenDocumentText file.
If there is an active region, export only the region.  The prefix
ARG specifies how many levels of the outline should become
headlines.  The default is 3.  Lower levels will become bulleted
lists.  HIDDEN is obsolete and does nothing.
EXT-PLIST is a property list with external parameters overriding
org-mode's default settings, but still inferior to file-local
settings.  When TO-BUFFER is non-nil, create a buffer with that
name and export to that buffer.  If TO-BUFFER is the symbol
`string', don't leave any buffer behind but just return the
resulting XML as a string.  When BODY-ONLY is set, don't produce
the file header and footer, simply return the content of
<body>...</body>, without even the body tags themselves.  When
PUB-DIR is set, use this as the publishing directory."
  (interactive "P")
  (org-lparse (or org-export-odt-preferred-output-format "odt")
	      "odt" arg hidden ext-plist to-buffer body-only pub-dir))

(defvar org-odt-entity-control-callbacks-alist
  `((EXPORT
     . (org-odt-begin-export org-odt-end-export))
    (DOCUMENT-CONTENT
     . (org-odt-begin-document-content org-odt-end-document-content))
    (DOCUMENT-BODY
     . (org-odt-begin-document-body org-odt-end-document-body))
    (TOC
     . (org-odt-begin-toc org-odt-end-toc))
    (ENVIRONMENT
     . (org-odt-begin-environment org-odt-end-environment))
    (FOOTNOTE-DEFINITION
     . (org-odt-begin-footnote-definition org-odt-end-footnote-definition))
    (TABLE
     . (org-odt-begin-table org-odt-end-table))
    (TABLE-ROWGROUP
     . (org-odt-begin-table-rowgroup org-odt-end-table-rowgroup))
    (LIST
     . (org-odt-begin-list org-odt-end-list))
    (LIST-ITEM
     . (org-odt-begin-list-item org-odt-end-list-item))
    (OUTLINE
     . (org-odt-begin-outline org-odt-end-outline))
    (OUTLINE-TEXT
     . (org-odt-begin-outline-text org-odt-end-outline-text))
    (PARAGRAPH
     . (org-odt-begin-paragraph org-odt-end-paragraph)))
  "")

(defvar org-odt-entity-format-callbacks-alist
  `((EXTRA-TARGETS . org-lparse-format-extra-targets)
    (ORG-TAGS . org-lparse-format-org-tags)
    (SECTION-NUMBER . org-lparse-format-section-number)
    (HEADLINE . org-odt-format-headline)
    (TOC-ENTRY . org-odt-format-toc-entry)
    (TOC-ITEM . org-odt-format-toc-item)
    (TAGS . org-odt-format-tags)
    (SPACES . org-odt-format-spaces)
    (TABS . org-odt-format-tabs)
    (LINE-BREAK . org-odt-format-line-break)
    (FONTIFY . org-odt-format-fontify)
    (TODO . org-lparse-format-todo)
    (LINK . org-odt-format-link)
    (INLINE-IMAGE . org-odt-format-inline-image)
    (ORG-LINK . org-odt-format-org-link)
    (HEADING . org-odt-format-heading)
    (ANCHOR . org-odt-format-anchor)
    (TABLE . org-lparse-format-table)
    (TABLE-ROW . org-odt-format-table-row)
    (TABLE-CELL . org-odt-format-table-cell)
    (FOOTNOTES-SECTION . ignore)
    (FOOTNOTE-REFERENCE . org-odt-format-footnote-reference)
    (HORIZONTAL-LINE . org-odt-format-horizontal-line)
    (COMMENT . org-odt-format-comment)
    (LINE . org-odt-format-line)
    (ORG-ENTITY . org-odt-format-org-entity))
  "")

;;;_. callbacks
;;;_. control callbacks
;;;_ , document body
(defun org-odt-begin-office-body ()
  ;; automatic styles
  (insert-file-contents
   (or org-export-odt-content-template-file
       (expand-file-name "styles/OrgOdtContentTemplate.xml"
			 org-odt-data-dir)))
  (goto-char (point-min))
  (re-search-forward "</office:text>" nil nil)
  (delete-region (match-beginning 0) (point-max)))

;; Following variable is let bound when `org-do-lparse' is in
;; progress. See org-html.el.
(defvar org-lparse-toc)
(defun org-odt-begin-document-body (opt-plist)
  (org-odt-begin-office-body)
  (let ((title (plist-get opt-plist :title)))
    (when title
      (insert
       (org-odt-format-stylized-paragraph 'title title))))

  ;; insert toc
  (when org-lparse-toc
    (insert "\n" org-lparse-toc "\n")))

(defvar org-lparse-body-only)		; let bound during org-do-lparse
(defvar org-lparse-to-buffer)		; let bound during org-do-lparse
(defun org-odt-end-document-body (opt-plist)
  (unless org-lparse-body-only
    (org-lparse-insert-tag "</office:text>")
    (org-lparse-insert-tag "</office:body>")))

(defun org-odt-begin-document-content (opt-plist)
  (ignore))

(defun org-odt-end-document-content ()
  (org-lparse-insert-tag "</office:document-content>"))

(defun org-odt-begin-outline (level1 snumber title tags
				     target extra-targets class)
  (org-lparse-insert
   'HEADING (org-lparse-format
	     'HEADLINE title extra-targets tags snumber level1)
   level1 target))

(defun org-odt-end-outline ()
  (ignore))

(defun org-odt-begin-outline-text (level1 snumber class)
  (ignore))

(defun org-odt-end-outline-text ()
  (ignore))

(defun org-odt-begin-paragraph (&optional style)
  (org-lparse-insert-tag
   "<text:p%s>" (org-odt-get-extra-attrs-for-paragraph-style style)))

(defun org-odt-end-paragraph ()
  (org-lparse-insert-tag "</text:p>"))

(defun org-odt-get-extra-attrs-for-paragraph-style (style)
  (let (style-name)
    (setq style-name
	  (cond
	   ((stringp style) style)
	   ((symbolp style) (org-odt-get-style-name-for-entity
			     'paragraph style))))
    (unless style-name
      (error "Don't know how to handle paragraph style %s" style))
    (format " text:style-name=\"%s\"" style-name)))

(defun org-odt-format-stylized-paragraph (style text)
  (org-odt-format-tags
   '("<text:p%s>" . "</text:p>") text
   (org-odt-get-extra-attrs-for-paragraph-style style)))

(defvar org-lparse-opt-plist)		    ; bound during org-do-lparse
(defun org-odt-format-author (&optional author)
  (when (setq author (or author (plist-get org-lparse-opt-plist :author)))
    (org-odt-format-tags '("<dc:creator>" . "</dc:creator>") author)))

(defun org-odt-iso-date-from-org-timestamp (&optional org-ts)
  (save-match-data
    (let* ((time
	    (and (stringp org-ts)
		 (string-match org-ts-regexp0 org-ts)
		 (apply 'encode-time
			(org-fix-decoded-time
			 (org-parse-time-string (match-string 0 org-ts) t)))))
	   (date (format-time-string "%Y-%m-%dT%H:%M:%S%z" time)))
      (format "%s:%s" (substring date 0 -2) (substring date -2)))))

(defun org-odt-begin-annotation (&optional author date)
  (org-lparse-insert-tag "<office:annotation>")
  (when (setq author (org-odt-format-author author))
    (insert author))
  (insert (org-odt-format-tags
	   '("<dc:date>" . "</dc:date>")
	   (org-odt-iso-date-from-org-timestamp
	    (or date (plist-get org-lparse-opt-plist :date)))))
  (org-lparse-begin-paragraph))

(defun org-odt-end-annotation ()
  (org-lparse-insert-tag  "</office:annotation>"))

(defun org-odt-begin-environment (style env-options-plist)
  (case style
    (annotation
     (org-lparse-stash-save-paragraph-state)
     (org-odt-begin-annotation (plist-get env-options-plist 'author)
			       (plist-get env-options-plist 'date)))
    ((blockquote verse center quote)
     (org-lparse-begin-paragraph style)
     (list))
    ((fixedwidth native)
     (org-lparse-end-paragraph)
     (list))
    (t (error "Unknown environment %s" style))))

(defun org-odt-end-environment (style env-options-plist)
  (case style
    (annotation
     (org-lparse-end-paragraph)
     (org-odt-end-annotation)
     (org-lparse-stash-pop-paragraph-state))
    ((blockquote verse center quote)
     (org-lparse-end-paragraph)
     (list))
    ((fixedwidth native)
     (org-lparse-begin-paragraph)
     (list))
    (t (error "Unknown environment %s" style))))

(defvar org-lparse-list-level) ; dynamically bound in org-do-lparse
(defun org-odt-begin-list (ltype)
  (setq ltype (or (org-lparse-html-list-type-to-canonical-list-type ltype)
		  ltype))
  (let* ((style-name (org-odt-get-style-name-for-entity 'list ltype))
	 (extra (concat (when (= org-lparse-list-level 1)
			  " text:continue-numbering=\"false\"")
			(when style-name
			  (format " text:style-name=\"%s\""  style-name)))))
    (case ltype
      ((ordered unordered description)
       (org-lparse-end-paragraph)
       (org-lparse-insert-tag "<text:list%s>" extra))
      (t (error "Unknown list type: %s"  ltype)))))

(defun org-odt-end-list (ltype)
  (setq ltype (or (org-lparse-html-list-type-to-canonical-list-type ltype)
		  ltype))
  (if ltype
      (org-lparse-insert-tag "</text:list>")
    (error "Unknown list type: %s" ltype)))

(defun org-odt-begin-list-item (ltype &optional arg headline)
  (setq ltype (or (org-lparse-html-list-type-to-canonical-list-type ltype)
		  ltype))
  (case ltype
    (ordered
     (assert (not headline) t)
     (let* ((counter arg) (extra ""))
       (org-lparse-insert-tag "<text:list-item>")
       (org-lparse-begin-paragraph)))
    (unordered
     (let* ((id arg) (extra ""))
       (org-lparse-insert-tag "<text:list-item>")
       (org-lparse-begin-paragraph)
       (insert (if headline (org-odt-format-target headline id)
		 (org-odt-format-bookmark "" id)))))
    (description
     (assert (not headline) t)
     (let ((term (or arg "(no term)")))
       (insert
	(org-odt-format-tags
	 '("<text:list-item>" . "</text:list-item>")
	 (org-odt-format-stylized-paragraph 'definition-term term)))
       (org-lparse-begin-list-item 'unordered)
       (org-lparse-begin-list 'description)
       (org-lparse-begin-list-item 'unordered)))
    (t (error "Unknown list type"))))

(defun org-odt-end-list-item (ltype)
  (setq ltype (or (org-lparse-html-list-type-to-canonical-list-type ltype)
		  ltype))
  (case ltype
    ((ordered unordered)
     (org-lparse-insert-tag "</text:list-item>"))
    (description
     (org-lparse-end-list-item-1)
     (org-lparse-end-list 'description)
     (org-lparse-end-list-item-1))
    (t (error "Unknown list type"))))

;; Following variables are let bound when table emission is in
;; progress. See org-lparse.el.
(defvar org-lparse-table-begin-marker)
(defvar org-lparse-table-ncols)
(defvar org-lparse-table-rowgrp-open)
(defvar org-lparse-table-rownum)
(defvar org-lparse-table-cur-rowgrp-is-hdr)
(defvar org-lparse-table-is-styled)
(defvar org-lparse-table-rowgrp-info)
(defvar org-lparse-table-colalign-vector)

(defvar org-odt-table-style nil
  "Table style specified by \"#+ATTR_ODT: <style-name>\" line.
This is set during `org-odt-begin-table'.")

(defvar org-odt-table-style-spec nil
  "Entry for `org-odt-table-style' in `org-export-odt-table-styles'.")

(defcustom org-export-odt-table-styles
  '(("OrgEquation" "OrgEquation"
     ((use-first-column-styles . t)
      (use-last-column-styles . t))))
  "Specify how Table Styles should be derived from a Table Template.
This is a list where each element is of the
form (TABLE-STYLE-NAME TABLE-TEMPLATE-NAME TABLE-CELL-OPTIONS).

TABLE-STYLE-NAME is the style associated with the table through
`org-odt-table-style'.

TABLE-TEMPLATE-NAME is a set of - upto 9 - automatic
TABLE-CELL-STYLE-NAMEs and PARAGRAPH-STYLE-NAMEs (as defined
below) that is included in
`org-export-odt-content-template-file'.

TABLE-CELL-STYLE-NAME := TABLE-TEMPLATE-NAME + TABLE-CELL-TYPE +
                         \"TableCell\"
PARAGRAPH-STYLE-NAME  := TABLE-TEMPLATE-NAME + TABLE-CELL-TYPE +
                         \"TableParagraph\"
TABLE-CELL-TYPE       := \"FirstRow\"   | \"LastColumn\" |
                         \"FirstRow\"   | \"LastRow\"    |
                         \"EvenRow\"    | \"OddRow\"     |
                         \"EvenColumn\" | \"OddColumn\"  | \"\"
where \"+\" above denotes string concatenation.

TABLE-CELL-OPTIONS is an alist where each element is of the
form (TABLE-CELL-STYLE-SELECTOR . ON-OR-OFF).
TABLE-CELL-STYLE-SELECTOR := `use-first-row-styles'       |
                             `use-last-row-styles'        |
                             `use-first-column-styles'    |
                             `use-last-column-styles'     |
                             `use-banding-rows-styles'    |
                             `use-banding-columns-styles' |
                             `use-first-row-styles'
ON-OR-OFF                 := `t' | `nil'

For example, with the following configuration

\(setq org-export-odt-table-styles
      '\(\(\"TableWithHeaderRowsAndColumns\" \"Custom\"
         \(\(use-first-row-styles . t\)
          \(use-first-column-styles . t\)\)\)
        \(\"TableWithHeaderColumns\" \"Custom\"
         \(\(use-first-column-styles . t\)\)\)\)\)

1. A table associated with \"TableWithHeaderRowsAndColumns\"
   style will use the following table-cell styles -
   \"CustomFirstRowTableCell\", \"CustomFirstColumnTableCell\",
   \"CustomTableCell\" and the following paragraph styles
   \"CustomFirstRowTableParagraph\",
   \"CustomFirstColumnTableParagraph\", \"CustomTableParagraph\"
   as appropriate.

2. A table associated with \"TableWithHeaderColumns\" style will
   use the following table-cell styles -
   \"CustomFirstColumnTableCell\", \"CustomTableCell\" and the
   following paragraph styles
   \"CustomFirstColumnTableParagraph\", \"CustomTableParagraph\"
   as appropriate..

Note that TABLE-TEMPLATE-NAME corresponds to the
\"<table:table-template>\" elements contained within
\"<office:styles>\".  The entries (TABLE-STYLE-NAME
TABLE-TEMPLATE-NAME TABLE-CELL-OPTIONS) correspond to
\"table:template-name\" and \"table:use-first-row-styles\" etc
attributes of \"<table:table>\" element.  Refer ODF-1.2
specification for more information.  Also consult the
implementation filed under `org-odt-get-table-cell-styles'.

The TABLE-STYLE-NAME \"OrgEquation\" is used internally for
formatting of numbered display equations.  Do not delete this
style from the list."
  :group 'org-export-odt
  :type '(choice
          (const :tag "None" nil)
          (repeat :tag "Table Styles"
                  (list :tag "Table Style Specification"
			(string :tag "Table Style Name")
			(string  :tag "Table Template Name")
			(alist :options (use-first-row-styles
					 use-last-row-styles
					 use-first-column-styles
					 use-last-column-styles
					 use-banding-rows-styles
					 use-banding-columns-styles)
			       :key-type symbol
			       :value-type (const :tag "True" t))))))

(defun org-odt-begin-table (caption label attributes)
  (setq org-odt-table-style attributes)
  (setq org-odt-table-style-spec
	(assoc org-odt-table-style org-export-odt-table-styles))
  (when label
    (insert
     (org-odt-format-stylized-paragraph
      'table (org-odt-format-entity-caption label caption "__Table__"))))
  (org-lparse-insert-tag
   "<table:table table:name=\"%s\" table:style-name=\"%s\">"
   (or label "") (or (nth 1 org-odt-table-style-spec) "OrgTable"))
  (setq org-lparse-table-begin-marker (point)))

(defvar org-lparse-table-colalign-info)
(defun org-odt-end-table ()
  (goto-char org-lparse-table-begin-marker)
  (loop for level from 0 below org-lparse-table-ncols
	do (let* ((col-cookie (and org-lparse-table-is-styled
				   (cdr (assoc (1+ level)
					       org-lparse-table-colalign-info))))
		  (extra-columns (or (nth 1 col-cookie) 0)))
	     (dotimes (i (1+ extra-columns))
	       (insert
		(org-odt-format-tags
		 "<table:table-column table:style-name=\"%sColumn\"/>"
		 "" (or (nth 1 org-odt-table-style-spec) "OrgTable"))))
	     (insert "\n")))
  ;; fill style attributes for table cells
  (when org-lparse-table-is-styled
    (while (re-search-forward "@@\\(table-cell:p\\|table-cell:style-name\\)@@\\([0-9]+\\)@@\\([0-9]+\\)@@" nil t)
      (let* ((spec (match-string 1))
	     (r (string-to-number (match-string 2)))
	     (c (string-to-number (match-string 3)))
	     (cell-styles (org-odt-get-table-cell-styles
			   r c org-odt-table-style-spec))
	     (table-cell-style (car cell-styles))
	     (table-cell-paragraph-style (cdr cell-styles)))
	(cond
	 ((equal spec "table-cell:p")
	  (replace-match table-cell-paragraph-style t t))
	 ((equal spec "table-cell:style-name")
	  (replace-match table-cell-style t t))))))
  (goto-char (point-max))
  (org-lparse-insert-tag "</table:table>"))

(defun org-odt-begin-table-rowgroup (&optional is-header-row)
  (when org-lparse-table-rowgrp-open
    (org-lparse-end 'TABLE-ROWGROUP))
  (org-lparse-insert-tag (if is-header-row
			   "<table:table-header-rows>"
			 "<table:table-rows>"))
  (setq org-lparse-table-rowgrp-open t)
  (setq org-lparse-table-cur-rowgrp-is-hdr is-header-row))

(defun org-odt-end-table-rowgroup ()
  (when org-lparse-table-rowgrp-open
    (setq org-lparse-table-rowgrp-open nil)
    (org-lparse-insert-tag
     (if org-lparse-table-cur-rowgrp-is-hdr
	 "</table:table-header-rows>" "</table:table-rows>"))))

(defun org-odt-format-table-row (row)
  (org-odt-format-tags
   '("<table:table-row>" . "</table:table-row>") row))

(defun org-odt-get-table-cell-styles (r c &optional style-spec)
  "Retrieve styles applicable to a table cell.
R and C are (zero-based) row and column numbers of the table
cell.  STYLE-SPEC is an entry in `org-export-odt-table-styles'
applicable to the current table.  It is `nil' if the table is not
associated with any style attributes.

Return a cons of (TABLE-CELL-STYLE-NAME . PARAGRAPH-STYLE-NAME).

When STYLE-SPEC is nil, style the table cell the conventional way
- choose cell borders based on row and column groupings and
choose paragraph alignment based on `org-col-cookies' text
property.  See also
`org-odt-get-paragraph-style-cookie-for-table-cell'.

When STYLE-SPEC is non-nil, ignore the above cookie and return
styles congruent with the ODF-1.2 specification."
  (cond
   (style-spec

    ;; LibreOffice - particularly the Writer - honors neither table
    ;; templates nor custom table-cell styles.  Inorder to retain
    ;; inter-operability with LibreOffice, only automatic styles are
    ;; used for styling of table-cells.  The current implementation is
    ;; congruent with ODF-1.2 specification and hence is
    ;; future-compatible.

    ;; Additional Note: LibreOffice's AutoFormat facility for tables -
    ;; which recognizes as many as 16 different cell types - is much
    ;; richer. Unfortunately it is NOT amenable to easy configuration
    ;; by hand.

    (let* ((template-name (nth 1 style-spec))
	   (cell-style-selectors (nth 2 style-spec))
	   (cell-type
	    (cond
	     ((and (cdr (assoc 'use-first-column-styles cell-style-selectors))
		   (= c 0)) "FirstColumn")
	     ((and (cdr (assoc 'use-last-column-styles cell-style-selectors))
		   (= c (1- org-lparse-table-ncols))) "LastColumn")
	     ((and (cdr (assoc 'use-first-row-styles cell-style-selectors))
		   (= r 0)) "FirstRow")
	     ((and (cdr (assoc 'use-last-row-styles cell-style-selectors))
		   (= r org-lparse-table-rownum))
	      "LastRow")
	     ((and (cdr (assoc 'use-banding-rows-styles cell-style-selectors))
		   (= (% r 2) 1)) "EvenRow")
	     ((and (cdr (assoc 'use-banding-rows-styles cell-style-selectors))
		   (= (% r 2) 0)) "OddRow")
	     ((and (cdr (assoc 'use-banding-columns-styles cell-style-selectors))
		   (= (% c 2) 1)) "EvenColumn")
	     ((and (cdr (assoc 'use-banding-columns-styles cell-style-selectors))
		   (= (% c 2) 0)) "OddColumn")
	     (t ""))))
      (cons
       (concat template-name cell-type "TableCell")
       (concat template-name cell-type "TableParagraph"))))
   (t
    (cons
     (concat
      "OrgTblCell"
      (cond
       ((= r 0) "T")
       ((eq (cdr (assoc r org-lparse-table-rowgrp-info))  :start) "T")
       (t ""))
      (when (= r org-lparse-table-rownum) "B")
      (cond
       ((= c 0) "")
       ((or (memq (nth c org-table-colgroup-info) '(:start :startend))
	    (memq (nth (1- c) org-table-colgroup-info) '(:end :startend))) "L")
       (t "")))
     (capitalize (aref org-lparse-table-colalign-vector c))))))

(defun org-odt-get-paragraph-style-cookie-for-table-cell (r c)
  (concat
   (and (not org-odt-table-style-spec)
	(cond
	 (org-lparse-table-cur-rowgrp-is-hdr "OrgTableHeading")
	 ((and (= c 0) (org-lparse-get 'TABLE-FIRST-COLUMN-AS-LABELS))
	  "OrgTableHeading")
	 (t "OrgTableContents")))
   (and org-lparse-table-is-styled
	(format "@@table-cell:p@@%03d@@%03d@@" r c))))

(defun org-odt-get-style-name-cookie-for-table-cell (r c)
  (when org-lparse-table-is-styled
    (format "@@table-cell:style-name@@%03d@@%03d@@" r c)))

(defun org-odt-format-table-cell (data r c horiz-span)
  (concat
   (let* ((paragraph-style-cookie
	   (org-odt-get-paragraph-style-cookie-for-table-cell r c))
	  (style-name-cookie
	   (org-odt-get-style-name-cookie-for-table-cell r c))
	  (extra (and style-name-cookie
		      (format " table:style-name=\"%s\""  style-name-cookie)))
	  (extra (concat extra
			 (and (> horiz-span 0)
			      (format " table:number-columns-spanned=\"%d\""
				      (1+ horiz-span))))))
     (org-odt-format-tags
      '("<table:table-cell%s>" . "</table:table-cell>")
      (if org-lparse-list-table-p data
	(org-odt-format-stylized-paragraph paragraph-style-cookie data)) extra))
   (let (s)
     (dotimes (i horiz-span)
       (setq s (concat s "\n<table:covered-table-cell/>"))) s)
   "\n"))

(defun org-odt-begin-footnote-definition (n)
  (org-lparse-begin-paragraph 'footnote))

(defun org-odt-end-footnote-definition (n)
  (org-lparse-end-paragraph))

(defun org-odt-begin-toc (lang-specific-heading)
  (insert
   (format "
    <text:table-of-content text:style-name=\"Sect2\" text:protected=\"true\" text:name=\"Table of Contents1\">
     <text:table-of-content-source text:outline-level=\"10\">
      <text:index-title-template text:style-name=\"Contents_20_Heading\">%s</text:index-title-template>
" lang-specific-heading))

  (loop for level from 1 upto 10
	do (insert (format
		    "
      <text:table-of-content-entry-template text:outline-level=\"%d\" text:style-name=\"Contents_20_%d\">
       <text:index-entry-link-start text:style-name=\"Internet_20_link\"/>
       <text:index-entry-chapter/>
       <text:index-entry-text/>
       <text:index-entry-link-end/>
      </text:table-of-content-entry-template>
" level level)))

  (insert
   (format  "
     </text:table-of-content-source>

     <text:index-body>
      <text:index-title text:style-name=\"Sect1\" text:name=\"Table of Contents1_Head\">
       <text:p text:style-name=\"Contents_20_Heading\">%s</text:p>
      </text:index-title>
" lang-specific-heading)))

(defun org-odt-end-toc ()
  (insert "
     </text:index-body>
    </text:table-of-content>
"))

(defun org-odt-format-toc-entry (snumber todo headline tags href)
  (setq headline (concat
		  (and org-export-with-section-numbers
		       (concat snumber ". "))
		  headline
		  (and tags
		    (concat
		     (org-lparse-format 'SPACES 3)
		     (org-lparse-format 'FONTIFY tags "tag")))))
  (when todo
    (setq headline (org-lparse-format 'FONTIFY headline "todo")))

  (let ((org-odt-suppress-xref t))
    (org-odt-format-link headline (concat  "#" href))))

(defun org-odt-format-toc-item (toc-entry level org-last-level)
  (let ((style (format "Contents_20_%d"
		       (+ level (or (org-lparse-get 'TOPLEVEL-HLEVEL) 1) -1))))
    (insert "\n" (org-odt-format-stylized-paragraph style toc-entry) "\n")))

;; Following variable is let bound during 'ORG-LINK callback. See
;; org-html.el
(defvar org-lparse-link-description-is-image nil)
(defun org-odt-format-link (desc href &optional attr)
  (cond
   ((and (= (string-to-char href) ?#) (not org-odt-suppress-xref))
    (setq href (concat org-export-odt-bookmark-prefix (substring href 1)))
    (let ((xref-format "text"))
      (when (numberp desc)
	(setq desc (format "%d" desc) xref-format "number"))
      (org-odt-format-tags
       '("<text:bookmark-ref text:reference-format=\"%s\" text:ref-name=\"%s\">" .
	 "</text:bookmark-ref>")
       desc xref-format href)))
   (org-lparse-link-description-is-image
    (org-odt-format-tags
     '("<draw:a xlink:type=\"simple\" xlink:href=\"%s\" %s>" . "</draw:a>")
     desc href (or attr "")))
   (t
    (org-odt-format-tags
     '("<text:a xlink:type=\"simple\" xlink:href=\"%s\" %s>" . "</text:a>")
     desc href (or attr "")))))

(defun org-odt-format-spaces (n)
  (cond
   ((= n 1) " ")
   ((> n 1) (concat
	     " " (org-odt-format-tags "<text:s text:c=\"%d\"/>" "" (1- n))))
   (t "")))

(defun org-odt-format-tabs (&optional n)
  (let ((tab "<text:tab/>")
	(n (or n 1)))
    (insert tab)))

(defun org-odt-format-line-break ()
  (org-odt-format-tags "<text:line-break/>" ""))

(defun org-odt-format-horizontal-line ()
  (org-odt-format-stylized-paragraph 'horizontal-line ""))

(defun org-odt-encode-plain-text (line &optional no-whitespace-filling)
  (setq line (org-xml-encode-plain-text line))
  (if no-whitespace-filling line
    (org-odt-fill-tabs-and-spaces line)))

(defun org-odt-format-line (line)
  (case org-lparse-dyn-current-environment
    (fixedwidth (concat
		 (org-odt-format-stylized-paragraph
		  'fixedwidth (org-odt-encode-plain-text line)) "\n"))
    (t (concat line "\n"))))

(defun org-odt-format-comment (fmt &rest args)
  (let ((comment (apply 'format fmt args)))
    (format "\n<!-- %s  -->\n" comment)))

(defun org-odt-format-org-entity (wd)
  (org-entity-get-representation wd 'utf8))

(defun org-odt-fill-tabs-and-spaces (line)
  (replace-regexp-in-string
   "\\([\t]\\|\\([ ]+\\)\\)" (lambda (s)
			       (cond
				((string= s "\t") (org-odt-format-tabs))
				(t (org-odt-format-spaces (length s))))) line))

(defcustom org-export-odt-fontify-srcblocks t
  "Specify whether or not source blocks need to be fontified.
Turn this option on if you want to colorize the source code
blocks in the exported file.  For colorization to work, you need
to make available an enhanced version of `htmlfontify' library."
  :type 'boolean
  :group 'org-export-odt)

(defun org-odt-format-source-line-with-line-number-and-label
  (line rpllbl num fontifier par-style)

  (let ((keep-label (not (numberp rpllbl)))
	(ref (org-find-text-property-in-string 'org-coderef line)))
    (setq line (concat line (and keep-label ref (format "(%s)" ref))))
    (setq line (funcall fontifier line))
    (when ref
      (setq line (org-odt-format-target line (concat "coderef-" ref))))
    (setq line (org-odt-format-stylized-paragraph par-style line))
    (if (not num) line
      (org-odt-format-tags '("<text:list-item>" . "</text:list-item>") line))))

(defun org-odt-format-source-code-or-example-plain
  (lines lang caption textareap cols rows num cont rpllbl fmt)
  "Format source or example blocks much like fixedwidth blocks.
Use this when `org-export-odt-fontify-srcblocks' option is turned
off."
  (let* ((lines (org-split-string lines "[\r\n]"))
	 (line-count (length lines))
	 (i 0))
    (mapconcat
     (lambda (line)
       (incf i)
       (org-odt-format-source-line-with-line-number-and-label
	line rpllbl num 'org-odt-encode-plain-text
	(if (= i line-count) "OrgFixedWidthBlockLastLine"
	  "OrgFixedWidthBlock")))
     lines "\n")))

(defvar org-src-block-paragraph-format
  "<style:style style:name=\"OrgSrcBlock\" style:family=\"paragraph\" style:parent-style-name=\"Preformatted_20_Text\">
   <style:paragraph-properties fo:background-color=\"%s\" fo:padding=\"0.049cm\" fo:border=\"0.51pt solid #000000\" style:shadow=\"none\">
    <style:background-image/>
   </style:paragraph-properties>
   <style:text-properties fo:color=\"%s\"/>
  </style:style>"
  "Custom paragraph style for colorized source and example blocks.
This style is much the same as that of \"OrgFixedWidthBlock\"
except that the foreground and background colors are set
according to the default face identified by the `htmlfontify'.")

(defun org-odt-hfy-face-to-css (fn)
  "Create custom style for face FN.
When FN is the default face, use it's foreground and background
properties to create \"OrgSrcBlock\" paragraph style.  Otherwise
use it's color attribute to create a character style whose name
is obtained from FN.  Currently all attributes of FN other than
color are ignored.

The style name for a face FN is derived using the following
operations on the face name in that order - de-dash, CamelCase
and prefix with \"OrgSrc\".  For example,
`font-lock-function-name-face' is associated with
\"OrgSrcFontLockFunctionNameFace\"."
  (let* ((css-list (hfy-face-to-style fn))
	 (style-name ((lambda (fn)
			(concat "OrgSrc"
				(mapconcat
				 'capitalize (split-string
					      (hfy-face-or-def-to-name fn) "-")
				 ""))) fn))
	 (color-val (cdr (assoc "color" css-list)))
	 (background-color-val (cdr (assoc "background" css-list)))
	 (style (and org-export-odt-create-custom-styles-for-srcblocks
		     (cond
		      ((eq fn 'default)
		       (format org-src-block-paragraph-format
			       background-color-val color-val))
		      (t
		       (format
			"
<style:style style:name=\"%s\" style:family=\"text\">
  <style:text-properties fo:color=\"%s\"/>
 </style:style>" style-name color-val))))))
    (cons style-name style)))

(defcustom org-export-odt-create-custom-styles-for-srcblocks t
  "Whether custom styles for colorized source blocks be automatically created.
When this option is turned on, the exporter creates custom styles
for source blocks based on the advice of `htmlfontify'.  Creation
of custom styles happen as part of `org-odt-hfy-face-to-css'.

When this option is turned off exporter does not create such
styles.

Use the latter option if you do not want the custom styles to be
based on your current display settings.  It is necessary that the
styles.xml already contains needed styles for colorizing to work.

This variable is effective only if
`org-export-odt-fontify-srcblocks' is turned on."
  :group 'org-export-odt
  :type 'boolean)

(defun org-odt-insert-custom-styles-for-srcblocks (styles)
  "Save STYLES used for colorizing of source blocks.
Update styles.xml with styles that were collected as part of
`org-odt-hfy-face-to-css' callbacks."
  (when styles
    (with-current-buffer
	(find-file-noselect (expand-file-name "styles.xml") t)
      (goto-char (point-min))
      (when (re-search-forward "</office:styles>" nil t)
	(goto-char (match-beginning 0))
	(insert "\n<!-- Org Htmlfontify Styles -->\n" styles "\n")))))

(defun org-odt-format-source-code-or-example-colored
  (lines lang caption textareap cols rows num cont rpllbl fmt)
  "Format source or example blocks using `htmlfontify-string'.
Use this routine when `org-export-odt-fontify-srcblocks' option
is turned on."
  (let* ((lang-m (and lang (or (cdr (assoc lang org-src-lang-modes)) lang)))
	 (mode (and lang-m (intern (concat (if (symbolp lang-m)
					       (symbol-name lang-m)
					     lang-m) "-mode"))))
	 (org-inhibit-startup t)
	 (org-startup-folded nil)
	 (lines (with-temp-buffer
		  (insert lines)
		  (if (functionp mode) (funcall mode) (fundamental-mode))
		  (font-lock-fontify-buffer)
		  (buffer-string)))
	 (hfy-html-quote-regex "\\([<\"&> 	]\\)")
	 (hfy-html-quote-map '(("\"" "&quot;")
			       ("<" "&lt;")
			       ("&" "&amp;")
			       (">" "&gt;")
			       (" " "<text:s/>")
			       ("	" "<text:tab/>")))
	 (hfy-face-to-css 'org-odt-hfy-face-to-css)
	 (hfy-optimisations-1 (copy-seq hfy-optimisations))
	 (hfy-optimisations (add-to-list 'hfy-optimisations-1
					 'body-text-only))
	 (hfy-begin-span-handler
	  (lambda (style text-block text-id text-begins-block-p)
	    (insert (format "<text:span text:style-name=\"%s\">" style))))
	 (hfy-end-span-handler (lambda nil (insert "</text:span>"))))
    (when (fboundp 'htmlfontify-string)
      (let* ((lines (org-split-string lines "[\r\n]"))
	     (line-count (length lines))
	     (i 0))
	(mapconcat
	 (lambda (line)
	   (incf i)
	   (org-odt-format-source-line-with-line-number-and-label
	    line rpllbl num 'htmlfontify-string
	    (if (= i line-count) "OrgSrcBlockLastLine" "OrgSrcBlock")))
	 lines "\n")))))

(defun org-odt-format-source-code-or-example (lines lang caption textareap
						    cols rows num cont
						    rpllbl fmt)
  "Format source or example blocks for export.
Use `org-odt-format-source-code-or-example-plain' or
`org-odt-format-source-code-or-example-colored' depending on the
value of `org-export-odt-fontify-srcblocks."
  (setq lines (org-export-number-lines
	       lines 0 0 num cont rpllbl fmt 'preprocess)
	lines (funcall
	       (or (and org-export-odt-fontify-srcblocks
			(or (featurep 'htmlfontify)
			    (require 'htmlfontify))
			(fboundp 'htmlfontify-string)
			'org-odt-format-source-code-or-example-colored)
		   'org-odt-format-source-code-or-example-plain)
	       lines lang caption textareap cols rows num cont rpllbl fmt))
  (if (not num) lines
    (let ((extra (format " text:continue-numbering=\"%s\""
			 (if cont "true" "false"))))
      (org-odt-format-tags
       '("<text:list text:style-name=\"OrgSrcBlockNumberedLine\"%s>"
	 . "</text:list>") lines extra))))

(defun org-odt-remap-stylenames (style-name)
  (or
   (cdr (assoc style-name '(("timestamp-wrapper" . "OrgTimestampWrapper")
			    ("timestamp" . "OrgTimestamp")
			    ("timestamp-kwd" . "OrgTimestampKeyword")
			    ("tag" . "OrgTag")
			    ("todo" . "OrgTodo")
			    ("done" . "OrgDone")
			    ("target" . "OrgTarget"))))
   style-name))

(defun org-odt-format-fontify (text style &optional id)
  (let* ((style-name
	  (cond
	   ((stringp style)
	    (org-odt-remap-stylenames style))
	   ((symbolp style)
	    (org-odt-get-style-name-for-entity 'character style))
	   ((listp style)
	    (assert (< 1 (length style)))
	    (let ((parent-style (pop style)))
	      (mapconcat (lambda (s)
			   ;; (assert (stringp s) t)
			   (org-odt-remap-stylenames s)) style "")
	      (org-odt-remap-stylenames parent-style)))
	   (t (error "Don't how to handle style %s"  style)))))
    (org-odt-format-tags
     '("<text:span text:style-name=\"%s\">" . "</text:span>")
     text style-name)))

(defun org-odt-relocate-relative-path (path dir)
  (if (file-name-absolute-p path) path
    (file-relative-name (expand-file-name path dir)
			(expand-file-name "eyecandy" dir))))

(defun org-odt-format-inline-image (thefile)
  (let* ((thelink (if (file-name-absolute-p thefile) thefile
		    (org-xml-format-href
		     (org-odt-relocate-relative-path
		      thefile org-current-export-file))))
	 (href
	  (org-odt-format-tags
	   "<draw:image xlink:href=\"%s\" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\"/>" ""
	   (if org-export-odt-embed-images
	       (org-odt-copy-image-file thefile) thelink))))
    (org-export-odt-format-image thefile href)))

(defun org-export-odt-format-formula (src href &optional embed-as)
  "Create image tag with source and attributes."
  (save-match-data
    (let* ((caption (org-find-text-property-in-string 'org-caption src))
	   (caption (and caption (org-xml-format-desc caption)))
	   (label (org-find-text-property-in-string 'org-label src))
	   (latex-frag (org-find-text-property-in-string 'org-latex-src src))
	   (embed-as (or embed-as
			 (and latex-frag
			      (org-find-text-property-in-string
			       'org-latex-src-embed-type src))
			 (if (or caption label) 'paragraph 'character)))
	   width height)
      (when latex-frag
	(setq href (org-propertize href :title "LaTeX Fragment"
				   :description latex-frag)))
      (cond
       ((eq embed-as 'character)
	(org-odt-format-entity "InlineFormula" href width height))
       (t
	(org-lparse-end-paragraph)
	(org-lparse-insert-list-table
	 `((,(org-odt-format-entity
	      (if caption "CaptionedDisplayFormula" "DisplayFormula")
	      href width height caption nil)
	    ,(if (not label) ""
	       (org-odt-format-entity-caption label nil "__MathFormula__"))))
	 nil nil nil "OrgEquation" nil '((1 "c" 8) (2 "c" 1)))
	(throw 'nextline nil))))))

(defvar org-odt-embedded-formulas-count 0)
(defun org-odt-copy-formula-file (path)
  "Returns the internal name of the file"
  (let* ((src-file (expand-file-name
		    path (file-name-directory org-current-export-file)))
	 (target-dir (format "Formula-%04d/"
			     (incf org-odt-embedded-formulas-count)))
	 (target-file (concat target-dir "content.xml")))
    (when (not org-lparse-to-buffer)
      (message "Embedding %s as %s ..."
	       (substring-no-properties path) target-file)

	(make-directory target-dir)
	(org-odt-create-manifest-file-entry
	 "application/vnd.oasis.opendocument.formula" target-dir "1.2")

	(case (org-odt-is-formula-link-p src-file)
	  (mathml
	   (copy-file src-file target-file 'overwrite))
	  (odf
	   (org-odt-zip-extract-one src-file "content.xml" target-dir))
	  (t
	   (error "%s is not a formula file" src-file)))

	(org-odt-create-manifest-file-entry "text/xml" target-file))
    target-file))

(defun org-odt-format-inline-formula (thefile)
  (let* ((thelink (if (file-name-absolute-p thefile) thefile
		    (org-xml-format-href
		     (org-odt-relocate-relative-path
		      thefile org-current-export-file))))
	 (href
	  (org-odt-format-tags
	   "<draw:object xlink:href=\"%s\" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\"/>" ""
	   (file-name-directory (org-odt-copy-formula-file thefile)))))
    (org-export-odt-format-formula thefile href)))

(defun org-odt-is-formula-link-p (file)
  (let ((case-fold-search nil))
    (cond
     ((string-match "\\.\\(mathml\\|mml\\)\\'" file)
      'mathml)
     ((string-match "\\.odf\\'" file)
      'odf))))

(defun org-odt-format-org-link (opt-plist type-1 path fragment desc attr
					  descp)
  "Make a OpenDocument link.
OPT-PLIST is an options list.
TYPE-1 is the device-type of the link (THIS://foo.html).
PATH is the path of the link (http://THIS#location).
FRAGMENT is the fragment part of the link, if any (foo.html#THIS).
DESC is the link description, if any.
ATTR is a string of other attributes of the a element."
  (declare (special org-lparse-par-open))
  (save-match-data
    (let* ((may-inline-p
	    (and (member type-1 '("http" "https" "file"))
		 (org-lparse-should-inline-p path descp)
		 (not fragment)))
	   (type (if (equal type-1 "id") "file" type-1))
	   (filename path)
	   (thefile path))
      (cond
       ;; check for inlined images
       ((and (member type '("file"))
	     (not fragment)
	     (org-file-image-p
	      filename org-export-odt-inline-image-extensions)
	     (or (eq t org-export-odt-inline-images)
		 (and org-export-odt-inline-images (not descp))))
	(org-odt-format-inline-image thefile))
       ;; check for embedded formulas
       ((and (member type '("file"))
	     (not fragment)
	     (org-odt-is-formula-link-p filename)
	     (or (not descp)))
	(org-odt-format-inline-formula thefile))
       ((string= type "coderef")
	(let* ((ref fragment)
	       (lineno-or-ref (cdr (assoc ref org-export-code-refs)))
	       (desc (and descp desc))
	       (org-odt-suppress-xref nil)
	       (href (org-xml-format-href (concat "#coderef-" ref))))
	  (cond
	   ((and (numberp lineno-or-ref) (not desc))
	    (org-odt-format-link lineno-or-ref href))
	   ((and (numberp lineno-or-ref) desc
		 (string-match (regexp-quote (concat "(" ref ")")) desc))
	    (format (replace-match "%s" t t desc)
		    (org-odt-format-link lineno-or-ref href)))
	   (t
	    (setq desc (format
			(if (and desc (string-match
				       (regexp-quote (concat "(" ref ")"))
				       desc))
			    (replace-match "%s" t t desc)
			  (or desc "%s"))
			lineno-or-ref))
	    (org-odt-format-link (org-xml-format-desc desc) href)))))
       (t
	(when (string= type "file")
	  (setq thefile
		(cond
		 ((file-name-absolute-p path)
		  (concat "file://" (expand-file-name path)))
		 (t (org-odt-relocate-relative-path
		     thefile org-current-export-file)))))

	(when (and (member type '("" "http" "https" "file")) fragment)
	  (setq thefile (concat thefile "#" fragment)))

	(setq thefile (org-xml-format-href thefile))

	(when (not (member type '("" "file")))
	  (setq thefile (concat type ":" thefile)))

	(let ((org-odt-suppress-xref nil))
	  (org-odt-format-link
	   (org-xml-format-desc desc) thefile attr)))))))

(defun org-odt-format-heading (text level &optional id)
  (let* ((text (if id (org-odt-format-target text id) text)))
    (org-odt-format-tags
     '("<text:h text:style-name=\"Heading_20_%s\" text:outline-level=\"%s\">" .
       "</text:h>") text level level)))

(defun org-odt-format-headline (title extra-targets tags
					    &optional snumber level)
  (concat
   (org-lparse-format 'EXTRA-TARGETS extra-targets)

   ;; No need to generate section numbers. They are auto-generated by
   ;; the application

   ;; (concat (org-lparse-format 'SECTION-NUMBER snumber level) " ")
   title
   (and tags (concat (org-lparse-format 'SPACES 3)
		     (org-lparse-format 'ORG-TAGS tags)))))

(defun org-odt-format-anchor (text name &optional class)
  (org-odt-format-target text name))

(defun org-odt-format-bookmark (text id)
  (if id
      (org-odt-format-tags "<text:bookmark text:name=\"%s\"/>" text id)
    text))

(defun org-odt-format-target (text id)
  (let ((name (concat org-export-odt-bookmark-prefix id)))
    (concat
     (and id (org-odt-format-tags
	      "<text:bookmark-start text:name=\"%s\"/>" "" name))
     (org-odt-format-bookmark text id)
     (and id (org-odt-format-tags
	      "<text:bookmark-end text:name=\"%s\"/>" "" name)))))

(defun org-odt-format-footnote (n def)
  (let ((id (concat  "fn" n))
	(note-class "footnote")
	(par-style "Footnote"))
    (org-odt-format-tags
     '("<text:note text:id=\"%s\" text:note-class=\"%s\">" .
       "</text:note>")
     (concat
      (org-odt-format-tags
       '("<text:note-citation>" . "</text:note-citation>")
       n)
      (org-odt-format-tags
       '("<text:note-body>" . "</text:note-body>")
       def))
     id note-class)))

(defun org-odt-format-footnote-reference (n def refcnt)
  (if (= refcnt 1)
      (org-odt-format-footnote n def)
    (org-odt-format-footnote-ref n)))

(defun org-odt-format-footnote-ref (n)
  (let ((note-class "footnote")
	(ref-format "text")
	(ref-name (concat "fn" n)))
    (org-odt-format-tags
     '("<text:span text:style-name=\"%s\">" . "</text:span>")
     (org-odt-format-tags
      '("<text:note-ref text:note-class=\"%s\" text:reference-format=\"%s\" text:ref-name=\"%s\">" . "</text:note-ref>")
      n note-class ref-format ref-name)
     "OrgSuperscript")))

(defun org-odt-get-image-name (file-name)
  (require 'sha1)
  (file-relative-name
   (expand-file-name
    (concat (sha1 file-name) "." (file-name-extension file-name)) "Pictures")))

(defun org-export-odt-format-image (src href &optional embed-as)
  "Create image tag with source and attributes."
  (save-match-data
    (let* ((caption (org-find-text-property-in-string 'org-caption src))
	   (caption (and caption (org-xml-format-desc caption)))
	   (attr (org-find-text-property-in-string 'org-attributes src))
	   (label (org-find-text-property-in-string 'org-label src))
	   (latex-frag (org-find-text-property-in-string
			      'org-latex-src src))
	   (category (and latex-frag "__DvipngImage__"))
	   (embed-as (or embed-as
			 (if latex-frag
			     (or (org-find-text-property-in-string
				  'org-latex-src-embed-type src) 'character)
			   'paragraph)))
	   (attr-plist (org-lparse-get-block-params attr))
	   (size (org-odt-image-size-from-file
		  src (plist-get attr-plist :width)
		  (plist-get attr-plist :height)
		  (plist-get attr-plist :scale) nil embed-as))
	   (width (car size)) (height (cdr size)))
      (when latex-frag
	(setq href (org-propertize href :title "LaTeX Fragment"
				   :description latex-frag)))
      (cond
       ((not (or caption label))
	(case embed-as
	  (paragraph (org-odt-format-entity "DisplayImage" href width height))
	  (character (org-odt-format-entity "InlineImage" href width height))
	  (t (error "Unknown value for embed-as %S" embed-as))))
       (t
	(org-odt-format-entity
	 "CaptionedDisplayImage" href width height caption label category))))))

(defun org-odt-format-object-description (title description)
  (concat (and title (org-odt-format-tags
		      '("<svg:title>" . "</svg:title>")
		      (org-odt-encode-plain-text title t)))
	  (and description (org-odt-format-tags
			    '("<svg:desc>" . "</svg:desc>")
			    (org-odt-encode-plain-text description t)))))

(defun org-odt-format-frame (text width height style &optional
				  extra anchor-type)
  (let ((frame-attrs
	 (concat
	  (if width (format " svg:width=\"%0.2fcm\"" width) "")
	  (if height (format " svg:height=\"%0.2fcm\"" height) "")
	  extra
	  (format " text:anchor-type=\"%s\"" (or anchor-type "paragraph")))))
    (org-odt-format-tags
     '("<draw:frame draw:style-name=\"%s\"%s>" . "</draw:frame>")
     (concat text (org-odt-format-object-description
		   (get-text-property 0 :title text)
		   (get-text-property 0 :description text)))
     style frame-attrs)))

(defun org-odt-format-textbox (text width height style &optional
				    extra anchor-type)
  (org-odt-format-frame
   (org-odt-format-tags
    '("<draw:text-box %s>" . "</draw:text-box>")
    text (concat (format " fo:min-height=\"%0.2fcm\"" (or height .2))
		 (format " fo:min-width=\"%0.2fcm\"" (or width .2))))
   width nil style extra anchor-type))

(defun org-odt-format-inlinetask (heading content
					  &optional todo priority tags)
  (org-odt-format-stylized-paragraph
   nil (org-odt-format-textbox
	(concat (org-odt-format-stylized-paragraph
		 "OrgInlineTaskHeading"
		 (org-lparse-format
		  'HEADLINE (concat (org-lparse-format-todo todo) " " heading)
		  nil tags))
		content) nil nil "OrgInlineTaskFrame" " style:rel-width=\"100%\"")))

(defvar org-odt-entity-frame-styles
  '(("InlineImage" "__Figure__" ("OrgInlineImage" nil "as-char"))
    ("DisplayImage" "__Figure__" ("OrgDisplayImage" nil "paragraph"))
    ("CaptionedDisplayImage" "__Figure__"
     ("OrgCaptionedImage"
      " style:rel-width=\"100%\" style:rel-height=\"scale\"" "paragraph")
     ("OrgImageCaptionFrame"))
    ("InlineFormula" "__MathFormula__" ("OrgInlineFormula" nil "as-char"))
    ("DisplayFormula" "__MathFormula__" ("OrgDisplayFormula" nil "as-char"))
    ("CaptionedDisplayFormula" "__MathFormula__"
     ("OrgCaptionedFormula" nil "paragraph")
     ("OrgFormulaCaptionFrame" nil "as-char"))))

(defun org-odt-format-entity (entity href width height
				     &optional caption label category)
  (let* ((entity-style (assoc entity org-odt-entity-frame-styles))
	 (entity-frame (apply 'org-odt-format-frame
			      href width height (nth 2 entity-style))))
    (if (not (or caption label)) entity-frame
      (apply 'org-odt-format-textbox
	     (org-odt-format-stylized-paragraph
	      'illustration
	      (concat entity-frame
		      (org-odt-format-entity-caption
		       label caption (or category (nth 1 entity-style)))))
	     width height (nth 3 entity-style)))))

(defvar org-odt-embedded-images-count 0)
(defun org-odt-copy-image-file (path)
  "Returns the internal name of the file"
  (let* ((image-type (file-name-extension path))
	 (media-type (format "image/%s" image-type))
	 (src-file (expand-file-name
		    path (file-name-directory org-current-export-file)))
	 (target-dir "Images/")
	 (target-file
	  (format "%s%04d.%s" target-dir
		  (incf org-odt-embedded-images-count) image-type)))
    (when (not org-lparse-to-buffer)
      (message "Embedding %s as %s ..."
	       (substring-no-properties path) target-file)

      (when (= 1 org-odt-embedded-images-count)
	(make-directory target-dir)
	(org-odt-create-manifest-file-entry "" target-dir))

      (copy-file src-file target-file 'overwrite)
      (org-odt-create-manifest-file-entry media-type target-file))
    target-file))

(defvar org-export-odt-image-size-probe-method
  '(emacs imagemagick force)
  "Ordered list of methods by for determining size of an embedded
  image.")

(defvar org-export-odt-default-image-sizes-alist
  '(("character" . (5 . 0.4))
    ("paragraph" . (5 . 5)))
  "Hardcoded image dimensions one for each of the anchor
  methods.")

(defun org-odt-do-image-size (probe-method file &optional dpi anchor-type)
  (setq dpi (or dpi org-export-odt-pixels-per-inch))
  (setq anchor-type (or anchor-type "paragraph"))
  (flet ((size-in-cms (size-in-pixels)
		      (flet ((pixels-to-cms (pixels)
					    (let* ((cms-per-inch 2.54)
						   (inches (/ pixels dpi)))
					      (* cms-per-inch inches))))
			(and size-in-pixels
			     (cons (pixels-to-cms (car size-in-pixels))
				   (pixels-to-cms (cdr size-in-pixels)))))))
    (case probe-method
      (emacs
       (size-in-cms (ignore-errors (image-size (create-image file) 'pixels))))
      (imagemagick
       (size-in-cms
	(let ((dim (shell-command-to-string
		    (format "identify -format \"%%w:%%h\" \"%s\"" file))))
	  (when (string-match "\\([0-9]+\\):\\([0-9]+\\)" dim)
	    (cons (string-to-number (match-string 1 dim))
		  (string-to-number (match-string 2 dim)))))))
      (t
       (cdr (assoc-string anchor-type
			  org-export-odt-default-image-sizes-alist))))))

(defun org-odt-image-size-from-file (file &optional user-width
					  user-height scale dpi embed-as)
  (unless (file-name-absolute-p file)
    (setq file (expand-file-name
		file (file-name-directory org-current-export-file))))
  (let* (size width height)
    (unless (and user-height user-width)
      (loop for probe-method in org-export-odt-image-size-probe-method
	    until size
	    do (setq size (org-odt-do-image-size
			   probe-method file dpi embed-as)))
      (or size (error "Cannot determine Image size. Aborting ..."))
      (setq width (car size) height (cdr size)))
    (cond
     (scale
      (setq width (* width scale) height (* height scale)))
     ((and user-height user-width)
      (setq width user-width height user-height))
     (user-height
      (setq width (* user-height (/ width height)) height user-height))
     (user-width
      (setq height (* user-width (/ height width)) width user-width))
     (t (ignore)))
    (cons width height)))

(defvar org-odt-entity-labels-alist nil
  "Associate Labels with the Labelled entities.
Each element of the alist is of the form (LABEL-NAME
CATEGORY-NAME SEQNO LABEL-STYLE-NAME).  LABEL-NAME is same as
that specified by \"#+LABEL: ...\" line.  CATEGORY-NAME is the
type of the entity that LABEL-NAME is attached to.  CATEGORY-NAME
can be one of \"Table\", \"Figure\" or \"Equation\".  SEQNO is
the unique number assigned to the referenced entity on a
per-CATEGORY basis.  It is generated sequentially and is 1-based.
LABEL-STYLE-NAME is a key `org-odt-label-styles'.

See `org-odt-add-label-definition' and
`org-odt-fixup-label-references'.")

(defvar org-odt-entity-counts-plist nil
  "Plist of running counters of SEQNOs for each of the CATEGORY-NAMEs.
See `org-odt-entity-labels-alist' for known CATEGORY-NAMEs.")

(defvar org-odt-label-styles
  '(("text" "(%n)" "text" "(%n)")
    ("category-and-value" "%e %n%c" "category-and-value" "%e %n"))
  "Specify how labels are applied and referenced.
This is an alist where each element is of the
form (LABEL-STYLE-NAME LABEL-ATTACH-FMT LABEL-REF-MODE
LABEL-REF-FMT).

LABEL-ATTACH-FMT controls how labels and captions are attached to
an entity.  It may contain following specifiers - %e, %n and %c.
%e is replaced with the CATEGORY-NAME.  %n is replaced with
\"<text:sequence ...> SEQNO </text:sequence>\".  %c is replaced
with CAPTION. See `org-odt-format-label-definition'.

LABEL-REF-MODE and LABEL-REF-FMT controls how label references
are generated.  The following XML is generated for a label
reference - \"<text:sequence-ref
text:reference-format=\"LABEL-REF-MODE\" ...> LABEL-REF-FMT
</text:sequence-ref>\".  LABEL-REF-FMT may contain following
specifiers - %e and %n.  %e is replaced with the CATEGORY-NAME.
%n is replaced with SEQNO. See
`org-odt-format-label-reference'.")

(defvar org-odt-category-map-alist
  '(("__Table__" "Table" "category-and-value")
    ("__Figure__" "Figure" "category-and-value")
    ("__MathFormula__" "Equation" "text")
    ("__DvipngImage__" "Equation" "category-and-value"))
  "Map a CATEGORY-HANDLE to CATEGORY-NAME and LABEL-STYLE.
This is an alist where each element is of the form
\\(CATEGORY-HANDLE CATEGORY-NAME LABEL-STYLE\\).  CATEGORY_HANDLE
could either be one of the internal handles (as seen above) or be
derived from the \"#+LABEL:<label-name>\" specification.  See
`org-export-odt-get-category-from-label'.  CATEGORY-NAME and
LABEL-STYLE are used for generating ODT labels.  See
`org-odt-label-styles'.")

(defvar org-export-odt-user-categories
  '("Illustration" "Table" "Text" "Drawing" "Equation" "Figure"))

(defvar org-export-odt-get-category-from-label nil
  "Should category of label be inferred from label itself.
When this option is non-nil, a label is parsed in to two
component parts delimited by a \":\" (colon) as shown here -
#+LABEL:[CATEGORY-HANDLE:]EXTRA.  The CATEGORY-HANDLE is mapped
to a CATEGORY-NAME and LABEL-STYLE using
`org-odt-category-map-alist'.  (If no such map is provided and
CATEGORY-NAME is set to CATEGORY-HANDLE and LABEL-STYLE is set to
\"category-and-value\").  If CATEGORY-NAME so obtained is listed
under `org-export-odt-user-categories' then the user specified
styles are used.  Otherwise styles as determined by the internal
CATEGORY-HANDLE is used.  See
`org-odt-get-label-category-and-style' for details.")

(defun org-odt-get-label-category-and-style (label default-category)
  "See `org-export-odt-get-category-from-label'."
  (let ((default-category-map
	  (assoc default-category org-odt-category-map-alist))
	user-category user-category-map category)
    (cond
     ((not org-export-odt-get-category-from-label)
      default-category-map)
     ((not (setq user-category
		 (save-match-data
		   (and (string-match "\\`\\(.*\\):.+" label)
			(match-string 1 label)))))
      default-category-map)
     (t
      (setq user-category-map
	    (or (assoc user-category org-odt-category-map-alist)
		(list nil user-category "category-and-value"))
	    category (nth 1 user-category-map))
      (if (member category org-export-odt-user-categories)
	  user-category-map
	default-category-map)))))

(defun org-odt-add-label-definition (label default-category)
  "Create an entry in `org-odt-entity-labels-alist' and return it."
  (setq label (substring-no-properties label))
  (let* ((label-props (org-odt-get-label-category-and-style
		       label default-category))
	 (category (nth 1 label-props))
	 (counter category)
	 (label-style (nth 2 label-props))
	 (sequence-var (intern (mapconcat
				'downcase
				(org-split-string counter) "-")))
	 (seqno (1+ (or (plist-get org-odt-entity-counts-plist sequence-var)
			0)))
	 (label-props (list label category seqno label-style)))
    (setq org-odt-entity-counts-plist
	  (plist-put org-odt-entity-counts-plist sequence-var seqno))
    (push label-props org-odt-entity-labels-alist)
    label-props))

(defun org-odt-format-label-definition (caption label category seqno label-style)
  (assert label)
  (format-spec
   (cadr (assoc-string label-style org-odt-label-styles t))
   `((?e . ,category)
     (?n . ,(org-odt-format-tags
	     '("<text:sequence text:ref-name=\"%s\" text:name=\"%s\" text:formula=\"ooow:%s+1\" style:num-format=\"1\">" . "</text:sequence>")
	     (format "%d" seqno) label category category))
     (?c . ,(or (and caption (concat ": " caption)) "")))))

(defun org-odt-format-label-reference (label category seqno label-style)
  (assert label)
  (save-match-data
    (let* ((fmt (cddr (assoc-string label-style org-odt-label-styles t)))
	   (fmt1 (car fmt))
	   (fmt2 (cadr fmt)))
      (org-odt-format-tags
       '("<text:sequence-ref text:reference-format=\"%s\" text:ref-name=\"%s\">"
	 . "</text:sequence-ref>")
       (format-spec fmt2 `((?e . ,category)
			   (?n . ,(format "%d" seqno)))) fmt1 label))))

(defun org-odt-fixup-label-references ()
  (goto-char (point-min))
  (while (re-search-forward
	  "<text:sequence-ref text:ref-name=\"\\([^\"]+\\)\"/>" nil t)
    (let* ((label (match-string 1))
	   (label-def (assoc label org-odt-entity-labels-alist))
	   (rpl (and label-def
		     (apply 'org-odt-format-label-reference label-def))))
      (if rpl (replace-match rpl t t)
	(org-lparse-warn
	 (format "Unable to resolve reference to label \"%s\"" label))))))

(defun org-odt-format-entity-caption (label caption category)
  (or (and label
	   (apply 'org-odt-format-label-definition
		  caption (org-odt-add-label-definition label category)))
      caption ""))

(defun org-odt-format-tags (tag text &rest args)
  (let ((prefix (when org-lparse-encode-pending "@"))
	(suffix (when org-lparse-encode-pending "@")))
    (apply 'org-lparse-format-tags tag text prefix suffix args)))

(defun org-odt-init-outfile (filename)
  (unless (executable-find "zip")
    ;; Not at all OSes ship with zip by default
    (error "Executable \"zip\" needed for creating OpenDocument files"))

  (let* ((outdir (make-temp-file
		  (format org-export-odt-tmpdir-prefix org-lparse-backend) t))
	 (content-file (expand-file-name "content.xml" outdir)))

    ;; init conten.xml
    (with-current-buffer (find-file-noselect content-file t))

    ;; reset variables
    (setq org-odt-manifest-file-entries nil
	  org-odt-embedded-images-count 0
	  org-odt-embedded-formulas-count 0
	  org-odt-entity-labels-alist nil
	  org-odt-entity-counts-plist nil)
    content-file))

(defcustom org-export-odt-prettify-xml nil
  "Specify whether or not the xml output should be prettified.
When this option is turned on, `indent-region' is run on all
component xml buffers before they are saved.  Turn this off for
regular use.  Turn this on if you need to examine the xml
visually."
  :group 'org-export-odt
  :type 'boolean)

(defvar hfy-user-sheet-assoc)		; bound during org-do-lparse
(defun org-odt-save-as-outfile (target opt-plist)
  ;; write meta file
  (org-odt-update-meta-file opt-plist)

  ;; write styles file
  (when (equal org-lparse-backend 'odt)
    (org-odt-update-styles-file opt-plist))

  ;; create mimetype file
  (let ((mimetype (org-odt-write-mimetype-file org-lparse-backend)))
    (org-odt-create-manifest-file-entry mimetype "/" "1.2"))

  ;; create a manifest entry for content.xml
  (org-odt-create-manifest-file-entry "text/xml" "content.xml")

  ;; write out the manifest entries before zipping
  (org-odt-write-manifest-file)

  (let ((xml-files '("mimetype" "META-INF/manifest.xml" "content.xml"
		     "meta.xml"))
	(zipdir default-directory))
    (when (equal org-lparse-backend 'odt)
      (push "styles.xml" xml-files))
    (message "Switching to directory %s" (expand-file-name zipdir))

    ;; save all xml files
    (mapc (lambda (file)
	    (with-current-buffer
		(find-file-noselect (expand-file-name file) t)
	      ;; prettify output if needed
	      (when org-export-odt-prettify-xml
		(indent-region (point-min) (point-max)))
	      (save-buffer 0)))
	  xml-files)

    (let* ((target-name (file-name-nondirectory target))
	   (target-dir (file-name-directory target))
	   (cmds `(("zip" "-mX0" ,target-name "mimetype")
		   ("zip" "-rmTq" ,target-name "."))))
      (when (file-exists-p target)
	;; FIXME: If the file is locked this throws a cryptic error
	(delete-file target))

      (let ((coding-system-for-write 'no-conversion) exitcode err-string)
	(message "Creating odt file...")
	(mapc
	 (lambda (cmd)
	   (message "Running %s" (mapconcat 'identity cmd " "))
	   (setq err-string
		 (with-output-to-string
		   (setq exitcode
			 (apply 'call-process (car cmd)
				nil standard-output nil (cdr cmd)))))
	   (or (zerop exitcode)
	       (ignore (message "%s" err-string))
	       (error "Unable to create odt file (%S)" exitcode)))
	 cmds))

      ;; move the file from outdir to target-dir
      (rename-file target-name target-dir)

      ;; kill all xml buffers
      (mapc (lambda (file)
	      (kill-buffer
	       (find-file-noselect (expand-file-name file zipdir) t)))
	    xml-files)

      (delete-directory zipdir)))
  (message "Created %s" target)
  (set-buffer (find-file-noselect target t)))

(defconst org-odt-manifest-file-entry-tag
  "
<manifest:file-entry manifest:media-type=\"%s\" manifest:full-path=\"%s\"%s/>")

(defvar org-odt-manifest-file-entries nil)

(defun org-odt-create-manifest-file-entry (&rest args)
  (push args org-odt-manifest-file-entries))

(defun org-odt-write-manifest-file ()
  (make-directory "META-INF")
  (let ((manifest-file (expand-file-name "META-INF/manifest.xml")))
    (write-region
     "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
     <manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\" manifest:version=\"1.2\">\n"
     nil manifest-file)
    (mapc
     (lambda (file-entry)
       (let* ((version (nth 2 file-entry))
	      (extra (if version
			 (format  " manifest:version=\"%s\"" version)
		       "")))
	 (write-region
	  (format org-odt-manifest-file-entry-tag
		  (nth 0 file-entry) (nth 1 file-entry) extra)
	  nil manifest-file t))) org-odt-manifest-file-entries)
    (write-region "\n</manifest:manifest>" nil manifest-file t)))

(defun org-odt-update-meta-file (opt-plist)
  (let ((date (org-odt-iso-date-from-org-timestamp
	       (plist-get opt-plist :date)))
	(author (or (plist-get opt-plist :author) ""))
	(email (plist-get opt-plist :email))
	(keywords (plist-get opt-plist :keywords))
	(description (plist-get opt-plist :description))
	(title (plist-get opt-plist :title)))
    (write-region
     (concat
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
     <office:document-meta
         xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\"
         xmlns:xlink=\"http://www.w3.org/1999/xlink\"
         xmlns:dc=\"http://purl.org/dc/elements/1.1/\"
         xmlns:meta=\"urn:oasis:names:tc:opendocument:xmlns:meta:1.0\"
         xmlns:ooo=\"http://openoffice.org/2004/office\"
         office:version=\"1.2\">
       <office:meta>" "\n"
      (org-odt-format-author)
      (org-odt-format-tags
       '("\n<meta:initial-creator>" . "</meta:initial-creator>") author)
      (org-odt-format-tags '("\n<dc:date>" . "</dc:date>") date)
      (org-odt-format-tags
       '("\n<meta:creation-date>" . "</meta:creation-date>") date)
      (org-odt-format-tags '("\n<meta:generator>" . "</meta:generator>")
			   (when org-export-creator-info
			     (format "Org-%s/Emacs-%s"
				     org-version emacs-version)))
      (org-odt-format-tags '("\n<meta:keyword>" . "</meta:keyword>") keywords)
      (org-odt-format-tags '("\n<dc:subject>" . "</dc:subject>") description)
      (org-odt-format-tags '("\n<dc:title>" . "</dc:title>") title)
      "\n"
      "  </office:meta>" "</office:document-meta>")
     nil (expand-file-name "meta.xml")))

  ;; create a manifest entry for meta.xml
  (org-odt-create-manifest-file-entry "text/xml" "meta.xml"))

(defun org-odt-update-styles-file (opt-plist)
  ;; write styles file
  (let ((styles-file (plist-get opt-plist :odt-styles-file)))
    (org-odt-copy-styles-file (and styles-file
				   (read (org-trim styles-file)))))

  ;; Update styles.xml - take care of outline numbering
  (with-current-buffer
      (find-file-noselect (expand-file-name "styles.xml") t)
    ;; Don't make automatic backup of styles.xml file. This setting
    ;; prevents the backedup styles.xml file from being zipped in to
    ;; odt file. This is more of a hackish fix. Better alternative
    ;; would be to fix the zip command so that the output odt file
    ;; includes only the needed files and excludes any auto-generated
    ;; extra files like backups and auto-saves etc etc. Note that
    ;; currently the zip command zips up the entire temp directory so
    ;; that any auto-generated files created under the hood ends up in
    ;; the resulting odt file.
    (set (make-local-variable 'backup-inhibited) t)

    ;; Import local setting of `org-export-with-section-numbers'
    (org-lparse-bind-local-variables opt-plist)
    (org-odt-configure-outline-numbering
     (if org-export-with-section-numbers org-export-headline-levels 0)))

  ;; Write custom stlyes for source blocks
  (org-odt-insert-custom-styles-for-srcblocks
   (mapconcat
    (lambda (style)
      (format " %s\n" (cddr style)))
    hfy-user-sheet-assoc "")))

(defun org-odt-write-mimetype-file (format)
  ;; create mimetype file
  (let ((mimetype
	 (case format
	   (odt "application/vnd.oasis.opendocument.text")
	   (odf "application/vnd.oasis.opendocument.formula")
	   (t (error "Unknown OpenDocument backend %S" org-lparse-backend)))))
    (write-region mimetype nil (expand-file-name "mimetype"))
    mimetype))

(defun org-odt-finalize-outfile ()
  (org-odt-delete-empty-paragraphs))

(defun org-odt-delete-empty-paragraphs ()
  (goto-char (point-min))
  (let ((open "<text:p[^>]*>")
	(close "</text:p>"))
    (while (re-search-forward (format "%s[ \r\n\t]*%s" open close) nil t)
      (replace-match ""))))

(defcustom org-export-odt-convert-processes
  '(("BasicODConverter"
     ("soffice" "-norestore" "-invisible" "-headless"
      "\"macro:///BasicODConverter.Main.Convert(%I,%f,%O)\""))
    ("unoconv"
     ("unoconv" "-f" "%f" "-o" "%d" "%i")))
  "Specify a list of document converters and their usage.
The converters in this list are offered as choices while
customizing `org-export-odt-convert-process'.

This variable is an alist where each element is of the
form (CONVERTER-NAME CONVERTER-PROCESS).  CONVERTER-NAME is name
of the converter.  CONVERTER-PROCESS specifies the command-line
syntax of the converter and is of the form (CONVERTER-PROGRAM
ARG1 ARG2 ...).  CONVERTER-PROGRAM is the name of the executable.
ARG1, ARG2 etc are command line options that are passed to
CONVERTER-PROGRAM.  Format specifiers can be used in the ARGs and
they are interpreted as below:

%i input file name in full
%I input file name as a URL
%f format of the output file
%o output file name in full
%O output file name as a URL
%d output dir in full
%D output dir as a URL."
  :group 'org-export-odt
  :type
  '(choice
    (const :tag "None" nil)
    (alist :tag "Converters"
	   :key-type (string :tag "Converter Name")
	   :value-type (group (cons (string :tag "Executable")
				    (repeat (string :tag "Command line args")))))))

(defcustom org-export-odt-convert-process nil
  "Use this converter to convert from \"odt\" format to other formats.
During customization, the list of converter names are populated
from `org-export-odt-convert-processes'."
  :group 'org-export-odt
  :type '(choice :convert-widget
		 (lambda (w)
		   (apply 'widget-convert (widget-type w)
			  (eval (car (widget-get w :args)))))
		 `((const :tag "None" nil)
		   ,@(mapcar (lambda (c)
			       `(const :tag ,(car c) ,(car c)))
			     org-export-odt-convert-processes))))

(defcustom org-export-odt-convert-capabilities
  '(("Text"
     ("odt" "ott" "doc" "rtf")
     (("pdf" "pdf") ("odt" "odt") ("xhtml" "html") ("rtf" "rtf")
      ("ott" "ott") ("doc" "doc") ("ooxml" "xml") ("html" "html")))
    ("Web"
     ("html" "xhtml") (("pdf" "pdf") ("odt" "txt") ("html" "html")))
    ("Spreadsheet"
     ("ods" "ots" "xls" "csv")
     (("pdf" "pdf") ("ots" "ots") ("html" "html") ("csv" "csv")
      ("ods" "ods") ("xls" "xls") ("xhtml" "xhtml") ("ooxml" "xml")))
    ("Presentation"
     ("odp" "otp" "ppt")
     (("pdf" "pdf") ("swf" "swf") ("odp" "odp") ("xhtml" "xml")
      ("otp" "otp") ("ppt" "ppt") ("odg" "odg") ("html" "html"))))
  "Specify input and output formats of `org-export-odt-convert-process'.
More correctly, specify the set of input and output formats that
the user is actually interested in.

This variable is an alist where each element is of the
form (DOCUMENT-CLASS INPUT-FMT-LIST OUTPUT-FMT-ALIST).
INPUT-FMT-LIST is a list of INPUT-FMTs.  OUTPUT-FMT-ALIST is an
alist where each element is of the form (OUTPUT-FMT
OUTPUT-FILE-EXTENSION).

The variable is interpreted as follows:
`org-export-odt-convert-process' can take any document that is in
INPUT-FMT-LIST and produce any document that is in the
OUTPUT-FMT-LIST.  A document converted to OUTPUT-FMT will have
OUTPUT-FILE-EXTENSION as the file name extension.  OUTPUT-FMT
serves dual purposes:
- It is used for populating completion candidates during
  `org-export-odt-convert' commands.
- It is used as the value of \"%f\" specifier in
  `org-export-odt-convert-process'.

DOCUMENT-CLASS is used to group a set of file formats in
INPUT-FMT-LIST in to a single class.

Note that this variable inherently captures how LibreOffice based
converters work.  LibreOffice maps documents of various formats
to classes like Text, Web, Spreadsheet, Presentation etc and
allow document of a given class (irrespective of it's source
format) to be converted to any of the export formats associated
with that class.

See default setting of this variable for an typical
configuration."
  :group 'org-export-odt
  :type
  '(choice
    (const :tag "None" nil)
    (alist :key-type (string :tag "Document Class")
	   :value-type
	   (group (repeat :tag "Input formats" (string :tag "Input format"))
		  (alist :tag "Output formats"
			 :key-type (string :tag "Output format")
			 :value-type
			 (group (string :tag "Output file extension")))))))

;;;###autoload
(defun org-export-odt-convert (&optional in-file out-fmt prefix-arg)
  "Convert IN-FILE to format OUT-FMT using a command line converter.
IN-FILE is the file to be converted.  If unspecified, it defaults
to variable `buffer-file-name'.  OUT-FMT is the desired output
format.  Use `org-export-odt-convert-process' as the converter.
If PREFIX-ARG is non-nil then the newly converted file is opened
using `org-open-file'."
  (interactive
   (append (org-lparse-convert-read-params) current-prefix-arg))
  (org-lparse-do-convert in-file out-fmt prefix-arg))

(defun org-odt-get (what &optional opt-plist)
  (case what
    (BACKEND 'odt)
    (EXPORT-DIR (org-export-directory :html opt-plist))
    (FILE-NAME-EXTENSION "odt")
    (EXPORT-BUFFER-NAME "*Org ODT Export*")
    (ENTITY-CONTROL org-odt-entity-control-callbacks-alist)
    (ENTITY-FORMAT org-odt-entity-format-callbacks-alist)
    (INIT-METHOD 'org-odt-init-outfile)
    (FINAL-METHOD 'org-odt-finalize-outfile)
    (SAVE-METHOD 'org-odt-save-as-outfile)
    (CONVERT-METHOD
     (and org-export-odt-convert-process
	  (cadr (assoc-string org-export-odt-convert-process
			      org-export-odt-convert-processes t))))
    (CONVERT-CAPABILITIES
     (and org-export-odt-convert-process
	  (cadr (assoc-string org-export-odt-convert-process
			      org-export-odt-convert-processes t))
	  org-export-odt-convert-capabilities))
    (TOPLEVEL-HLEVEL 1)
    (SPECIAL-STRING-REGEXPS org-export-odt-special-string-regexps)
    (INLINE-IMAGES 'maybe)
    (INLINE-IMAGE-EXTENSIONS '("png" "jpeg" "jpg" "gif" "svg"))
    (PLAIN-TEXT-MAP '(("&" . "&amp;") ("<" . "&lt;") (">" . "&gt;")))
    (TABLE-FIRST-COLUMN-AS-LABELS nil)
    (FOOTNOTE-SEPARATOR (org-lparse-format 'FONTIFY "," 'superscript))
    (CODING-SYSTEM-FOR-WRITE 'utf-8)
    (CODING-SYSTEM-FOR-SAVE 'utf-8)
    (t (error "Unknown property: %s"  what))))

(defvar org-lparse-latex-fragment-fallback) ; set by org-do-lparse
(defun org-export-odt-do-preprocess-latex-fragments ()
  "Convert LaTeX fragments to images."
  (let* ((latex-frag-opt (plist-get org-lparse-opt-plist :LaTeX-fragments))
	 (latex-frag-opt		;  massage the options
	  (or (and (member latex-frag-opt '(mathjax t))
		   (not (and (fboundp 'org-format-latex-mathml-available-p)
			     (org-format-latex-mathml-available-p)))
		   (prog1 org-lparse-latex-fragment-fallback
		     (org-lparse-warn
		      (concat
		       "LaTeX to MathML converter not available. "
		       (format "Using %S instead."
			       org-lparse-latex-fragment-fallback)))))
	      latex-frag-opt))
	 cache-dir display-msg)
    (cond
     ((eq latex-frag-opt 'dvipng)
      (setq cache-dir "ltxpng/")
      (setq display-msg "Creating LaTeX image %s"))
     ((member latex-frag-opt '(mathjax t))
      (setq latex-frag-opt 'mathml)
      (setq cache-dir "ltxmathml/")
      (setq display-msg "Creating MathML formula %s")))
    (when (and org-current-export-file)
      (org-format-latex
       (concat cache-dir (file-name-sans-extension
			  (file-name-nondirectory org-current-export-file)))
       org-current-export-dir nil display-msg
       nil nil latex-frag-opt))))

(defadvice org-format-latex-as-mathml
  (after org-odt-protect-latex-fragment activate)
  "Encode LaTeX fragment as XML.
Do this when translation to MathML fails."
  (when (or (not (> (length ad-return-value) 0))
	    (get-text-property 0 'org-protected ad-return-value))
    (setq ad-return-value
	  (org-propertize (org-odt-encode-plain-text (ad-get-arg 0))
			  'org-protected t))))

(defun org-export-odt-preprocess-latex-fragments ()
  (when (equal org-export-current-backend 'odt)
    (org-export-odt-do-preprocess-latex-fragments)))

(defun org-export-odt-preprocess-label-references ()
  (goto-char (point-min))
  (let (label label-components category value pretty-label)
    (while (re-search-forward "\\\\ref{\\([^{}\n]+\\)}" nil t)
      (org-if-unprotected-at (match-beginning 1)
	(replace-match
	 (let ((org-lparse-encode-pending t)
	       (label (match-string 1)))
	   ;; markup generated below is mostly an eye-candy.  At
	   ;; pre-processing stage, there is no information on which
	   ;; entity a label reference points to.  The actual markup
	   ;; is generated as part of `org-odt-fixup-label-references'
	   ;; which gets called at the fag end of export.  By this
	   ;; time we would have seen and collected all the label
	   ;; definitions in `org-odt-entity-labels-alist'.
	   (org-odt-format-tags
	    "<text:sequence-ref text:ref-name=\"%s\"/>" ""
	    (org-add-props label '(org-protected t)))) t t)))))

;; process latex fragments as part of
;; `org-export-preprocess-after-blockquote-hook'. Note that this hook
;; is the one that is closest and well before the call to
;; `org-export-attach-captions-and-attributes' in
;; `org-export-preprocess-stirng'.  The above arrangement permits
;; captions, labels and attributes to be attached to png images
;; generated out of latex equations.
(add-hook 'org-export-preprocess-after-blockquote-hook
	  'org-export-odt-preprocess-latex-fragments)

(defun org-export-odt-preprocess (parameters)
  (org-export-odt-preprocess-label-references))

(declare-function archive-zip-extract "arc-mode.el" (archive name))
(defun org-odt-zip-extract-one (archive member &optional target)
  (require 'arc-mode)
  (let* ((target (or target default-directory))
	 (archive (expand-file-name archive))
	 (archive-zip-extract
	  (list "unzip" "-qq" "-o" "-d" target))
	 exit-code command-output)
    (setq command-output
	  (with-temp-buffer
	    (setq exit-code (archive-zip-extract archive member))
	    (buffer-string)))
    (unless (zerop exit-code)
      (message command-output)
      (error "Extraction failed"))))

(defun org-odt-zip-extract (archive members &optional target)
  (when (atom members) (setq members (list members)))
  (mapc (lambda (member)
	  (org-odt-zip-extract-one archive member target))
	members))

(defun org-odt-copy-styles-file (&optional styles-file)
  ;; Non-availability of styles.xml is not a critical error. For now
  ;; throw an error purely for aesthetic reasons.
  (setq styles-file (or styles-file
			org-export-odt-styles-file
			(expand-file-name "styles/OrgOdtStyles.xml"
					  org-odt-data-dir)
			(error "org-odt: Missing styles file?")))
  (cond
   ((listp styles-file)
    (let ((archive (nth 0 styles-file))
	  (members (nth 1 styles-file)))
      (org-odt-zip-extract archive members)
      (mapc
       (lambda (member)
	 (when (org-file-image-p member)
	   (let* ((image-type (file-name-extension member))
		  (media-type (format "image/%s" image-type)))
	     (org-odt-create-manifest-file-entry media-type member))))
       members)))
   ((and (stringp styles-file) (file-exists-p styles-file))
    (let ((styles-file-type (file-name-extension styles-file)))
      (cond
       ((string= styles-file-type "xml")
	(copy-file styles-file "styles.xml" t))
       ((member styles-file-type '("odt" "ott"))
	(org-odt-zip-extract styles-file "styles.xml")))))
   (t
    (error (format "Invalid specification of styles.xml file: %S"
		   org-export-odt-styles-file))))

  ;; create a manifest entry for styles.xml
  (org-odt-create-manifest-file-entry "text/xml" "styles.xml"))

(defvar org-export-odt-factory-settings
  "d4328fb9d1b6cb211d4320ff546829f26700dc5e"
  "SHA1 hash of OrgOdtStyles.xml.")

(defun org-odt-configure-outline-numbering (level)
  "Outline numbering is retained only upto LEVEL.
To disable outline numbering pass a LEVEL of 0."
  (goto-char (point-min))
  (let ((regex
	 "<text:outline-level-style\\([^>]*\\)text:level=\"\\([^\"]*\\)\"\\([^>]*\\)>")
	(replacement
	 "<text:outline-level-style\\1text:level=\"\\2\" style:num-format=\"\">"))
    (while (re-search-forward regex nil t)
      (when (> (string-to-number (match-string 2)) level)
	(replace-match replacement t nil))))
  (save-buffer 0))

;;;###autoload
(defun org-export-as-odf (latex-frag &optional odf-file)
  "Export LATEX-FRAG as OpenDocument formula file ODF-FILE.
Use `org-create-math-formula' to convert LATEX-FRAG first to
MathML.  When invoked as an interactive command, use
`org-latex-regexps' to infer LATEX-FRAG from currently active
region.  If no LaTeX fragments are found, prompt for it.  Push
MathML source to kill ring, if `org-export-copy-to-kill-ring' is
non-nil."
  (interactive
   `(,(let (frag)
	(setq frag (and (setq frag (and (region-active-p)
					(buffer-substring (region-beginning)
							  (region-end))))
			(loop for e in org-latex-regexps
			      thereis (when (string-match (nth 1 e) frag)
					(match-string (nth 2 e) frag)))))
	(read-string "LaTeX Fragment: " frag nil frag))
     ,(let ((odf-filename (expand-file-name
			   (concat
			    (file-name-sans-extension
			     (or (file-name-nondirectory buffer-file-name)))
			    "." "odf")
			   (file-name-directory buffer-file-name))))
	(message "default val is %s"  odf-filename)
	(read-file-name "ODF filename: " nil odf-filename nil
			(file-name-nondirectory odf-filename)))))
  (let* ((org-lparse-backend 'odf)
	 org-lparse-opt-plist
	 (filename (or odf-file
		       (expand-file-name
			(concat
			 (file-name-sans-extension
			  (or (file-name-nondirectory buffer-file-name)))
			 "." "odf")
			(file-name-directory buffer-file-name))))
	 (buffer (find-file-noselect (org-odt-init-outfile filename)))
	 (coding-system-for-write 'utf-8)
	 (save-buffer-coding-system 'utf-8))
    (set-buffer buffer)
    (set-buffer-file-coding-system coding-system-for-write)
    (let ((mathml (org-create-math-formula latex-frag)))
      (unless mathml (error "No Math formula created"))
      (insert mathml)
      (or (org-export-push-to-kill-ring
	   (upcase (symbol-name org-lparse-backend)))
	  (message "Exporting... done")))
    (org-odt-save-as-outfile filename nil)))

;;;###autoload
(defun org-export-as-odf-and-open ()
 "Export LaTeX fragment as OpenDocument formula and immediately open it.
Use `org-export-as-odf' to read LaTeX fragment and OpenDocument
formula file."
  (interactive)
  (org-lparse-and-open
   nil nil nil (call-interactively 'org-export-as-odf)))

(provide 'org-odt)

;;; org-odt.el ends here
