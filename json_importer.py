#!/usr/bin/env python
"""A script to import cards from JSON.

The addon adds a menu item to import items from a JSON file.  The function
makes use (a modified version) of the Json_Importer from 1219378844 addon.

The json used by this addon can have multiple cards to be added to multiple
different decks using the 'deck' key mapped to the name of the deck.  It
currently supports just one model, but it should be possible to extend the
addon to use different models too.

"""

import json
import os
from os.path import expanduser

from anki.lang import _
from anki.importing.noteimp import NoteImporter, ForeignNote
from aqt import editor, mw
from aqt.qt import QAction, SIGNAL
from aqt.utils import getFile, showText


MODEL_NAME = 'Basic-Import'
AUDIO_EXTENSIONS = editor.audio
IMAGE_EXTENSIONS = editor.pics
MEDIA_EXTENSIONS = editor.audio + editor.pics


class JsonImporter(NoteImporter):
    def __init__(self, col, file_, model_name=None, deck_name=None):
        NoteImporter.__init__(self, col, file_)
        self._setup_model(model_name, deck_name, file_)

    def run(self, entries):
        "Import."
        assert self.mapping
        c = self.entriesToNotes(entries)
        self.importNotes(c)

    def entriesToNotes(self, entries):
        notes = []
        for entry in entries:
            row = self._read_row(entry)
            if len(row) == 0:  # empty entry
                continue

            note = ForeignNote()
            note.fields = row
            notes.append(note)

        return notes

    def fields(self):
        return len(self.model['flds'])

    def _read_row(self, entry):
        row = []
        empty = True
        for f in self.mappingFields:
            value = entry.get(f, '')
            if value:
                empty = False

            if '.' in value:
                ext = value[value.rfind('.') + 1:].lower()
                if ext in MEDIA_EXTENSIONS:
                    path = os.path.join(self.fileDir, value)
                    if os.path.exists(path):
                        filename = self.col.media.addFile(os.path.join(self.fileDir, value))
                        if ext in AUDIO_EXTENSIONS:
                            value = u'[sound:%s]' % filename
                        else:
                            value = u'<img src="%s">' % filename

            row.append(value)

        return row if not empty else []

    def _setup_model(self, model_name, deck_name, file_):
        self.model = self.col.models.byName(model_name)
        self.mappingFields = [f['name'] for f in self.model['flds']]
        self.mapping = None
        self.fileDir = os.path.dirname(file_)

        deck_id = self.col.decks.id(deck_name)
        self.col.decks.select(deck_id)
        deck = self.col.decks.get(deck_id)
        deck['mid'] = self.model['id']
        self.col.decks.save(deck)

        self.model['did'] = deck_id


def import_from_json():
    path = getFile(mw, "Org file to import", cb=None, dir=expanduser("~"))
    if not path:
        return
    with open(path, 'r') as f:
        content = f.read().decode('utf-8')

    entries = json.loads(content)
    import itertools
    get_deck = lambda e: e['deck']
    entries = sorted(entries, key=get_deck)

    mw.checkpoint(_("Import"))
    logs = []
    for deck_name, entries in itertools.groupby(entries, get_deck):
        # FIXME: If required we could group by model name also!
        importer = JsonImporter(mw.col, path, MODEL_NAME, deck_name)
        importer.initMapping()
        importer.run(list(entries))
        if importer.log:
            logs.append('\n'.join(importer.log))

    txt = _("Importing complete.") + "\n"
    txt += '\n'.join(logs)
    showText(txt)
    mw.reset()


action = QAction("Import from &JSON", mw)
mw.connect(action, SIGNAL("triggered()"), import_from_json)
mw.form.menuTools.addAction(action)
