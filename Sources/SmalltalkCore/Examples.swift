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

    public static let legacyUserInterface = """
    "Die Oberfläche und ihre Aktionen bestehen aus Smalltalk-Objekten."
    | window column nameField greeting buttons greetButton clearButton |

    window := UIWindow new.
    window title: 'Meine Smalltalk-Oberfläche'.

    nameField := UITextField new.
    nameField label: 'Name'; placeholder: 'Dein Name'.
    greeting := UILabel new.
    greeting text: 'Noch keine Begrüßung.'.

    greetButton := UIButton new.
    greetButton title: 'Begrüßen'.
    greetButton action: [ greeting text: 'Hallo, ', nameField text, '!' ].
    clearButton := UIButton new.
    clearButton title: 'Leeren'.
    clearButton action: [ nameField text: ''. greeting text: 'Noch keine Begrüßung.' ].

    buttons := UIRow new.
    buttons spacing: 12; add: greetButton; add: clearButton.
    column := UIColumn new.
    column padding: 20; spacing: 12.
    column add: nameField; add: buttons; add: greeting.

    window content: column.
    window open
    """

    public static let mvcDefinitions = """
    "Model: Fachliche Daten, berechnete Werte und Änderungsnachrichten."
    (Model subclasses select: [ :each | each name = #GreetingModel ]) isEmpty ifTrue: [
        Model subclass: #GreetingModel instanceVariableNames: 'name' ].
    GreetingModel compile: 'initialize super initialize. name := '''''.
    GreetingModel compile: 'name ^ name'.
    GreetingModel compile: 'name: aString name := aString. self changed'.
    GreetingModel compile: 'greeting
        name size = 0 ifTrue: [ ^ ''Noch keine Begrüßung.'' ].
        ^ ''Hallo, '', name, ''!'''.

    "Controller: Benutzereingaben verändern ausschließlich das Model."
    (Controller subclasses select: [ :each | each name = #GreetingController ]) isEmpty ifTrue: [
        Controller subclass: #GreetingController instanceVariableNames: '' ].
    GreetingController compile: 'nameChanged: aString model name: aString'.
    GreetingController compile: 'useExample model name: ''Moritz'''.
    GreetingController compile: 'clear model name: '''''.

    "View: Layout, Bindungen und Weiterleitung von Eingaben."
    (UIWindow subclasses select: [ :each | each name = #GreetingView ]) isEmpty ifTrue: [
        UIWindow subclass: #GreetingView instanceVariableNames: '' ].
    GreetingView compile: 'initialize super initialize. self title: ''Meine MVC-Oberfläche'''.
    GreetingView compile: 'model: aModel controller: aController
        | column input output buttons exampleButton clearButton |
        input := UITextField new.
        input label: ''Name''; placeholder: ''Dein Name''.
        input bind: #text to: aModel aspect: #name.
        input onChangeSend: #nameChanged: to: aController.
        output := UILabel new.
        output bind: #text to: aModel aspect: #greeting.
        exampleButton := UIButton new.
        exampleButton title: ''Beispielname''; onClickSend: #useExample to: aController.
        clearButton := UIButton new.
        clearButton title: ''Leeren''; onClickSend: #clear to: aController.
        buttons := UIRow new.
        buttons spacing: 12; add: exampleButton; add: clearButton.
        column := UIColumn new.
        column padding: 20; spacing: 12.
        column add: input; add: buttons; add: output.
        self content: column'.
    """

    public static let userInterface = mvcDefinitions + """

    "Model, View und Controller verbinden. Das Model ist im Workspace erreichbar."
    greetingModel := GreetingModel new.
    greetingController := GreetingController new.
    greetingController model: greetingModel.
    greetingView := GreetingView new.
    greetingView model: greetingModel controller: greetingController; open.

    "Danach zum Beispiel im Workspace: greetingModel name: 'Ada'"
    greetingView
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
