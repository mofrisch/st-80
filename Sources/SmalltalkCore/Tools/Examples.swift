public enum SmalltalkExamples {
    public static let workspace = """
    "Welcome. Select code and press ⌘D to run it.
     With no selection, the entire workspace runs."

    counter := Counter new.
    5 timesRepeat: [ counter increment ].

    Transcript
        show: 'Hello, Smalltalk!';
        cr;
        show: 'The counter is at ';
        show: counter value;
        cr.

    counter value
    """

    public static let collections = """
    "Messages, arrays, and blocks"

    squares := #(1 2 3 4 5) collect: [ :each | each squared ].
    Transcript show: squares; cr.

    sum := 0.
    squares do: [ :each | sum := sum + each ].
    sum
    """

    public static let classes = """
    "Define a class and its methods in the running system"

    Object subclass: #Greeter instanceVariableNames: 'name'.

    Greeter compile: 'name: aString
        name := aString'.

    Greeter compile: 'greeting
        ^ ''Hello, '', name'.

    greeter := Greeter new.
    greeter name: 'Moritz'.
    greeter greeting
    """

    public static let legacyUserInterface = """
    "The interface and its actions are Smalltalk objects."
    | window column nameField greeting buttons greetButton clearButton |

    window := UIWindow new.
    window title: 'My Smalltalk Interface'.

    nameField := UITextField new.
    nameField label: 'Name'; placeholder: 'Your name'.
    greeting := UILabel new.
    greeting text: 'No greeting yet.'.

    greetButton := UIButton new.
    greetButton title: 'Greet'.
    greetButton action: [ greeting text: 'Hello, ', nameField text, '!' ].
    clearButton := UIButton new.
    clearButton title: 'Clear'.
    clearButton action: [ nameField text: ''. greeting text: 'No greeting yet.' ].

    buttons := UIRow new.
    buttons spacing: 12; add: greetButton; add: clearButton.
    column := UIColumn new.
    column padding: 20; spacing: 12.
    column add: nameField; add: buttons; add: greeting.

    window content: column.
    window open
    """

    public static let mvcDefinitions = """
    "The model holds data, computes values, and notifies observers of changes."
    (Model subclasses select: [ :each | each name = #GreetingModel ]) isEmpty ifTrue: [
        Model subclass: #GreetingModel instanceVariableNames: 'name' ].
    GreetingModel compile: 'initialize super initialize. name := '''''.
    GreetingModel compile: 'name ^ name'.
    GreetingModel compile: 'name: aString name := aString. self changed'.
    GreetingModel compile: 'greeting
        name size = 0 ifTrue: [ ^ ''No greeting yet.'' ].
        ^ ''Hello, '', name, ''!'''.

    "The controller handles input by updating the model."
    (Controller subclasses select: [ :each | each name = #GreetingController ]) isEmpty ifTrue: [
        Controller subclass: #GreetingController instanceVariableNames: '' ].
    GreetingController compile: 'nameChanged: aString model name: aString'.
    GreetingController compile: 'useExample model name: ''Moritz'''.
    GreetingController compile: 'clear model name: '''''.

    "The view defines the layout, binds to the model, and forwards input."
    (UIWindow subclasses select: [ :each | each name = #GreetingView ]) isEmpty ifTrue: [
        UIWindow subclass: #GreetingView instanceVariableNames: '' ].
    GreetingView compile: 'initialize super initialize. self title: ''My MVC Interface'''.
    GreetingView compile: 'model: aModel controller: aController
        | column input output buttons exampleButton clearButton |
        input := UITextField new.
        input label: ''Name''; placeholder: ''Your name''.
        input bind: #text to: aModel aspect: #name.
        input onChangeSend: #nameChanged: to: aController.
        output := UILabel new.
        output bind: #text to: aModel aspect: #greeting.
        exampleButton := UIButton new.
        exampleButton title: ''Use Example Name''; onClickSend: #useExample to: aController.
        clearButton := UIButton new.
        clearButton title: ''Clear''; onClickSend: #clear to: aController.
        buttons := UIRow new.
        buttons spacing: 12; add: exampleButton; add: clearButton.
        column := UIColumn new.
        column padding: 20; spacing: 12.
        column add: input; add: buttons; add: output.
        self content: column'.
    """

    public static let userInterface = mvcDefinitions + """

    "Connect the model, view, and controller. The workspace can access the model."
    greetingModel := GreetingModel new.
    greetingController := GreetingController new.
    greetingController model: greetingModel.
    greetingView := GreetingView new.
    greetingView model: greetingModel controller: greetingController; open.

    "Try evaluating greetingModel name: 'Ada' in the workspace."
    greetingView
    """

    public static let precedence = """
    "Unary messages bind before binary messages, and binary messages before keyword messages.
     Binary messages are evaluated from left to right."

    Transcript show: (3 + 4 * 2); cr.
    Transcript show: (3 + (4 * 2)); cr.

    (5 squared > 20)
        ifTrue: [ 'Smalltalk is running.' ]
        ifFalse: [ 'Check the result again.' ]
    """
}
