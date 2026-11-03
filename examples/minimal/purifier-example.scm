(module purifier-example (answer)
 (import scheme (chicken base) srfi-13)
 (define (answer)
  (string->number (string-filter char-numeric? "answer=42"))))
