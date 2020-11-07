
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; MODULE      : ref-edit.scm
;; DESCRIPTION : editing routines for references
;; COPYRIGHT   : (C) 2020  Joris van der Hoeven
;;
;; This software falls under the GNU general public license version 3 or later.
;; It comes WITHOUT ANY WARRANTY WHATSOEVER. For details, see the file LICENSE
;; in the root directory or <http://www.gnu.org/licenses/gpl-3.0.html>.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(texmacs-module (link ref-edit)
  (:use (utils edit variants)
        (generic generic-edit)
        (generic document-part)
        (text text-drd)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Finding all standard types of labels/references in a document
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(tm-define (label-context? t)
  (tree-in? t (label-tag-list)))

(tm-define (reference-context? t)
  (tree-in? t (reference-tag-list)))

(tm-define (citation-context? t)
  (tree-in? t (citation-tag-list)))

(tm-define (tie-context? t)
  (or (label-context? t) (reference-context? t) (citation-context? t)))

(define ((named-context? pred? . ids) t)
  (and (pred? t)
       (exists? (lambda (id)
                  (exists? (cut tm-equal? <> id) (tm-children t)))
                ids)))

(define (and-nnull? l)
  (and (nnull? l) l))

(tm-define (search-labels t)
  (tree-search t label-context?))

(tm-define (search-label t id)
  (tree-search t (named-context? label-context? id)))

(tm-define (search-references t)
  (tree-search t reference-context?))

(tm-define (search-reference t id)
  (tree-search t (named-context? reference-context? id)))

(tm-define (search-citations t)
  (tree-search t citation-context?))

(tm-define (search-citation t id)
  (tree-search t (named-context? citation-context? id)))

(tm-define (search-tie t id)
  (let* ((id1 (if (string-starts? id "bib-") (string-drop id 4) id))
         (id2 (string-append "bib-" id1)))
    (tree-search t (named-context? tie-context? id1 id2))))

(tm-define (search-duplicate-labels t)
  (let* ((labs (search-labels t))
         (labl (map (lambda (lab) (tm->string (tm-ref lab 0))) labs))
         (freq (list->frequencies labl))
         (filt (lambda (lab)
                 (with f (ahash-ref freq (tm->string (tm-ref lab 0)))
                   (> (or f 0) 1)))))
    (list-filter labs filt)))

(define (tm-keys t)
  (cond ((tm-in? t '(cite-detail)) (list (tm-ref t 0)))
        (else (tm-children t))))

(define ((tie-in? t) ref)
  (with l (map tm->string (tm-keys ref))
    (forall? (lambda (s) (ahash-ref t s)) l)))

(define (strip-bib s)
  (if (string-starts? s "bib-") (string-drop s 4) s))

(define (set-of-labels t)
  (let* ((labs (search-labels t))
         (labl (map (lambda (t) (strip-bib (tm->string (tm-ref t 0)))) labs))
         (labt (list->ahash-set labl)))
    (if (project-attached?)
        (let* ((glob (list->ahash-set (map strip-bib (list-references* #t))))
               (loc  (list->ahash-set (map strip-bib (list-references)))))
          (ahash-table-append (ahash-table-difference glob loc) labt))
        labt)))

(tm-define (search-broken-references t)
  (let* ((refs (search-references t))
         (labt (set-of-labels t)))
    (list-filter refs (non (tie-in? labt)))))

(tm-define (search-broken-citations t)
  (let* ((refs (search-citations t))
         (labt (set-of-labels t)))
    (list-filter refs (non (tie-in? labt)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Navigation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(tm-define (list-go-to-first l)
  (tree-go-to (car l) :end))

(tm-define (list-go-to-last l)
  (tree-go-to (cAr l) :end))

(define (list-go-to-previous* l)
  (when (nnull? l)
    (if (path-less? (tree->path (car l)) (tree->path (cursor-tree)))
        (tree-go-to (car l) :end)
        (list-go-to-previous* (cdr l)))))

(tm-define (list-go-to-previous l)
  (list-go-to-previous* (reverse l)))

(tm-define (list-go-to-next l)
  (when (nnull? l)
    (if (path-less? (tree->path (cursor-tree)) (tree->path (car l)))
        (tree-go-to (car l) :end)
        (list-go-to-next (cdr l)))))

(tm-define (list-go-to l dir)
  (cond ((nlist? l) (noop))
        ((== dir :first) (list-go-to-first l))
        ((== dir :last) (list-go-to-last l))
        ((== dir :previous) (list-go-to-previous l))
        ((== dir :next) (list-go-to-next l))))

(define current-id '(none))

(tm-define (tie-id)
  (and-with t (tree-innermost tie-context? #t)
    (or (and (exists? (cut tm-equal? <> current-id) (tm-children t))
             current-id)
        (and (tm-atomic? (tm-ref t 0))
             (with key (tm->string (tm-ref t 0))
               (if (string-starts? key "bib-") (string-drop key 4) key))))))

(tm-define (same-ties)
  (and-nnull? (search-tie (buffer-tree) (tie-id))))

(tm-define (duplicate-labels)
  (and-nnull? (search-duplicate-labels (buffer-tree))))

(tm-define (broken-references)
  (and-nnull? (search-broken-references (buffer-tree))))

(tm-define (broken-citations)
  (and-nnull? (search-broken-citations (buffer-tree))))

(tm-define (go-to-same-tie dir)
  (:applicable (same-ties))
  (set! current-id (tie-id))
  (list-go-to (same-ties) dir))

(tm-define (go-to-duplicate-label dir)
  (:applicable (duplicate-labels))
  (list-go-to (duplicate-labels) dir))

(tm-define (go-to-broken-reference dir)
  (:applicable (broken-references))
  (list-go-to (broken-references) dir))

(tm-define (go-to-broken-citation dir)
  (:applicable (broken-citations))
  (list-go-to (broken-citations) dir))

(tm-define (special-extremal t forwards?)
  (:require (focus-label t))
  (with lab (focus-label t)
    (tree-go-to lab :end)
    (special-extremal lab forwards?)))

(tm-define (special-incremental t forwards?)
  (:require (focus-label t))
  (with lab (focus-label t)
    (tree-go-to lab :end)
    (special-incremental lab forwards?)))

(tm-define (special-extremal t forwards?)
  (:require (tie-context? t))
  (go-to-same-tie (if forwards? :last :first)))

(tm-define (special-incremental t forwards?)
  (:require (tie-context? t))
  (go-to-same-tie (if forwards? :next :previous)))

(tm-define (special-navigate t dir)
  (:require (label-context? t))
  (go-to-duplicate-label dir))

(tm-define (special-navigate t dir)
  (:require (reference-context? t))
  (go-to-broken-reference dir))

(tm-define (special-navigate t dir)
  (:require (citation-context? t))
  (go-to-broken-citation dir))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Preview of the content that a reference points to
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (preview-context? t)
  (or (tree-is? t 'row)
      (and (tree-up t) (tree-is? (tree-up t) 'document))))

(define (math-context? t)
  (tree-in? t '(equation equation* eqnarray eqnarray*)))

(define (uncell t)
  (if (tm-func? t 'cell 1) (tm-ref t 0) t))

(define (clean-preview t)
  (cond ((tm-is? t 'document)
         `(document ,@(map clean-preview (tm-children t))))
        ((tm-is? t 'concat)
         (apply tmconcat (map clean-preview (tm-children t))))
        ((tm-in? t (section-tag-list))
         (with l (symbol-append (tm-label t) '*)
           `(,l ,@(tm-children t))))
        ((tm-in? t '(label item item* bibitem bibitem* eq-number)) "")
        ((or (tm-func? t 'equation 1) (tm-func? t 'equation* 1))
         `(equation* ,(clean-preview (tm-ref t 0))))
        ((tm-in? t '(eqnarray eqnarray* tformat table row cell))
         `(,(tm-label t) ,@(map clean-preview (tm-children t))))
        (else t)))

(define (preview-expand-context? t)
  (tree-in? t '(theorem proposition lemma corollary conjecture
                theorem* proposition* lemma* corollary* conjecture*
                definition axiom
                definition* axiom*)))

(define (label-preview t)
  (and-with doc (tree-search-upwards t preview-context?)
    (with math? (tree-search-upwards t math-context?)
      (when (and (tree-up doc) (tree-up (tree-up doc))
                 (tree-is? (tree-up doc) 'document)
                 (preview-expand-context? (tree-up (tree-up doc))))
        (set! doc (tree-up doc)))
      (when (tm-is? doc 'row)
        (set! doc (apply tmconcat (map uncell (tm-children doc)))))
      (set! doc (clean-preview doc))
      (when math?
        (set! doc `(with "math-display" "true" (math ,doc))))
      `(preview-balloon ,doc))))

(tm-define (ref-preview id)
  (and-with l (and-nnull? (search-label (buffer-tree) id))
    (label-preview (car l))))

(define (preview-init? p)
  (and-with x (and (pair? p) (car p))
    (and (string? x)
         (not (string-starts? x "page-"))
         (nin? x (list "zoom-factor" "full-screen-mode")))))

(tm-define (preview-reference body body*)
  (:secure #t)
  (and-with ref (tree-up body)
    (with (x1 y1 x2 y2) (tree-bounding-rectangle ref)
      (and-let* ((packs (get-style-list))
                 (pre (document-get-preamble (buffer-tree)))
                 (id (and (tree-atomic? body*) (tree->string body*)))
                 (balloon (ref-preview id))
                 (zf (get-window-zoom-factor))
                 (sf (/ 4.0 zf))
                 (mag (number->string (/ zf 1.5)))
                 (inits* (map cdr (cdr (tm->stree (get-all-inits)))))
                 (inits (list-filter inits* preview-init?))
                 (env (apply append inits))
                 (balloon* `(with ,@env "magnification" ,mag ,balloon))
                 (w (widget-texmacs-output
                     `(surround (hide-preamble ,pre) "" ,balloon*)
                     `(style (tuple ,@packs)))))
        (show-balloon w x1 (- y1 1280))))))
