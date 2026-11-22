Object subclass: #Greeter instanceVariableNames: 'name'.
Greeter compile: 'name: aString
    name := aString'.
Greeter compile: 'greeting
    ^ ''Hallo, '', name'.
greeter := Greeter new.
greeter name: 'Moritz'.
greeter greeting
