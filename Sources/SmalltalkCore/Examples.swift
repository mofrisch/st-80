public enum SmalltalkExamples {
    static let bootstrap = """
    Object compile: 'initialize
        ^ self'.

    Object subclass: #Counter instanceVariableNames: 'count'.
    Counter compile: 'initialize
        count := 0'.
    Counter compile: 'increment
        count := count + 1'.
    Counter compile: 'add: amount
        count := count + amount'.
    Counter compile: 'value
        ^ count'.
    """

    public static let workspace = """
    "Willkommen. Code markieren und mit ⌘D ausführen.
     Ohne Auswahl wird der gesamte Workspace ausgeführt."

    counter := Counter new.
    5 timesRepeat: [ counter increment ].

    Transcript
        show: 'Hallo, Smalltalk!';
        cr;
        show: 'Der Zähler steht bei ';
        show: counter value;
        cr.

    counter value
    """

    public static let collections = """
    "Nachrichten, Arrays und Blöcke"

    squares := #(1 2 3 4 5) collect: [ :each | each squared ].
    Transcript show: squares; cr.

    sum := 0.
    squares do: [ :each | sum := sum + each ].
    sum
    """

    public static let classes = """
    "Eine neue Klasse und ihre Methoden im laufenden System"

    Object subclass: #Greeter instanceVariableNames: 'name'.

    Greeter compile: 'name: aString
        name := aString'.

    Greeter compile: 'greeting
        ^ ''Hallo, '', name'.

    greeter := Greeter new.
    greeter name: 'Moritz'.
    greeter greeting
    """

    public static let precedence = """
    "Unär vor binär vor Keyword.
     Binäre Nachrichten werden von links nach rechts ausgewertet."

    Transcript show: (3 + 4 * 2); cr.
    Transcript show: (3 + (4 * 2)); cr.

    (5 squared > 20)
        ifTrue: [ 'Smalltalk läuft.' ]
        ifFalse: [ 'Noch einmal nachsehen.' ]
    """
}
