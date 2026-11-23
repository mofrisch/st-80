"The small source-level core. Primitive operations stay in the host VM."
Object compile: 'initialize ^ self'.
Integer compile: 'min: other self < other ifTrue: [ ^ self ]. ^ other'.
Integer compile: 'max: other self > other ifTrue: [ ^ self ]. ^ other'.
Integer compile: 'clampFrom: lower to: upper ^ (self max: lower) min: upper'.

Object subclass: #Counter instanceVariableNames: 'count'.
Counter compile: 'initialize count := 0'.
Counter compile: 'increment count := count + 1'.
Counter compile: 'add: amount count := count + amount'.
Counter compile: 'value ^ count'.
