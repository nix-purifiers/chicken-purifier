(import scheme (chicken base) (chicken gc) (chicken foreign)
        (chicken platform) purifier-example)
(define-external (purifier_answer (int value)) int
  (let ((values (make-vector 10000 value)))
    (gc)
    (+ (vector-ref values 9999) (answer))))
(return-to-host)
