;; Copyright (c) 2012-2014, Vasily Postnicov
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

(in-package :easy-audio.wv)

(defvar *residual-buffers* nil
  "Works with @c(make-output-buffers) to reduce consing.
Bind this variable to output buffers when you read multiple
block in a loop to reduce consing.")

(defun get-med (median)
  (declare (optimize (speed 3))
           (type (ub 32) median))
  (1+ (ash median -4)))

(defun inc-med (median amount)
  (declare (optimize (speed 3))
           (type (ub 32) median amount))
  (+ median (* 5 (floor (+ amount median) amount))))

(defun dec-med (median amount)
  (declare (optimize (speed 3))
           (type (ub 32) median amount))
  (- median (* 2 (floor (+ amount median -2) amount))))

(defun decode-residual (wv-block)
  (declare (optimize (speed 3)))
  (if (flag-set-p wv-block +flags-hybrid-mode+)
      (error 'block-error :message "Cannot work with hybrid mode"))
  (let ((metadata-residual (find 'metadata-wv-residual (the list (block-metadata wv-block))
                                 :key #'type-of))
        (channels (block-channels wv-block))
        (samples (block-block-samples wv-block)))

    (if metadata-residual
        (let (#|(residual (loop for i below channels collect
                             (let ((residual-buffer (nth i *residual-buffers*)))
                               (if (and residual-buffer
                                        (= (length (the (sa-sb 32) residual-buffer)) samples))
                                   (map-into residual-buffer (lambda (x) (declare (ignore x)) 0) residual-buffer)
                                   (make-array samples
                                               :element-type '(sb 32)
                                               :initial-element 0)))))|#
              (residual (if *residual-buffers*
                            (mapc (lambda (buffer)
                                    (declare (type (sa-sb 32) buffer))
                                    (fill buffer 0))
                                  *residual-buffers*)
                            (loop repeat channels collect (make-array samples
                                                                      :element-type '(sb 32)
                                                                      :initial-element 0))))
              (coded-residual-reader (metadata-residual-reader metadata-residual))
              (medians (block-entropy-median wv-block))
              holding-one holding-zero zero-run-met)

          (do* ((i       0)
                (sample  0 (ash i (- 1 channels)))
                (channel 0 (logand i (1- channels))))
               ((= sample samples) sample)
            (declare (type (ub 32) i sample channel))

            (if (> sample samples)
                (error 'block-error :message "Accidentally read too much samples"))
            (cond
              ((and (< (aref (the (sa-ub 32) (first medians)) 0) 2)
                    (or (null (second medians))
                        (< (aref (the (sa-ub 32) (second medians)) 0) 2))
                    (not holding-one)
                    (not holding-zero)
                    (not zero-run-met))
               ;; Run of zeros - do nothing
               (let ((zero-length (read-elias-code coded-residual-reader)))
                 (when (/= zero-length 0)
                   (incf i zero-length)
                   (mapc (lambda (median)
                           (declare (type (sa-ub 32) median))
                           (fill median 0)) medians)))
               (setq zero-run-met t))

              (t
               (setq zero-run-met nil)
               (let ((ones-count 0))
                 (declare (type non-negative-fixnum ones-count))
                 (cond
                   (holding-zero (setq holding-zero nil))
                   (t
                    (setq ones-count (read-unary-coded-integer coded-residual-reader #.(1+ 16)))
                    (when (>= ones-count 16)
                      (if (= ones-count 17) (error 'block-error :message "Invalid residual code"))
                      (incf ones-count (read-elias-code coded-residual-reader)))
                    (psetq
                     holding-one (/= (logand ones-count 1) 0)
                     ones-count (+ (ash ones-count -1) (if holding-one 1 0)))
                    (setq holding-zero (not holding-one))))

                 (let ((median (nth channel medians))
                       (low 0)
                       (high 0))
                   (declare (type (sb 32) low high)
                            (type (sa-ub 32) median))
                   (cond
                     ((= ones-count 0)
                      (setq high (1- (get-med (aref median 0))))
                      (setf (aref median 0) (dec-med (aref median 0) 128)))
                     (t
                      (setq low (get-med (aref median 0)))
                      (setf (aref median 0) (inc-med (aref median 0) 128))
                      (cond
                        ((= ones-count 1)
                         (setq high (+ low (get-med (aref median 1)) -1))
                         (setf (aref median 1) (dec-med (aref median 1) 64)))
                        (t
                         (setq low (+ low (get-med (aref median 1))))
                         (setf (aref median 1) (inc-med (aref median 1) 64))
                         (cond
                           ((= ones-count 2)
                            (setq high (+ low (get-med (aref median 2)) -1))
                            (setf (aref median 2) (dec-med (aref median 2) 32)))
                           (t
                            (setq low (+ low (the (sb 32)
                                                  (* (get-med (aref median 2))
                                                     (- ones-count 2))))
                                  high (+ low (get-med (aref median 2)) -1))
                            (setf (aref median 2) (inc-med (aref median 2) 32))))))))
                   (incf low (read-code coded-residual-reader (- high low)))
                   (setf (aref (the (sa-sb 32) (nth channel residual)) sample)
                         (if (= (residual-read-bit coded-residual-reader) 1)
                             (lognot low) low))))
               (incf i))))
          (read-to-byte-alignment coded-residual-reader)
          ;; For some reason residual reader looses some useful ("actual") data at the end
          ;; and it seems to be OK. But check if we loose too much
          (if (> (- (the (ub 24) (reader-length coded-residual-reader))
                    (the (ub 24) (reader-position coded-residual-reader))) 1)
              (error 'block-error :message "Too much useful data is lost in residual reader"))
          (setf (block-residual wv-block) residual))))
  wv-block)

;; Coding guide to myself:

;; 1) When I need to check if flag (bit) is set, use bit-set-p function
;; 2) When I need to choose which flag in the set is set, use cond
;;    macro with (logand x mask)
;; 3) When I need to get a value from flags using masks and shifts, use
;;    automatically generated special functions

(defreader read-wv-block%% ((make-wv-block))
    (block-id            (:octets 4) :endianness :big)
    (block-size          (:octets 4) :endianness :little)
    (block-version       (:octets 2) :endianness :little)
    (block-track-number  (:octets 1))
    (block-index-number  (:octets 1))
    (block-total-samples (:octets 4) :endianness :little)
    (block-block-index   (:octets 4) :endianness :little)
    (block-block-samples (:octets 4) :endianness :little)
    (block-flags         (:octets 4) :endianness :little)
    (block-crc           (:octets 4) :endianness :little))

(defun read-wv-block% (reader)
  (declare (optimize (speed 3)))
  (let ((wv-block (read-wv-block%% reader)))
    (if (/= (block-id wv-block) +wv-id+)
        (error 'lost-sync :message "WavPack ckID /= 'wvpk'"))

    (let ((version (block-version wv-block)))
      (if (or (< version #x402) ; FIXME: is this range inclusive?
              (> version #x410))
          (error 'block-error :message "Unsupported WavPack block version")))

    (if (flag-set-p wv-block +flags-reserved-zero+)
        ;; Specification says we should "refuse to decode if set"
        (error 'block-error :message "Reserved flag is set to 1"))

    (let ((sub-blocks-size (- (block-size wv-block) 24))
          (*current-block* wv-block))
      (if (< sub-blocks-size 0)
          (error 'block-error :message "Sub-blocks size is less than 0"))
      (loop with bytes-read fixnum = 0
         while (< bytes-read sub-blocks-size)
         for metadata = (read-metadata reader)
         do (incf bytes-read (+ 1 (if (bit-set-p (metadata-id metadata)
                                                 +meta-id-large-block+) 3 1)
                                (the (ub 24) (metadata-size metadata))))
           (push metadata (block-metadata wv-block))
         finally (if (> bytes-read sub-blocks-size)
                     (error 'block-error :message "Read more sub-block bytes than needed"))))

    (decode-residual wv-block)))

(defun read-wv-block (reader)
  "Read the next block in the stream. @c(reader)'s position must be set to the
beginning of this block explicitly (e.g. by calling @c(restore-sync))"
  (restart-case
      (read-wv-block% reader)
    (read-new-block-single ()
        :report "Restore sync and read a new block"
        (restore-sync reader)
        (read-wv-block reader))))

(defun restore-sync (reader)
  "Restore the reader's position to the first occurring
   block in the stream"
  (peek-octet reader +wv-id/first-octet+)
  (let ((position (reader-position reader)))
    (handler-case
        (prog1
            (block-block-index (read-wv-block reader))
          (reader-position reader position))
      (lost-sync ()
        (reader-position reader (1+ position))
        (restore-sync reader)))))

(defun make-output-buffers (reader)
  "Make output buffers to bind them to @c(*residual-buffers*) to reduce consing."
  (let ((position (reader-position reader))
        (first-block (read-wv-block reader)))
    (multiple-value-prog1
        (values
         (loop repeat (block-channels first-block) collect
              (make-array (block-block-samples first-block) :element-type '(sb 32)))
         (if (flag-set-p first-block +flags-shifted-int+)
             (loop repeat (block-channels first-block) collect
                  (make-array (block-block-samples first-block) :element-type '(sb 32)))))
      (reader-position reader position))))

(defmacro with-output-buffers ((reader) &body body)
  "Calls to @c(read-wv-block), @c(restore-sync) etc. can be done inside this macro to
avoid unnecessary consing if all WavPack blocks in the stream contain the same number
of samples and have the same number of channels."
  `(multiple-value-bind (*residual-buffers* *wvx-buffers*)
       (make-output-buffers ,reader)
     ,@body))

(defun seek-sample (reader number)
  (declare (type (integer 0) number))
  "Set reader position to beginning of the block
   which contains a sample with the specified number.
   Works for readers associated with files.
   Return a position of the sample in the block"

  ;; Reset position of the reader
  (reader-position reader 0)
  (restore-sync reader)

  (let* ((file-length (reader-length reader))
         (test-block (read-wv-block reader))
         (total-samples (block-total-samples test-block))
         (block-samples (block-block-samples test-block)))

    (if (> number total-samples)
        (error 'wavpack-error
               :message "Requested sample number is too big"))

    (multiple-value-bind (complete-blocks remainder)
        (floor number block-samples)
      (let ((block-starting-number (* block-samples complete-blocks)))
        (labels ((binary-search (start end)
                   (let* ((middle (+ start (floor (- end start) 2)))
                          (first-half (progn
                                        (reader-position reader start)
                                        (restore-sync reader)))
                          (second-half (progn
                                         (reader-position reader (1- middle))
                                         (restore-sync reader))))
                     (if (< block-starting-number first-half)
                         (error 'wavpack-error
                                :message "Seeking error: wrong half chosen"))
                     (cond
                       ((< block-starting-number second-half)
                        (binary-search start middle))
                       ((> block-starting-number second-half)
                        (binary-search middle end))
                       (t t)))))
          (binary-search 0 file-length))
        remainder))))

(defun open-wv (stream)
  "Return @c(bitreader) handle of Wavpack stream"
  (make-reader-from-stream stream))

(defmacro with-open-wv ((reader name &rest options) &body body)
  "Binds READER to an open wavpack stream associated with
   file with the name NAME"
  (let ((stream (gensym)))
    `(let* ((,stream (apply #'open ,name :element-type '(ub 8) ,options))
            (,reader (open-wv ,stream)))
       (unwind-protect (progn ,@body) (close ,stream)))))
