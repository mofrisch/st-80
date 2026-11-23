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

greetingModel := GreetingModel new.
greetingController := GreetingController new.
greetingController model: greetingModel.
greetingView := GreetingView new.
greetingView model: greetingModel controller: greetingController; open
