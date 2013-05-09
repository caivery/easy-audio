;; Copyright (c) 2012-2013, Vasily Postnicov
;; All rights reserved.

;; Redistribution and use in source and binary forms, with or without
;; modification, are permitted provided that the following conditions are met: 

;; 1. Redistributions of source code must retain the above copyright notice, this
;;   list of conditions and the following disclaimer. 
;; 2. Redistributions in binary form must reproduce the above copyright notice,
;;   this list of conditions and the following disclaimer in the documentation
;;   and/or other materials provided with the distribution. 

;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
;; ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
;; WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
;; DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
;; ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
;; (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
;; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
;; ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
;; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;; SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

(defpackage easy-music.bitreader
  (:use #:cl)
  (:nicknames #:bitreader)
  (:export #:non-negative-fixnum ; Types
           #:positive-fixnum
           #:bit-counter
           #:ub4
           #:ub8
           #:simple-ub8-vector

           #:bitreader-eof       ; Conditions

           #:reader              ; Reader structure and accessors
           #:make-reader
           #:reader-ibit
           #:reader-ibyte
           #:reader-end
           #:reader-stream
           #:reader-buffer
           
           #:reset-counters      ; Helper functions & macros
           #:move-forward
           #:fill-buffer
           #:can-not-read
           #:read-bits-loop

           #:read-bit            ; "End user" functions
           #:read-octet
           #:read-octet-vector
           #:read-to-byte-alignment
           #:reader-position
           #:peek-octet
           #:reader-length))

(defpackage easy-music.bitreader.be-fixnum
  (:use #:cl #:bitreader)
  (:nicknames #:bitreader.be-fixnum)
  (:export #:read-bits))

(defpackage easy-music.bitreader.le-fixnum
  (:use #:cl #:bitreader)
  (:nicknames #:bitreader.le-fixnum)
  (:export #:read-bits))

(defpackage easy-music.bitreader.be-bignum
  (:use #:cl #:bitreader)
  (:nicknames #:bitreader.be-bignum)
  (:export #:read-bits))

(defpackage easy-music.bitreader.le-bignum
  (:use #:cl #:bitreader)
  (:nicknames #:bitreader.le-bignum)
  (:export #:read-bits))