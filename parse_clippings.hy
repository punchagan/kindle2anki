#!/usr/bin/env hy

(import json)
(import re)

(import [book-deck-map [book-deck-map]])

;; Parsing related code

(defn parse-single-highlight [f]
  "Parse and return a single highlight from the file"
  (let [[highlight {}]]
    (for [[index line] (enumerate f)]
      (cond
       [(= index 0)
        (def heading (parse-heading line))]
       [(= index 1)
        (def location (parse-location line))]
       [(= index 2)
        ;; empty line
        (continue)]
       [(= index 3)
        (def text (parse-text line))]
       [(is-highlight-end? line)
        (do
         (assoc highlight
                "source" (.format "{} | {}" heading location)
                "text" text)
         (break))]))
    highlight))


(defn parse-heading [line]
  (-> (.strip line) (.strip "\ufeff")))

(defn parse-location [line]
  (-> (.strip line) (.lstrip "- ")))

(defn parse-text [line]
  (.strip line))

(defn is-highlight-end? [line]
  (= (set (.strip line)) (set "=")))

(defn parse-highlights [highlights-file]
  (let [[highlights []]]
    (with [(f (open highlights-file))]
          (while true
            (def highlight (parse-single-highlight f))
            (if (not highlight)
              (break)
              (.append highlights highlight))))
    highlights))

;; Write JSON for Anki addon

(def *title-author-re* (.compile re "^(.*?)\s*\(([^()]*?)\)\s*$"))
(def *page-re* (.compile re "^.*Page\s*(.*?)\s*$" re.IGNORECASE))
(def *location-re* (.compile re "^.*Location\s*(.*?)\s*$"))
(def *time-re* (.compile re "^.*Added on\s*(.*?)\s*$"))

(defn parse-title-author [text]
  (if (in "(" text)
    (-> (.match *title-author-re* text) (.groups))
    [(.strip text) ""]))

(defn no-page? [text]
  (none? (.match *page-re* text)))

(defn add-page [line]
  (.replace line "|" "| Page -- |" 1))

(defn parse-source [line]
  (when (no-page? line)
    (def line (add-page line)))
  (let [[[heading page location time]
         (list-comp (.strip x) [x (.split line "|")])]
         [info {}]
        [[title author] (parse-title-author heading)]
        [[page] (-> (.match *page-re* page) (.groups))]
        [[location] (-> (.match *location-re* location) (.groups))]
        [[time] (-> (.match *time-re* time) (.groups))]]
    (assoc info
           "title" title
           "author" author
           "location" location
           "page" page
           "time" time)
    info))

(defn book-list [highlights]
  (set-comp
   (-> (get highlight "source") (parse-source) (.get "title"))
   [highlight highlights]))

(defn ankify-highlight [highlight]
  (let [[source (get highlight "source")]
        [text (get highlight "text")]
        [info (parse-source source)]
        [title (get info "title")]
        [deck (.get book-deck-map title)]]
    (if (nil? deck)
      None
      (do
       (assoc highlight "deck" deck)
       (assoc highlight "Original Text" text)
       (assoc highlight "Text" text)
       (assoc highlight "Source" source)
       (.update highlight info)
       highlight))))

(defn filtered-highlights [highlights]
  (def -highlights (list-comp (ankify-highlight x) [x highlights]))
  (list (filter None -highlights)))

(defn show-missing-titles [highlights highlights-]
  (def missing-titles
    (- (book-list highlights) (book-list highlights-)))
  (print "Ignored titles:")
  (for [title missing-titles]
    (print (.format "  {}" title))))

(defn write-anki-json [highlights path]
  (def highlights- (filtered-highlights highlights))
  (with
   [[f (open path "w")]]
   (json.dump highlights- f :indent 2))
  (print (.format "Wrote {}" path))
  (show-missing-titles highlights highlights-))


;; Main
(defmain [&rest args]
  (def clippings-file
    (if (-> (len args) (> 1))
      (nth args 1)
      "/tmp/My Clippings.txt"))
  (def *h* (parse-highlights clippings-file))
  (write-anki-json *h* "anki.json"))
