#!/usr/bin/env hy
(def *usage*  "Kindle 2 Anki Import

Usage:
  parse_clippings.hy summary [--clippings=FILE ] BOOK
  parse_clippings.hy [--clippings=FILE ]

Options:
  --clippings=FILE  Path to clippings file [default: /tmp/My Clippings.txt]
")

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
  (set-comp (get-title highlight) [highlight highlights]))

(defn get-title [highlight]
  (-> (get highlight "source") (parse-source) (.get "title")))

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

(defn format-notes [highlights title]
  (let [[parsed-highlights []]
        sorted-highlights]
    (for [highlight highlights]
      (let [[source (parse-source (get highlight "source"))]]
        (when (= title (get source "title"))
          (.update highlight source)
          (.append parsed-highlights highlight))))
    (def sorted-highlights
      (sorted parsed-highlights
              :key (fn [x] (-> (get x "location") (.split "-") (get 0) (int)))))
    (for [h sorted-highlights]
      (let [[text (get h "text")]]
        (when text
          (print text))))))

(defn write-anki-json [highlights path]
  (def highlights- (filtered-highlights highlights))
  (with
   [[f (open path "w")]]
   (json.dump highlights- f :indent 2))
  (print (.format "Wrote {}" path))
  (show-missing-titles highlights highlights-))

(defn write-summary [highlights book]
  (let [[book-names (book-list highlights)]]
    (if (in book book-names)
      (do
       (print (.format "Generating summary for {}" book))
       (format-notes highlights book))
      (print (.format "Choose one of:\n    {}"
                      (.join "\n    " (sorted book-names)))))))

;; Main
(defmain [&rest args]
  (import docopt)
  (let [[arguments (docopt.docopt  *usage*)]
        [clippings-file (get arguments "--clippings")]
        [summary (get arguments "summary")]
        [*book* (get arguments "BOOK")]
        [highlights (parse-highlights clippings-file)]]
    (if summary
      (write-summary highlights *book*)
      (write-anki-json highlights "anki.json"))))
