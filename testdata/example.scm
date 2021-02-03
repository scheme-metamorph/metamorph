(define (fac n)
    (define zerod 0)
    (define (foo x) (bar x))
    (define (bar y) (foo y))
    (define ident (+ zerod 1))
    (if (> n 0) 
        (* n (fac (- n 1)))
        ident))
(define (q x . y) (append x y))
(define (test x y . z) (cons (+ x y) z))
(test 1 4 3 5 1 "String")
(set! test fac)
(test 2)