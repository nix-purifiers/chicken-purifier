(import scheme (chicken base) (chicken io) (chicken file) (chicken pathname) (chicken process-context))
(let ((args (command-line-arguments)))
 (for-each
  (lambda (identity)
   (let* ((name (car identity)) (version (cadr identity))
          (info (call-with-input-file (make-pathname (car args) name (if (pair? (cddr args)) (caddr args) "egg-info")) read)))
    (unless (equal? (cadr (assoc 'version info)) version)
      (error "Native installed egg version differs from lock" name version info))))
  (call-with-input-file (cadr args) read)))
