"Observation and controller protocols. Editable in the live browser."

Object subclass: #Model instanceVariableNames: 'dependents'.

Model compile: 'initialize dependents := nil'.

Model compile: 'dependents dependents isNil ifTrue: [ dependents := Array new: 0 ]. ^ dependents'.

Model compile: 'addDependent: anObserver
    | replacement |
    self dependents do: [ :each | each == anObserver ifTrue: [ ^ anObserver ] ].
    replacement := Array new: dependents size + 1.
    1 to: dependents size do: [ :index | replacement at: index put: (dependents at: index) ].
    replacement at: replacement size put: anObserver.
    dependents := replacement.
    ^ anObserver'.

Model compile: 'removeDependent: anObserver dependents := self dependents select: [ :each | (each == anObserver) not ]'.

Model compile: 'changed ^ self changed: nil'.

Model compile: 'changed: anAspect self dependents do: [ :each | each update: anAspect ]'.

Object subclass: #Controller instanceVariableNames: 'model'.

Controller compile: 'initialize model := nil'.

Controller compile: 'model ^ model'.

Controller compile: 'model: aModel model := aModel'.

Object subclass: #UIBinding instanceVariableNames: 'source aspect view property active'.

UIBinding compile: 'initialize active := false'.

UIBinding compile: 'source: aModel aspect: anAspect view: aView property: aProperty source := aModel. aspect := anAspect. view := aView. property := aProperty'.

UIBinding compile: 'source ^ source'.

UIBinding compile: 'aspect ^ aspect'.

UIBinding compile: 'view ^ view'.

UIBinding compile: 'property ^ property'.

UIBinding compile: 'active ^ active'.

UIBinding compile: 'connect active ifTrue: [ ^ self ]. active := true. source addDependent: self. self update: nil'.

UIBinding compile: 'disconnect active ifFalse: [ ^ self ]. active := false. source removeDependent: self'.

UIBinding compile: 'update: anAspect
    active ifFalse: [ ^ self ].
    (anAspect isNil or: [ anAspect = aspect ]) ifTrue: [
        view perform: (property asString, '':'') asSymbol with: (source perform: aspect) ]'.
