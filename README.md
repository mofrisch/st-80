# Smalltalk/80

Ein kleines, natives macOS-System mit einer von Smalltalk-80 inspirierten Sprache.
Die App und der Interpreter sind in Swift geschrieben. Keine externen Bibliotheken.

## In Xcode starten

1. **`Smalltalk80.xcodeproj` öffnen.**
2. Scheme **Smalltalk80**, Ziel **My Mac** auswählen.
3. Mit **⌘R** starten.

Das Projekt enthält vier Targets:

| Target | Aufgabe |
| --- | --- |
| Smalltalk80 | Native macOS-Fenster mit SwiftUI-Inhalt und AppKit-Texteditor |
| SmalltalkCore | Parser, Objektspeicher, Interpreter und Compiler für Methoden |
| SmalltalkCoreTests | Sprach-, Image- und Fenstermodelltests |
| Smalltalk80UITests | Workspaces, Methodenänderungen, native Fenster und Image-Neustart |

Die lokale App wird ad hoc signiert; zum Ausprobieren ist kein Development Team nötig.
Voraussetzungen: macOS 14 oder neuer und Xcode mit Swift 6.

## Benutzung

- **Workspace:** Code markieren und **⌘D** drücken. Ohne Auswahl wird der gesamte Inhalt ausgeführt.
- **⌘P:** Ausführen und den Ergebniswert zusätzlich ins Transcript schreiben.
- **Browser:** Links eine Klasse und eine Instanzmethode auswählen. Methode bearbeiten und mit **⌘S** akzeptieren. Bereits existierende Objekte verwenden sofort die neue Methode.
- Über **+** lassen sich Klassen und Methoden anlegen. Im Klassenbrowser stehen die eigenen Methoden; geerbte Methoden findet man bei der Oberklasse.
- Rechts erscheinen die Workspace-Variablen, ihre Klassen und ihre Werte.
- **⌘N:** Einen weiteren, unabhängigen Workspace öffnen.
- **⌘1 / ⌘2 / ⌘3:** Workspace, Browser oder Transcript nach vorne holen.
- **⌘O:** UTF-8-Quelltext in einem neuen Workspace öffnen. **⌘S** speichert im Workspace den Quelltext als `.st`.
- Das Menü **Beispiele** enthält Zähler, Arrays und Blöcke, Klassendefinitionen und Nachrichtenreihenfolge.

## Images speichern und laden

- **⌘⇧S – Image speichern:** Sichert die laufende Sitzung als `.stimage`. Beim ersten Speichern erscheint der native Dateidialog; danach wird dieselbe Datei atomar ersetzt.
- **⌘⌥⇧S – Image speichern unter:** Legt eine weitere Image-Datei an.
- **⌘⇧O – Image öffnen:** Ersetzt die Sitzung durch einen gespeicherten Stand.
- Beim App-Start wird das zuletzt erfolgreich gespeicherte oder geöffnete Image automatisch geladen. Weitere Änderungen müssen ausdrücklich gespeichert werden; beim Beenden wird die Datei nicht automatisch überschrieben.
- Rechts stehen der Image-Dateiname und der Speicherstatus. Im Browser Methoden vor dem Speichern mit **⌘S** akzeptieren; noch nicht akzeptierter Methodenquelltext gehört nicht zum Image.

Ein Image erhält Klassen und ihre Hierarchie, akzeptierte Methoden (auch Änderungen an Basisklassen), Workspace-Variablen, Instanzvariablen, Arrays und gespeicherte Blöcke samt lexikalischen Kontexten. Gemeinsam genutzte Referenzen und zyklische Objektgraphen bleiben erhalten. Alle Workspace-Texte, offene Fenster samt Größe, Position, Reihenfolge und Minimierungszustand sowie das Transcript werden ebenfalls gesichert. Nicht mehr erreichbare Objekte werden weggelassen.

Beim Laden wird zuerst eine separate Sitzung vollständig aufgebaut und geprüft. Fehlerhafte oder inkompatible Dateien lassen die bisherige Sitzung bestehen. Gespeicherter Methodenquelltext wird geparst, aber beim Laden wird kein Smalltalk-Code ausgeführt; insbesondere werden keine `initialize`-Methoden aufgerufen. Bereits beendete Rücksprungkontexte von Blöcken bleiben beendet.

**Sitzung zurücksetzen** beginnt einen frischen Stand und löst die automatische Image-Zuordnung. Bereits gespeicherte Dateien bleiben bestehen. **Workspace speichern** mit **⌘S** sichert weiterhin ausschließlich den Quelltext als `.st`.

Das eigene Format ist versioniertes JSON (`format: st80-image`, `version: 1`) mit einer Objekttabelle und Referenz-IDs. Es ist kein historisches Smalltalk-80-Image. Die aktuelle Grenze liegt bei 32 MiB pro Image und 40.000 erreichbaren Referenzobjekten; außerdem gelten die Laufzeitgrenzen des Prototyps.

## Native Fensterverwaltung

Workspace, System Browser und Transcript sind getrennte macOS-Fenster. Sie lassen sich über die normalen Titelleisten verschieben, skalieren, minimieren und schließen. Alle Workspaces teilen dieselbe Smalltalk-Sitzung, behalten aber jeweils ihren eigenen Text, ihre Auswahl und ihr letztes Ausführungsergebnis.

Die Fenster sind gewöhnliche `SystemWindow`-Objekte. Die globale Variable `Desktop` enthält einen `DesktopManager`; seine Smalltalk-Methoden verwalten die Fensterliste und das aktive Fenster. Auch die native Bedienung sendet diese Nachrichten. Die Methoden lassen sich im Browser bearbeiten.

```smalltalk
window := Desktop openWorkspace.
window title: 'Mein Workspace'.
window text: '6 * 7'.
window moveToX: 180 y: 240.
window resizeWidth: 700 height: 500
```

Weitere Befehle sind `Desktop openBrowser`, `Desktop openTranscript`, `Desktop windows`, `Desktop activeWindow`, `Desktop activate: window` und `Desktop close: window`.

Browser und Transcript werden beim erneuten Öffnen nach vorne geholt. Jeder Aufruf von `openWorkspace` erzeugt ein neues Fenster. Bis zu 128 Fenster sind vorgesehen. Die Koordinaten bezeichnen macOS-Bildschirmpunkte mit Ursprung unten links; beim Laden werden Fenster an die verfügbaren Bildschirme angepasst.

Fenstertexte werden vor einer Auswertung oder dem Speichern eines Images an die Smalltalk-Objekte übertragen. Ältere Images ohne Fensterverwaltung erhalten beim Laden die drei Standardfenster; ihr gespeicherter Workspace wird übernommen. Bei dieser Ergänzung werden keine benutzerdefinierten `initialize`-Methoden aufgerufen.

## Erster Versuch

```smalltalk
counter := Counter new.
5 timesRepeat: [ counter increment ].
counter value
```

Ergebnis: `5`. Nun im Browser `Counter » value` ändern und akzeptieren:

```smalltalk
value
    ^ count + 100
```

Anschließend im Workspace nur `counter value` markieren und ausführen. Das bestehende Objekt antwortet jetzt mit `105`.

Eigene Klassen können auch über Nachrichten entstehen:

```smalltalk
Object subclass: #Greeter instanceVariableNames: 'name'.
Greeter compile: 'name: aString
    name := aString'.
Greeter compile: 'greeting
    ^ ''Hallo, '', name'.

greeter := Greeter new.
greeter name: 'Moritz'.
greeter greeting
```

## Sprachumfang

Implementiert sind Ganzzahlen mit geprüfter 64-Bit-Arithmetik, Strings, Symbole, Arrays, `nil`, Boolesche Werte, Zuweisungen, lokale Variablen, unäre/binäre/Keyword-Nachrichten, Kaskaden, lexikalische Blöcke, nichtlokale Rückgaben mit `^`, Klassen, Instanzvariablen, einfache Vererbung und `super`.

Nachrichten folgen der Smalltalk-Reihenfolge: unär vor binär vor Keyword; binäre Nachrichten werden untereinander von links nach rechts ausgewertet. `3 + 4 * 2` ergibt daher `14`. Die Orientierung ist Goldberg/Robsons [Smalltalk-80: The Language and Its Implementation](https://rmod-files.lille.inria.fr/FreeBooks/BlueBookHughes/BlueBookImplementationTOC.html).

Für den Prototyp gelten bewusste Vereinfachungen:

- Der Interpreter führt einen Syntaxbaum aus; es gibt noch keine Blue-Book-Bytecode-VM und keine Kompatibilität zu historischen Images.
- Klassen teilen sich die vereinfachte Klasse `Class`; eine vollständige Metaklassenhierarchie und separate Klassenmethoden fehlen.
- `subclass:instanceVariableNames:` ist eine Kurzform. Die längere Smalltalk-80-Nachricht wird mit leeren Klassenvariablen und Pool-Dictionaries ebenfalls akzeptiert.
- `new` sendet `initialize`. Ohne explizites `^` gibt eine Methode `self`, ein Block seinen letzten Ausdruck zurück.
- Nicht deklarierte Workspace-Zuweisungen erzeugen bleibende Workspace-Variablen. `| temp |` bleibt lokal zur jeweiligen Ausführung.
- Strings sind Unicode-Werte; `at:` liefert einen String mit einem Zeichen. `==` vergleicht bei Strings deren Wert. Character, Fraction, Float und LargeInteger fehlen.
- Der Objektspeicher verwendet zunächst eine Arena und wird beim Zurücksetzen freigegeben. Ein Garbage Collector, Prozesse, Debugger und BitBlt fehlen noch.
- Derzeit sind bis zu 100.000 Ausführungsschritte, 128 Aufrufebenen, 32 syntaktische Verschachtelungen, 20.000 Arena-Einträge und 4.096 Elemente pro Array vorgesehen. Fehler machen bereits ausgeführte Änderungen nicht rückgängig.

## App-Icon

Das App-Icon verbindet überlappende Programmfenster mit einer Nachrichtenblase. Die transparente Originalgrafik liegt in `Design/AppIcon.png`, die verwendeten ImageGen-Prompts in `Design/AppIcon-prompt.txt`.

Das Xcode-Target verwendet `Assets.xcassets/AppIcon.appiconset` mit allen zehn macOS-Größen von 16 bis 1024 Pixeln. Die Ableitungen lassen sich mit den macOS-Bordmitteln erneut erzeugen:

```sh
python3 scripts/prepare-app-icon.py Design/AppIcon.png
```

Der Projektgenerator erhält die Asset-Katalog-Zuordnung und die App-Icon-Einstellung für Debug und Release.

## Prüfen und bauen

```sh
xcodebuild -project Smalltalk80.xcodeproj -scheme Smalltalk80 \
  -destination 'platform=macOS' -derivedDataPath .build/xcode build

xcodebuild -project Smalltalk80.xcodeproj -scheme Smalltalk80 \
  -destination 'platform=macOS' -derivedDataPath .build/xcode \
  -only-testing:SmalltalkCoreTests test

xcodebuild -project Smalltalk80.xcodeproj -scheme Smalltalk80 \
  -destination 'platform=macOS' -derivedDataPath .build/xcode \
  -only-testing:Smalltalk80UITests test
```

Alternativ lassen sich die Kerntests über `swift test` ausführen. Das Xcode-Projekt liegt direkt im Projektverzeichnis und benötigt keinen Generator zum Öffnen oder Bauen. Bei neuen Quelldateien lässt es sich mit `python3 scripts/generate-project.py` reproduzieren; manuelle Änderungen am Projekt würden dabei ersetzt.

## Nächste Ausbaustufe

Als Nächstes bietet sich ein Objektinspektor mit einzelnen Feldern an. Danach können Bytecodes und Garbage Collection den zunächst absichtlich kleinen Interpreter ablösen.
