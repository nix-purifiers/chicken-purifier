"""Instrument the pinned installer without replacing its resolver."""

from pathlib import Path

p = Path("chicken-install.scm")
s = p.read_text()
marker = '(include "purifier-transport.scm")'
if marker not in s:
    s = s.replace("(define (usage code)", marker + "\n\n(define (usage code)")
    old = "(main (command-line-arguments))"
    assert old in s
    s = s.replace(
        old,
        """(main (command-line-arguments))
(when (get-environment-variable "CHICKEN_PURIFIER_CAPTURE")
 (with-output-to-file (get-environment-variable "CHICKEN_PURIFIER_CAPTURE")
  (lambda ()
   (display "{\\\"eggs\\\":")
   (purifier-json
    (map (lambda (egg)
      (let* ((name (car egg)) (dir (cadr egg))
             (info (validate-egg-info (load-egg-info (make-pathname dir name +egg-extension+))))
             (vfile (make-pathname (make-pathname cache-metadata-directory name) +version-file+))
             (version (or (caddr egg) (and (file-exists? vfile) (with-input-from-file vfile read)) (get-egg-property info 'version))))
       (list name dir version))) canonical-eggs))
   (display ",\\\"dependencies\\\":") (purifier-json dependencies)
   (display ",\\\"order\\\":") (purifier-json (map car (order-installed-eggs)))
   (display ",\\\"responses\\\":") (purifier-json purifier-responses)
   (display "}"))))""",
    )
    p.write_text(s)
native = s[s.index("(define (string-suffix?") : s.index("(define (d flag")]
imports = """(import scheme (chicken base) (chicken condition) (chicken file)
 (chicken io) (chicken irregex) (chicken port) (chicken process-context)
 (chicken string) (chicken tcp) (chicken platform))
(define (d . args) #f)
"""
Path("purifier-unpack.scm").write_text(
    imports
    + native
    + """
(include "@download@")
(let* ((args (command-line-arguments)) (source (car args)) (dest (cadr args)))
 (create-directory dest #t)
 (print (http-retrieve-files (open-input-file source) (open-output-string) dest)))
"""
)
