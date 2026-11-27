"ANSI date and time protocols (J20 5.8). The default local time is UTC.
Dates count exact seconds since Gregorian 0001-01-01T00:00:00+00:00."

Object subclass: #Duration instanceVariableNames: 'totalSeconds'.
Object subclass: #DateAndTime instanceVariableNames: 'utcSeconds utcOffset'.

Duration compileClass: 'seconds: amount
    ^ self new _seconds: (self _exactSeconds: amount)'.

Duration compileClass: 'days: days hours: hours minutes: minutes seconds: seconds
    ((days isKindOf: Integer) and: [
        (hours isKindOf: Integer) and: [ minutes isKindOf: Integer ] ])
        ifFalse: [ self error: ''Days, hours, and minutes must be integers.'' ].
    ^ self seconds: (days * 86400) + (hours * 3600) + (minutes * 60) + (self _exactSeconds: seconds)'.

Duration compileClass: 'zero
    ^ self seconds: 0'.

Duration compileClass: '_exactSeconds: amount
    (amount isKindOf: Number) ifFalse: [ self error: ''Expected a number of seconds.'' ].
    ^ amount asFraction'.

Duration compile: '_seconds: amount
    totalSeconds := amount.
    ^ self'.

Duration compile: '_secondsOf: other
    (other isKindOf: Duration) ifFalse: [ self error: ''Expected a Duration.'' ].
    ^ other asSeconds'.

Duration compile: 'asSeconds
    ^ totalSeconds'.

Duration compile: 'days
    ^ totalSeconds quo: 86400'.

Duration compile: 'hours
    ^ (totalSeconds quo: 3600) rem: 24'.

Duration compile: 'minutes
    ^ (totalSeconds quo: 60) rem: 60'.

Duration compile: 'seconds
    ^ totalSeconds rem: 60'.

Duration compile: '+ other
    ^ self class seconds: totalSeconds + (self _secondsOf: other)'.

Duration compile: '- other
    ^ self class seconds: totalSeconds - (self _secondsOf: other)'.

Duration compile: '* factor
    ^ self class seconds: totalSeconds * (self class _exactSeconds: factor)'.

Duration compile: '/ operand
    | isDuration divisor quotient |
    isDuration := operand isKindOf: Duration.
    divisor := isDuration
        ifTrue: [ operand asSeconds ]
        ifFalse: [ self class _exactSeconds: operand ].
    divisor = 0 ifTrue: [ ^ ZeroDivide dividend: totalSeconds ].
    quotient := totalSeconds / divisor.
    ^ isDuration ifTrue: [ quotient ] ifFalse: [ self class seconds: quotient ]'.

Duration compile: 'abs
    ^ self negative ifTrue: [ self negated ] ifFalse: [ self ]'.

Duration compile: 'negated
    ^ self class seconds: totalSeconds negated'.

Duration compile: 'negative
    ^ totalSeconds < 0'.

Duration compile: 'positive
    ^ totalSeconds >= 0'.

Duration compile: '= other
    ^ (other isKindOf: Duration) and: [ totalSeconds = other asSeconds ]'.

Duration compile: '~= other
    ^ (self = other) not'.

Duration compile: 'hash
    ^ totalSeconds hash'.

Duration compile: '< other
    ^ totalSeconds < (self _secondsOf: other)'.

Duration compile: '<= other
    ^ totalSeconds <= (self _secondsOf: other)'.

Duration compile: '> other
    ^ totalSeconds > (self _secondsOf: other)'.

Duration compile: '>= other
    ^ totalSeconds >= (self _secondsOf: other)'.

Duration compile: 'between: lower and: upper
    ^ (self >= lower) and: [ self <= upper ]'.

Duration compile: 'min: other
    ^ self < other ifTrue: [ self ] ifFalse: [ other ]'.

Duration compile: 'max: other
    ^ self > other ifTrue: [ self ] ifFalse: [ other ]'.

Duration compile: 'printString
    | sign value |
    sign := self negative ifTrue: [ ''-'' ] ifFalse: [ '''' ].
    value := self abs.
    ^ sign , value days printString , '':'' ,
        (self class _pad: value hours to: 2) , '':'' ,
        (self class _pad: value minutes to: 2) , '':'' ,
        (self class _printSeconds: value seconds)'.

Duration compileClass: '_pad: number to: width
    | digits missing |
    digits := number printString.
    missing := width - digits size.
    missing <= 0 ifTrue: [ ^ digits ].
    ^ ((String new: missing) atAllPut: $0; yourself) , digits'.

Duration compileClass: '_printSeconds: amount
    | whole fraction result |
    whole := amount truncated.
    result := self _pad: whole to: 2.
    fraction := amount - whole.
    fraction = 0 ifTrue: [ ^ result ].
    ^ result , ''.'' , (self _decimalDigitsOf: fraction)'.

Duration compileClass: '_decimalDigitsOf: fraction
    "The input is a positive proper fraction. Print terminating decimals exactly."
    | denominator twos fives places digits |
    denominator := fraction denominator.
    twos := 0.
    fives := 0.
    [ denominator even ] whileTrue: [
        denominator := denominator // 2.
        twos := twos + 1 ].
    [ (denominator \\ 5) = 0 ] whileTrue: [
        denominator := denominator // 5.
        fives := fives + 1 ].
    places := denominator = 1
        ifTrue: [ twos max: fives ]
        ifFalse: [ 30 + ((fraction denominator printString size - fraction numerator printString size) max: 0) ].
    digits := (fraction * (10 raisedToInteger: places)) truncated.
    ^ self _pad: digits to: places'.

DateAndTime compileClass: 'now
    ^ self _atUTCSeconds: self _unixTime + ((self _daysBeforeYear: 1970) * 86400)
        offset: Duration zero'.

DateAndTime compileClass: 'clockPrecision
    ^ Duration seconds: self _clockResolution'.

DateAndTime compileClass: 'year: year month: month day: day hour: hour minute: minute second: second
    ^ self year: year month: month day: day hour: hour minute: minute second: second
        offset: Duration zero'.

DateAndTime compileClass: 'year: year month: month day: day hour: hour minute: minute second: second offset: offset
    | starts ordinal |
    self _checkYear: year.
    ((month isKindOf: Integer) and: [ month between: 1 and: 12 ])
        ifFalse: [ self error: ''Month must be between 1 and 12.'' ].
    starts := self _monthStartsFor: year.
    ((day isKindOf: Integer) and: [
        day between: 1 and: (starts at: month + 1) - (starts at: month) ])
        ifFalse: [ self error: ''Day is outside the month.'' ].
    ordinal := (starts at: month) + day.
    ^ self _year: year ordinal: ordinal hour: hour minute: minute second: second offset: offset'.

DateAndTime compileClass: 'year: year day: ordinal hour: hour minute: minute second: second
    ^ self year: year day: ordinal hour: hour minute: minute second: second offset: Duration zero'.

DateAndTime compileClass: 'year: year day: ordinal hour: hour minute: minute second: second offset: offset
    | starts |
    self _checkYear: year.
    starts := self _monthStartsFor: year.
    ((ordinal isKindOf: Integer) and: [ ordinal between: 1 and: starts last ])
        ifFalse: [ self error: ''Day is outside the year.'' ].
    ^ self _year: year ordinal: ordinal hour: hour minute: minute second: second offset: offset'.

DateAndTime compileClass: '_year: year ordinal: ordinal hour: hour minute: minute second: second offset: offset
    | seconds dayIndex |
    ((hour isKindOf: Integer) and: [ hour between: 0 and: 23 ])
        ifFalse: [ self error: ''Hour must be between 0 and 23.'' ].
    ((minute isKindOf: Integer) and: [ minute between: 0 and: 59 ])
        ifFalse: [ self error: ''Minute must be between 0 and 59.'' ].
    seconds := Duration _exactSeconds: second.
    (seconds >= 0 and: [ seconds < 60 ])
        ifFalse: [ self error: ''Second must be at least 0 and less than 60.'' ].
    self _checkOffset: offset.
    dayIndex := (self _daysBeforeYear: year) + ordinal - 1.
    ^ self _atUTCSeconds: (dayIndex * 86400) + (hour * 3600) + (minute * 60) + seconds - offset asSeconds
        offset: offset'.

DateAndTime compileClass: '_atUTCSeconds: instant offset: offset
    ^ self new _utcSeconds: instant offset: offset'.

DateAndTime compileClass: '_checkYear: year
    (year isKindOf: Integer) ifFalse: [ self error: ''Year must be an integer.'' ]'.

DateAndTime compileClass: '_checkOffset: offset
    ((offset isKindOf: Duration) and: [ offset asSeconds between: -86400 and: 86400 ])
        ifFalse: [ self error: ''Expected a UTC offset from -24 to +24 hours.'' ]'.

DateAndTime compileClass: '_isLeapYear: year
    ^ (year \\ 4) = 0 and: [ (year \\ 100) ~= 0 or: [ (year \\ 400) = 0 ] ]'.

DateAndTime compileClass: '_daysBeforeYear: year
    | previous |
    previous := year - 1.
    ^ (previous * 365) + (previous // 4) - (previous // 100) + (previous // 400)'.

DateAndTime compileClass: '_monthStartsFor: year
    ^ (self _isLeapYear: year)
        ifTrue: [ #(0 31 60 91 121 152 182 213 244 274 305 335 366) ]
        ifFalse: [ #(0 31 59 90 120 151 181 212 243 273 304 334 365) ]'.

DateAndTime compileClass: '_datePartsForDay: dayIndex
    "A Gregorian cycle begins on January 1 of year 1 modulo 400.
    Floor division also splits days before the epoch into a cycle and a nonnegative day."
    | cycle within lower upper middle year ordinal starts month |
    cycle := dayIndex // 146097.
    within := dayIndex \\ 146097.
    lower := 1.
    upper := 401.
    [ upper - lower > 1 ] whileTrue: [
        middle := (lower + upper) // 2.
        (self _daysBeforeYear: middle) <= within
            ifTrue: [ lower := middle ] ifFalse: [ upper := middle ] ].
    year := (cycle * 400) + lower.
    ordinal := within - (self _daysBeforeYear: lower) + 1.
    starts := self _monthStartsFor: lower.
    month := 1.
    [ ordinal > (starts at: month + 1) ] whileTrue: [ month := month + 1 ].
    ^ Array with: year with: month with: ordinal - (starts at: month) with: ordinal'.

DateAndTime compile: '_utcSeconds: instant offset: offset
    utcSeconds := instant.
    utcOffset := offset.
    ^ self'.

DateAndTime compile: '_utcSeconds
    ^ utcSeconds'.

DateAndTime compile: '_secondsOf: other
    (other isKindOf: DateAndTime) ifFalse: [ self error: ''Expected a DateAndTime.'' ].
    ^ other _utcSeconds'.

DateAndTime compile: '_localDay
    ^ (utcSeconds + utcOffset asSeconds) // 86400'.

DateAndTime compile: '_dateParts
    ^ self class _datePartsForDay: self _localDay'.

DateAndTime compile: '_timeOfDay
    ^ Duration seconds: ((utcSeconds + utcOffset asSeconds) \\ 86400)'.

DateAndTime compile: 'asUTC
    ^ self offset: Duration zero'.

DateAndTime compile: 'asLocal
    ^ self asUTC'.

DateAndTime compile: 'offset
    ^ utcOffset'.

DateAndTime compile: 'offset: offset
    self class _checkOffset: offset.
    ^ self class _atUTCSeconds: utcSeconds offset: offset'.

DateAndTime compile: '+ duration
    (duration isKindOf: Duration) ifFalse: [ self error: ''Expected a Duration.'' ].
    ^ self class _atUTCSeconds: utcSeconds + duration asSeconds offset: utcOffset'.

DateAndTime compile: '- other
    (other isKindOf: Duration) ifTrue: [ ^ self + other negated ].
    ^ Duration seconds: utcSeconds - (self _secondsOf: other)'.

DateAndTime compile: '= other
    ^ (other isKindOf: DateAndTime) and: [ utcSeconds = other _utcSeconds ]'.

DateAndTime compile: '~= other
    ^ (self = other) not'.

DateAndTime compile: 'hash
    ^ utcSeconds hash'.

DateAndTime compile: '< other
    ^ utcSeconds < (self _secondsOf: other)'.

DateAndTime compile: '<= other
    ^ utcSeconds <= (self _secondsOf: other)'.

DateAndTime compile: '> other
    ^ utcSeconds > (self _secondsOf: other)'.

DateAndTime compile: '>= other
    ^ utcSeconds >= (self _secondsOf: other)'.

DateAndTime compile: 'between: lower and: upper
    ^ (self >= lower) and: [ self <= upper ]'.

DateAndTime compile: 'min: other
    ^ self < other ifTrue: [ self ] ifFalse: [ other ]'.

DateAndTime compile: 'max: other
    ^ self > other ifTrue: [ self ] ifFalse: [ other ]'.

DateAndTime compile: 'year
    ^ self _dateParts first'.

DateAndTime compile: 'month
    ^ self _dateParts at: 2'.

DateAndTime compile: 'dayOfMonth
    ^ self _dateParts at: 3'.

DateAndTime compile: 'dayOfYear
    ^ self _dateParts last'.

DateAndTime compile: 'dayOfWeek
    ^ ((self _localDay + 1) \\ 7) + 1'.

DateAndTime compile: 'isLeapYear
    ^ self class _isLeapYear: self year'.

DateAndTime compile: 'hour
    ^ self hour24'.

DateAndTime compile: 'hour24
    ^ self _timeOfDay hours'.

DateAndTime compile: 'hour12
    ^ ((self hour24 - 1) \\ 12) + 1'.

DateAndTime compile: 'minute
    ^ self _timeOfDay minutes'.

DateAndTime compile: 'second
    ^ self _timeOfDay seconds'.

DateAndTime compile: 'meridianAbbreviation
    ^ self hour24 < 12 ifTrue: [ ''AM'' ] ifFalse: [ ''PM'' ]'.

DateAndTime compile: 'monthName
    ^ #(''January'' ''February'' ''March'' ''April'' ''May'' ''June''
        ''July'' ''August'' ''September'' ''October'' ''November'' ''December'') at: self month'.

DateAndTime compile: 'monthAbbreviation
    ^ self monthName copyFrom: 1 to: 3'.

DateAndTime compile: 'dayOfWeekName
    ^ #(''Sunday'' ''Monday'' ''Tuesday'' ''Wednesday'' ''Thursday'' ''Friday'' ''Saturday'') at: self dayOfWeek'.

DateAndTime compile: 'dayOfWeekAbbreviation
    ^ self dayOfWeekName copyFrom: 1 to: 3'.

DateAndTime compile: 'timeZoneName
    ^ self timeZoneAbbreviation'.

DateAndTime compile: 'timeZoneAbbreviation
    ^ utcOffset asSeconds = 0 ifTrue: [ ''UTC'' ] ifFalse: [ ''UTC'' , self _offsetString ]'.

DateAndTime compile: '_offsetString
    | sign absolute hours text seconds |
    sign := utcOffset negative ifTrue: [ ''-'' ] ifFalse: [ ''+'' ].
    absolute := utcOffset abs.
    hours := absolute asSeconds // 3600.
    text := sign , (Duration _pad: hours to: 2) , '':'' , (Duration _pad: absolute minutes to: 2).
    seconds := absolute seconds.
    ^ seconds = 0 ifTrue: [ text ] ifFalse: [ text , '':'' , (Duration _printSeconds: seconds) ]'.

DateAndTime compile: 'printString
    | parts year sign time |
    parts := self _dateParts.
    year := parts first.
    sign := year < 0 ifTrue: [ ''-'' ] ifFalse: [ '' '' ].
    time := self _timeOfDay.
    ^ sign , (Duration _pad: year abs to: 4) , ''-'' ,
        (Duration _pad: (parts at: 2) to: 2) , ''-'' , (Duration _pad: (parts at: 3) to: 2) ,
        ''T'' , (Duration _pad: time hours to: 2) , '':'' , (Duration _pad: time minutes to: 2) ,
        '':'' , (Duration _printSeconds: time seconds) , self _offsetString'.
