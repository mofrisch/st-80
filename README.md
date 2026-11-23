# Smalltalk/80

Ein kleines, natives macOS-System mit einer von Smalltalk-80 inspirierten Sprache.
Die native App und die VM sind in Swift geschrieben. Der Compiler und die Systembibliothek sind in Smalltalk implementiert.

## In Xcode starten

1. **`Smalltalk80.xcodeproj` öffnen.**
2. Scheme **Smalltalk80**, Ziel **My Mac** auswählen.
3. Mit **⌘R** starten.

Das Projekt enthält vier Targets:

| Target | Aufgabe |
| --- | --- |
| Smalltalk80 | Native macOS-Fenster mit SwiftUI-Inhalt und AppKit-Texteditor |
| SmalltalkCore | Swift-VM mit Objektspeicher, Syntaxbaumausführung und Smalltalk-Compiler |
| SmalltalkCoreTests | Sprach-, Image- und Fenstermodelltests |
| Smalltalk80UITests | Workspaces, Methodenänderungen, native Fenster und Image-Neustart |

Die lokale App wird ad hoc signiert; zum Ausprobieren ist kein Development Team nötig.
Voraussetzungen: macOS 14 oder neuer und Xcode mit Swift 6.

## Benutzung

- **Workspace:** Code markieren und **⌘D** drücken. Ohne Auswahl wird der gesamte Inhalt ausgeführt.
- **⌘P:** Ausführen und den Ergebniswert zusätzlich ins Transcript schreiben.
- Im **System Browser** führen vier Listen von der Klassenkategorie über Klasse und Protokoll zur Instanzmethode. Bearbeite den Quelltext darunter und akzeptiere ihn mit **⌘S**. Bereits existierende Objekte verwenden sofort die neue Methode.
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

Beim Laden wird zuerst eine separate Sitzung vollständig aufgebaut und geprüft. Fehlerhafte oder inkompatible Dateien lassen die bisherige Sitzung bestehen. Die VM prüft die Struktur der gespeicherten Methoden und ihre Quellenreferenzen. Beim Laden wird weder neu kompiliert noch Smalltalk-Code ausgeführt. Bereits beendete Rücksprungkontexte von Blöcken bleiben beendet.

**Sitzung zurücksetzen** beginnt einen frischen Stand und löst die automatische Image-Zuordnung. Bereits gespeicherte Dateien bleiben bestehen. **Workspace speichern** mit **⌘S** sichert weiterhin ausschließlich den Quelltext als `.st`.

Das Imageformat ist versioniertes JSON (`format: st80-image`, `version: 4`) mit Objekttabelle, ausführbaren Syntaxbäumen und Quellenverweisen. Ältere Alpha-Images werden abgewiesen. Die Core-API `imageData` liefert eine portable Fassung mit eingebetteten Methodenquellen. Es gelten 32 MiB pro Image und 40.000 erreichbare Referenzobjekte.

### Sources und Changes

Beim Speichern entstehen drei zusammengehörende Dateien:

| Datei | Inhalt |
|---|---|
| `MeineWelt.stimage` | Objektwelt, Klassen, ausführbare Methoden und letzter gesicherter Changes-Stand |
| `Smalltalk80-<Quellen-ID>.sources` | Unveränderliches Quellenarchiv des Basissystems; von mehreren Images teilbar |
| `MeineWelt.changes` | Fortlaufendes Protokoll akzeptierter Klassen- und Methodendefinitionen einschließlich früherer Versionen |

Die Originalquellen liegen in `Sources/SmalltalkCore/Library/*.st`. Xcode und Swift Package Manager bündeln das daraus erzeugte `Smalltalk80.sources` zusammen mit dem ausführbaren `Kernel.seed.json`. Die VM installiert beim Kaltstart die vorkompilierten Methoden und der geladene Smalltalk-Compiler übersetzt `InitialWorld.st`.

Akzeptieren schreibt und synchronisiert zuerst den Changes-Eintrag; erst danach wird die Methode im laufenden Image ersetzt. Das geschieht auch bei `SomeClass compile:` im Workspace. Ein Schreibfehler verhindert die Installation. Vor dem ersten Image-Speichern liegt das Protokoll unter `~/Library/Application Support/Smalltalk80/Changes/`; sein Pfad steht im Änderungsfenster. **Smalltalk → Changes-Datei öffnen …** liest auch ein Protokoll aus einer noch nie gespeicherten Sitzung zur Prüfung ein.

**Smalltalk → Codeänderungen …** öffnet die Historie; **Versionen …** im Browser filtert nach der gewählten Methode und zeigt zusätzlich deren ausgelieferte Basisfassung aus dem Sources-Archiv. **Version übernehmen** kompiliert die gewählte Fassung und protokolliert diese Wiederherstellung als neue Änderung. Einträge nach dem gespeicherten Image-Stand werden gekennzeichnet. Beim Laden werden sie nicht automatisch ausgeführt. Neue Klassen zunächst über ihre Klassendefinition, danach über ihre Methoden wiederherstellen. Das Protokoll speichert Codeänderungen, keine beliebigen Objektmutationen oder noch nicht akzeptierten Editortext.

Image und gleichnamige Changes-Datei zusammen mit dem referenzierten Sources-Archiv kopieren. Sources und Changes nicht mit einem Texteditor verändern. Fehlende, beschädigte oder nicht passende Begleitdateien lassen die aktuelle Sitzung bestehen. Eine unvollständige letzte Changes-Zeile nach einem Absturz wird ignoriert und beim nächsten Eintrag entfernt. Ein vollständiger beschädigter Eintrag wird als Fehler gemeldet. Die Changes-Grenze liegt bei 64 MiB und 100.000 Einträgen; die Oberfläche zeigt die letzten 2.000.

**Image speichern unter** verzweigt die bisherige Historie in eine eigene Changes-Datei. Ein vorhandenes fremdes Protokoll wird nicht überschrieben. Das Image wird erst nach den Begleitdateien atomar ersetzt; ein fehlgeschlagenes Speichern lässt den vorherigen Image-Stand und dessen Quellenverweise nutzbar.

## Smalltalk-Compiler und Startimage

`02-Scanner.st` und `03-Compiler.st` enthalten Scanner und Parser. Derselbe Compiler verarbeitet **Do it**, **Methode akzeptieren** und `Class>>compile:`. Er erzeugt Syntaxbäume in einem temporären Objektspeicher. Die Swift-VM prüft diese Daten, bevor sie Code ausführt oder eine Methode installiert.

Nach einer Änderung der nummerierten Systemquellen werden die beiden mitgelieferten Build-Artefakte im Projektordner so neu erzeugt:

```sh
python3 scripts/generate-sources.py
```

Der Build lädt den bisherigen Smalltalk-Compiler aus dem Startimage. Er erzeugt eine neue Compilergeneration und prüft, dass deren Selbstbau reproduzierbar ist. Mit `--check` überprüft das Skript die vorhandenen Artefakte. Der normale Xcode-Build bündelt sie. Beim Öffnen eines gespeicherten Images wird dessen eigener Compilerstand geladen.

## Native Fensterverwaltung

Workspace, System Browser und Transcript sind getrennte macOS-Fenster. Sie lassen sich über die normalen Titelleisten verschieben, skalieren, minimieren und schließen. Alle Workspaces teilen dieselbe Smalltalk-Sitzung, behalten aber jeweils ihren eigenen Text, ihre Auswahl und ihr letztes Ausführungsergebnis.

Die Fensterverwaltung ist in Smalltalk implementiert. Die globale Variable `Desktop` enthält den Controller `DesktopManager`; dessen `DesktopModel` verwaltet Fensterliste, Reihenfolge, aktives Fenster und Bildschirmdaten. `SystemWindow` ist eine Unterklasse von `Model` und meldet Zustandsänderungen über das gewöhnliche Beobachterprotokoll.

`Library/20-Windows.st` enthält Öffnen, Schließen, Aktivieren, Minimieren, Mindest- und Höchstgrößen, Platzierung, Bildschirmwahl und Wiederherstellung. Diese Methoden lassen sich im Browser ändern. Die Bildschirmwahl bevorzugt die größte Überlappung und bei Gleichstand den nächstgelegenen Bildschirm. Bei einem entfernten Monitor passen sich Fenster an die verbleibenden sichtbaren Bildschirmbereiche an. Die logische Mindestgröße bleibt erhalten, auch wenn ein kleiner Bildschirm vorübergehend kleinere native Grenzen erfordert.

`NativeWindowBackend` erstellt und bedient ausschließlich die einzelnen AppKit-Fenster, meldet verfügbare Bildschirmflächen und native Ereignisse und zeichnet die SwiftUI-Inhalte. Es enthält keine Größen- oder Platzierungsregeln. Native Schließversuche sind Anfragen an `canClose`; Verschieben, Skalieren und Fokuswechsel sind bereits eingetretene Tatsachen. Smalltalk-Anforderungen erhalten eine Revisionsnummer; das Backend meldet die tatsächlich angewendete Geometrie zurück. Sitzungskennungen, fortlaufende Ereignisnummern und Bestätigungen verhindern, dass alte Rückmeldungen neue Anforderungen oder ein neu geladenes Image überschreiben. Auch native Ereignisse werden zeitnah ohne Deaktivieren der Editoren verarbeitet.

```smalltalk
window := Desktop openWorkspace.
window title: 'Mein Workspace'.
window text: '6 * 7'.
window moveToX: 180 y: 240.
window resizeWidth: 700 height: 500
```

Weitere Befehle sind `Desktop openBrowser`, `Desktop openTranscript`, `Desktop openChanges`, `Desktop windows`, `Desktop activeWindow`, `Desktop activate: window` und `Desktop close: window`.

```smalltalk
window minimumWidth: 600 height: 400.
window maximumWidth: 1200 height: 900.

"Eigene Fenster können eine Schließanfrage ablehnen:"
UIWindow subclass: #ProtectedWindow instanceVariableNames: ''.
ProtectedWindow compile: 'canClose ^ false'.
ProtectedWindow new open
```

Ein vollständiges Beispiel mit Schließprüfung liegt in `Examples/WindowPolicy.st`.

Eine eigene `DesktopManager`-Unterklasse kann beispielsweise `screenFor:`, `constrain:`, `requestClose:` oder `createKind:title:` überschreiben. Die Basisklassen und ihr Model bleiben gewöhnliche, im Image gespeicherte Smalltalk-Objekte.

Browser und Transcript werden beim erneuten Öffnen nach vorne geholt. Jeder Aufruf von `openWorkspace` erzeugt ein neues Fenster. Bis zu 128 Fenster sind vorgesehen. Die Koordinaten bezeichnen macOS-Bildschirmpunkte mit Ursprung unten links; beim Laden werden Fenster an die verfügbaren Bildschirme angepasst.

Fenstertexte werden vor einer Auswertung oder dem Speichern eines Images an die Smalltalk-Objekte übertragen. Das Transcript und die Browserauswahl gehören zum gespeicherten Objektgraphen.

## Werkzeuge in Smalltalk

`40-Tools.st` definiert `WorkspaceWindow`, `BrowserWindow` und `TranscriptWindow`. Du kannst diese Klassen im Browser bearbeiten und für neue Fenster ableiten. `DesktopManager>>windowClassFor:` legt fest, welche Klasse beim Öffnen eines Werkzeugs verwendet wird.

Im Workspace wählen die Smalltalk-Aktionen zwischen der nativen Textauswahl und dem ganzen Puffer. Der Browser verwaltet Filter, Auswahl, Entwürfe, Klassenanlage und Methodenannahme in Smalltalk. Er liest die VM-Reflexion über `ToolVM` und `Class` und leitet die angezeigten Protokolle aus den Selektoren und VM-Primitiven ab. `Transcript show:`, `cr` und `clear` pflegen das beobachtbare `TranscriptBuffer`-Model mit den letzten 64 KiB Ausgabetext.

Der SwiftUI-Renderer verwendet denselben Control-Baum für die Werkzeuge und eigene Fenster. Dateidialoge, Tastenkürzel, native Textbearbeitung und die Darstellung der Controls liegen an der macOS-Grenze. Die Klassen der zusätzlichen Controls stehen in `35-NativeControls.st`.

## Oberflächen mit MVC

Unter **Beispiele → Eigene Oberfläche** im Workspace liegt ein vollständiges MVC-Beispiel. Den gleichen Quelltext findest du in `Examples/GreetingWindow.st`; du kannst ihn mit **⌘O** öffnen und ausführen.

| Rolle | Zuständigkeit im Beispiel |
| --- | --- |
| `GreetingModel`, Unterklasse von `Model` | Hält `name`, berechnet `greeting` und meldet Änderungen. Kennt keine UI-Klassen. |
| `GreetingView`, Unterklasse von `UIWindow` | Definiert Layout, Bedienelemente und Bindungen. Leitet Eingaben an den Controller weiter. |
| `GreetingController`, Unterklasse von `Controller` | Verarbeitet Eingaben und Buttons und verändert ausschließlich das Model. Aktualisiert keine Labels oder Felder selbst. |

Nach dem Ausführen reicht im Workspace:

```smalltalk
greetingModel name: 'Ada'
```

Das Eingabefeld und die Begrüßung aktualisieren sich automatisch. Eine zweite View kann dasselbe Model beobachten:

```smalltalk
secondView := GreetingView new.
secondView moveToX: 650 y: 200.
secondView model: greetingModel controller: greetingController; open
```

Änderungen am Model erscheinen in beiden Fenstern. Das funktioniert auch während des Tippens, ohne Return oder einen Button-Klick.

### Änderungsprotokoll und Bindungen

Ein Fachmodell erbt von `Model`. Seine Setter melden Änderungen über `self changed` (alle Aspekte) oder `self changed: #name` (nur diesen Aspekt). Ein Setter im Beispiel lautet:

```smalltalk
name: aString
    name := aString.
    self changed
```

Die View bindet eine Eigenschaft an einen Getter des Models und weist Eingaben einem Controller zu:

```smalltalk
input bind: #text to: greetingModel aspect: #name.
input onChangeSend: #nameChanged: to: greetingController.
output bind: #text to: greetingModel aspect: #greeting.
button onClickSend: #clear to: greetingController
```

`nameChanged:` im Controller sendet `model name: aString`. Das Model benachrichtigt seine Beobachter; die Bindungen lesen die betroffenen Getter und setzen die View-Eigenschaften. Der Controller muss weder die View kennen noch einen Refresh aufrufen. Für berechnete Werte wie `greeting` meldet das Beispiel alle Aspekte mit `changed`.

`Model` bietet außerdem `addDependent:`, `removeDependent:` und `dependents`. Eigene Beobachter implementieren `update:`; dessen Argument ist der geänderte Aspekt oder `nil` für alle Aspekte. Mehrfaches Anmelden desselben Beobachters erzeugt keine doppelten Benachrichtigungen.

Bindbar sind `text` bei Labels und Textfeldern, `title` bei Buttons, `enabled` und `visible` bei allen UI-Elementen sowie `spacing` und `padding` bei Layouts. `unbind: #text` entfernt eine einzelne Bindung, `unbindAll` alle Bindungen einer View. Erneutes Binden derselben Eigenschaft ersetzt die alte Bindung. Am Ende einer Auswertung oder eines nativen Ereignisses werden Bindungen entfernter Bedienelemente und geschlossener Fenster abgemeldet. Beim Wiederöffnen werden sie mit den aktuellen Model-Werten verbunden.

### Bedienelemente und Darstellung

| Klasse | Nachrichten |
| --- | --- |
| `UIWindow` | `title:`, `content:`, `open`, `moveToX:y:`, `resizeWidth:height:` |
| `UILabel` | `text:`, `text` |
| `UIButton` | `title:`, `action:`, `onClickSend:to:`, `selectionFrom:action:` für Aktionen mit der Auswahl eines Code-Editors |
| `UITextField` | `label:`, `placeholder:`, `text:`, `text`, `onChangeSend:to:` |
| `UICodeEditor` | Wie ein Textfeld, zusätzlich `readOnly:` und native Textauswahl |
| `UIList` | `items:` mit eindeutigen Strings, `selection:`, `onSelectSend:to:` |
| `UISplit`, `UIScroll`, `UIMenu` | Container für geteilte Ansicht, Scrollbereich bzw. Menü. `UISplit` stapelt die Bereiche mit `role: #vertical`. `UIMenu` hat zusätzlich `title:`. |
| `UIDivider` | Trennlinie |
| `UIColumn`, `UIRow` | `add:`, `remove:`, `removeAll`, `children:`, `spacing:`, `padding:` |
| `UISpacer` | Flexibler Abstand innerhalb einer Zeile oder Spalte |
| Alle UI-Elemente | `enabled:`, `visible:`, `identifier:`, `role:`, `widthFrom:to:`, `heightFrom:to:`, `bind:to:aspect:`, `unbind:`, `unbindAll` |

Zeilen und Spalten lassen sich verschachteln. `add:` gibt das hinzugefügte Element zurück. `spacing:` akzeptiert 0 bis 128 Punkte, `padding:` 0 bis 256. Eine Oberfläche ist ein Baum mit maximal 512 Elementen und 16 Verschachtelungsebenen; ein Element darf innerhalb eines Fensters nur einmal vorkommen. Ein deaktiviertes Layout deaktiviert auch seine enthaltenen Elemente.

Die Smalltalk-Objekte bleiben auf dem Interpreter-Thread. Die native SwiftUI-View zeichnet unveränderliche Zustände und führt keine Model-Getter aus. `AppController` vermittelt native Ereignisse und übernimmt die fertigen Zustände zur Darstellung. Das Änderungsprotokoll selbst läuft in Smalltalk, ohne Polling.

Textfelder mit einem Eingabe-Controller übertragen Änderungen nach einer kurzen Tipp-Pause von 80 ms. Dabei wird das Feld nicht deaktiviert. Vor Buttons, Workspace-Auswertungen und dem Speichern eines Images werden ausstehende Eingaben vollständig und in Eingabereihenfolge übertragen. Änderungen aus Model-Benachrichtigungen lösen keine erneuten Eingabeereignisse aus. Auch bei einer fehlerhaften Model- oder Controller-Methode bleiben Workspace und Methodenbrowser zum Reparieren benutzbar; ausstehende Eingaben werden danach erneut übertragen.

### Images

Images erhalten Fachmodelle, Controller, Views, Bindungen und Beobachterbeziehungen. Nach dem Laden funktionieren Model-Änderungen und Eingaben weiter. Beim Laden werden weder `initialize` noch gebundene Getter ausgeführt; dafür enthalten Images auch den zuletzt gültigen Darstellungszustand.

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
