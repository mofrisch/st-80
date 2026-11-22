"Einmal ausführen; danach öffnet GreetingWindow new open weitere Exemplare."
UIWindow subclass: #GreetingWindow instanceVariableNames: 'nameField greeting'.

GreetingWindow compile: '
initialize
    | column button |
    super initialize.
    self title: ''Mein Begrüßungsfenster''.
    nameField := UITextField new.
    nameField label: ''Name''; placeholder: ''Dein Name''.
    greeting := UILabel new.
    greeting text: ''Bereit.''.
    button := UIButton new.
    button title: ''Begrüßen''; action: [ self greet ].
    column := UIColumn new.
    column padding: 20; spacing: 12.
    column add: nameField; add: button; add: greeting.
    self content: column'.

GreetingWindow compile: '
greet
    greeting text: ''Hallo, '', nameField text, ''!'''.

GreetingWindow new open
