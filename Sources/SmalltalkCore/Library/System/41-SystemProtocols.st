"Shipped method organization, including the VM primitives exposed by the browser."

BrowserOrganization compile: 'shippedProtocols
    ^ #(
        (''Object'' (
            (''Initialization'' (''initialize''))
            (''Comparing'' (''='' ''=='' ''~='' ''~~''))
            (''Nil Testing'' (''isNil'' ''notNil'' ''ifNil:'' ''ifNotNil:''))
            (''Reflection'' (''class'' ''isKindOf:'' ''isMemberOf:'' ''respondsTo:'' ''perform:'' ''perform:with:'' ''perform:with:with:''
                ''perform:with:with:with:'' ''perform:withArguments:''))
            (''Printing'' (''printString'' ''printOn:''))
            (''Identity and Copying'' (''yourself'' ''copy'' ''hash'' ''identityHash''))
            (''Error Reporting'' (''error:'' ''doesNotUnderstand:'' ''error:line:column:''))))
        (''Class'' (
            (''Instance Creation'' (''new'' ''new:''))
            (''Class Structure'' (''name'' ''superclass'' ''subclasses'' ''allSuperclasses'' ''allSubclasses'' ''instanceVariableNamesText''))
            (''Subclass Definition'' (''subclass:instanceVariableNames:'' ''subclass:instanceVariableNames:classInstanceVariableNames:''
                ''subclass:instanceVariableNames:classVariableNames:poolDictionaries:category:''))
            (''Method Dictionary'' (''compile:'' ''compileClass:'' ''methodNames'' ''methodSourceAt:'' ''classMethodNames'' ''classMethodSourceAt:'' ''isPrimitiveAt:''))))
        (''Metaclass'' ((''Class Structure'' (''instanceClass'' ''instanceVariableNames:''))))
        (''Number'' (
            (''Comparing'' (''between:and:'' ''min:'' ''max:''))
            (''Sign'' (''negative'' ''positive'' ''strictlyPositive'' ''sign''))
            (''Arithmetic'' (''quo:'' ''rem:'' ''reciprocal'' ''raisedTo:'' ''raisedToInteger:'' ''fractionPart''))
            (''Intervals'' (''to:'' ''to:by:''))
            (''Rounding and Conversion'' (''asInteger'' ''roundTo:'' ''truncateTo:''))))
        (''Integer'' (
            (''Arithmetic'' (''+'' ''-'' ''*'' ''/'' ''//'' ''\\'' ''negated'' ''abs'' ''squared''))
            (''Comparing'' (''<'' ''>'' ''<='' ''>=''))
            (''Bounds'' (''min:'' ''max:'' ''clampFrom:to:''))
            (''Rational Access'' (''numerator'' ''denominator'' ''asFraction''))
            (''Bit Operations'' (''bitAnd:'' ''bitOr:'' ''bitXor:'' ''bitShift:'' ''bitAt:'' ''bitAt:put:''
                ''allMask:'' ''anyMask:'' ''noMask:'' ''highBit''))
            (''Integer Arithmetic'' (''even'' ''odd'' ''factorial'' ''gcd:'' ''lcm:'' ''sqrt''))
            (''Rounding'' (''ceiling'' ''floor'' ''rounded'' ''truncated'' ''integerPart''))
            (''Printing'' (''printStringRadix:'' ''printOn:base:showRadix:''))
            (''Converting'' (''asCharacter'' ''asFloat'' ''asFloatE'' ''asFloatD'' ''asFloatQ'' ''asScaledDecimal:''))
            (''Iteration'' (''timesRepeat:'' ''to:do:'' ''to:by:do:''))))
        (''Boolean'' (
            (''Logical Operations'' (''not'' ''and:'' ''or:'' ''&'' ''|'' ''eqv:'' ''xor:''))
            (''Conditionals'' (''ifTrue:'' ''ifFalse:'' ''ifTrue:ifFalse:'' ''ifFalse:ifTrue:''))))
        (''Fraction'' (
            (''Rational Access'' (''numerator'' ''denominator'' ''asFraction'' ''integerPart''))
            (''Arithmetic'' (''+'' ''-'' ''*'' ''/'' ''//'' ''\\'' ''negated'' ''abs'' ''squared''))
            (''Comparing'' (''<'' ''>'' ''<='' ''>=''))
            (''Converting'' (''asFloat'' ''asFloatE'' ''asFloatD'' ''asFloatQ'' ''asScaledDecimal:'' ''floor'' ''ceiling'' ''rounded'' ''truncated''))
            (''Mathematical Functions'' (''sqrt''))
            (''Iteration'' (''to:do:'' ''to:by:do:''))))
        (''ScaledDecimal'' (
            (''Accessing'' (''scale'' ''integerPart'' ''fractionPart''))
            (''Arithmetic'' (''+'' ''-'' ''*'' ''/'' ''//'' ''\\'' ''negated'' ''abs'' ''squared'' ''reciprocal'' ''sqrt''))
            (''Comparing'' (''<'' ''>'' ''<='' ''>='' ''negative'' ''positive'' ''strictlyPositive'' ''sign''))
            (''Converting'' (''asFraction'' ''asScaledDecimal:'' ''asFloat'' ''asFloatE'' ''asFloatD'' ''asFloatQ''
                ''asInteger'' ''rounded'' ''floor'' ''ceiling'' ''truncated''))
            (''Iteration'' (''to:do:'' ''to:by:do:''))))
        (''Float'' (
            (''Arithmetic'' (''+'' ''-'' ''*'' ''/'' ''//'' ''\\'' ''negated'' ''abs'' ''squared''))
            (''Comparing'' (''<'' ''>'' ''<='' ''>=''))
            (''Converting'' (''asFloat'' ''asFloatE'' ''asFloatD'' ''asFloatQ'' ''asScaledDecimal:'' ''ceiling'' ''floor'' ''truncated'' ''rounded'' ''asFraction'' ''integerPart''))
            (''Mathematical Functions'' (''sqrt'' ''exp'' ''ln'' ''log:'' ''floorLog:''))
            (''Trigonometry'' (''sin'' ''cos'' ''tan'' ''arcSin'' ''arcCos'' ''arcTan'' ''degreesToRadians'' ''radiansToDegrees''))
            (''Iteration'' (''to:do:'' ''to:by:do:''))))
        (''Collection'' (
            (''Testing'' (''notEmpty'' ''allSatisfy:'' ''anySatisfy:'' ''occurrencesOf:''))
            (''Searching'' (''detect:'' ''detect:ifNone:''))
            (''Enumerating'' (''do:separatedBy:'' ''inject:into:'' ''reject:''))
            (''Converting'' (''asArray'' ''asBag'' ''asByteArray'' ''asOrderedCollection'' ''asSet''
                ''asSortedCollection'' ''asSortedCollection:''))
            (''Maintenance'' (''rehash''))))
        (''SequenceableCollection'' (
            (''Accessing'' (''at:ifAbsent:'' ''first'' ''last'' ''before:'' ''after:''))
            (''Searching'' (''findFirst:'' ''findLast:'' ''indexOf:'' ''indexOf:ifAbsent:''
                ''indexOfSubCollection:startingAt:'' ''indexOfSubCollection:startingAt:ifAbsent:''))
            (''Enumerating'' (''from:to:do:'' ''from:to:keysAndValuesDo:'' ''keysAndValuesDo:'' ''reverseDo:'' ''with:do:''))
            (''Copying'' (''copyFrom:to:'' ''copyWith:'' ''reverse'' ''copyReplacing:withObject:''
                ''copyReplaceFrom:to:with:'' ''copyReplaceFrom:to:withObject:'' ''copyReplaceAll:with:'' ''copyWithout:''))
            (''Private'' (''_sequenceFrom:''))))
        (''OrderedCollection'' (
            (''Initialization'' (''initialize''))
            (''Accessing'' (''size'' ''at:'' ''isEmpty'' ''includes:''))
            (''Updating'' (''at:put:'' ''atAll:put:'' ''atAllPut:'' ''replaceFrom:to:with:''
                ''replaceFrom:to:with:startingAt:'' ''replaceFrom:to:withObject:''))
            (''Adding'' (''add:'' ''addFirst:'' ''addLast:'' ''add:after:'' ''add:before:'' ''add:afterIndex:'' ''add:beforeIndex:''
                ''addAll:'' ''addAllFirst:'' ''addAllLast:'' ''addAll:after:'' ''addAll:before:'' ''addAll:afterIndex:'' ''addAll:beforeIndex:''))
            (''Removing'' (''remove:'' ''remove:ifAbsent:'' ''removeAll:'' ''removeAtIndex:'' ''removeFirst'' ''removeLast''))
            (''Enumerating'' (''do:'' ''collect:'' ''select:''))
            (''Copying and Conversion'' (''copy'' '','' ''asArray''))
            (''Private'' (''_reserve:'' ''_makeRoomFor:'' ''_checkIndex:'' ''_checkInsertionIndex:'' ''_positionOf:''
                ''_spliceAt:remove:with:'' ''_sequenceFrom:''))))
        (''UnorderedCollection'' (
            (''Initialization'' (''initialize'' ''_reserve:''))
            (''Accessing'' (''size'' ''isEmpty'' ''includes:''))
            (''Adding'' (''addAll:''))
            (''Removing'' (''remove:'' ''remove:ifAbsent:'' ''removeAll:''))
            (''Enumerating'' (''do:'' ''collect:'' ''select:''))
            (''Copying and Conversion'' (''copy'' ''asArray''))))
        (''Bag'' ((''Adding'' (''add:'' ''add:withOccurrences:''))))
        (''Set'' ((''Adding'' (''add:''))))
        (''Dictionary'' (
            (''Initialization'' (''initialize''))
            (''Accessing'' (''at:'' ''at:ifAbsent:'' ''at:ifAbsentPut:'' ''keys'' ''values'' ''size'' ''isEmpty''))
            (''Searching'' (''includesKey:'' ''includes:'' ''keyAtValue:'' ''keyAtValue:ifAbsent:''))
            (''Updating'' (''at:put:'' ''addAll:''))
            (''Removing'' (''removeKey:'' ''removeKey:ifAbsent:'' ''removeAllKeys:'' ''removeAllKeys:ifAbsent:''))
            (''Enumerating'' (''do:'' ''keysDo:'' ''keysAndValuesDo:'' ''collect:'' ''select:''))
            (''Copying'' (''copy''))
            (''Private'' (''_reserve:'' ''_indexOfKey:'' ''_key:matches:''))))
        (''IdentityDictionary'' ((''Private'' (''_key:matches:''))))
        (''ByteArray'' (
            (''Initialization'' (''initialize''))
            (''Accessing'' (''size'' ''at:'' ''isEmpty'' ''includes:''))
            (''Updating'' (''at:put:'' ''atAll:put:'' ''atAllPut:'' ''replaceFrom:to:with:''
                ''replaceFrom:to:with:startingAt:'' ''replaceFrom:to:withObject:''))
            (''Enumerating'' (''do:'' ''collect:'' ''select:''))
            (''Copying and Conversion'' (''copy'' '','' ''asArray''))
            (''Private'' (''_size:'' ''_initializeFrom:'' ''_checkByte:'' ''_sequenceFrom:''))))
        (''SortedCollection'' (
            (''Initialization'' (''initialize''))
            (''Accessing'' (''size'' ''at:'' ''isEmpty'' ''includes:''))
            (''Sorting'' (''sortBlock'' ''sortBlock:''))
            (''Adding'' (''add:'' ''addAll:''))
            (''Removing'' (''remove:'' ''remove:ifAbsent:'' ''removeAll:'' ''removeAtIndex:'' ''removeFirst'' ''removeLast''))
            (''Enumerating'' (''do:'' ''collect:'' ''select:'' ''reverse''))
            (''Copying and Conversion'' (''copy'' '','' ''asArray'' ''asSortedCollection''))
            (''Private'' (''_elements'' ''_reserve:'' ''_sorted:by:'' ''_sequenceFrom:''))))
        (''String'' (
            (''Accessing'' (''size'' ''at:'' ''characters'' ''isEmpty''))
            (''Updating'' (''at:put:'' ''atAll:put:'' ''atAllPut:'' ''replaceFrom:to:with:''
                ''replaceFrom:to:with:startingAt:'' ''replaceFrom:to:withObject:''))
            (''Enumerating'' (''do:'' ''collect:'' ''select:''))
            (''Case Conversion'' (''asLowercase'' ''asUppercase''))
            (''Comparing'' (''sameAs:'' ''<'' ''<='' ''>'' ''>='' ''min:'' ''max:'' ''between:and:''))
            (''Private'' (''_sequenceFrom:'' ''_replaceCharacters:''))
            (''Combining'' ('',''))
            (''Searching'' (''includes:'' ''subStrings:''))
            (''Character Testing'' (''isLetter'' ''isNumber'' ''isASCIIDigit'' ''isLowercase'' ''isWhitespace'' ''isLineBreak''))
            (''Converting'' (''asString'' ''asSymbol'' ''asCharacter'' ''asIntegerOrNil'' ''parseIntegerMagnitudeRadix:'' ''parseFloatOrNil'' ''parseScaledDecimalOrNil''))))
        (''Character'' (
            (''Converting'' (''asString'' ''asLowercase'' ''asUppercase'' ''codePoint''))
            (''Testing'' (''isAlphaNumeric'' ''isDigit'' ''isLetter'' ''isLowercase'' ''isUppercase''))
            (''Identity'' (''hash'' ''identityHash''))))
        (''Symbol'' (
            (''Accessing'' (''size'' ''at:'' ''isEmpty'' ''includes:''))
            (''Enumerating'' (''do:'' ''collect:'' ''select:''))
            (''Text'' (''asString'' ''asSymbol'' ''asLowercase'' ''asUppercase'' ''subStrings:'' '',''))
            (''Comparing'' (''sameAs:'' ''<'' ''<='' ''>'' ''>='' ''min:'' ''max:'' ''between:and:''))
            (''Private'' (''_sequenceFrom:''))))
        (''Array'' (
            (''Accessing'' (''size'' ''at:'' ''at:ifAbsent:'' ''first'' ''last''))
            (''Updating'' (''at:put:'' ''atAll:put:'' ''atAllPut:'' ''replaceFrom:to:with:''
                ''replaceFrom:to:with:startingAt:'' ''replaceFrom:to:withObject:''))
            (''Enumerating'' (''do:'' ''collect:'' ''select:''))
            (''Testing'' (''isEmpty'' ''includes:''))
            (''Copying'' (''copyWith:'' ''copyFrom:to:'' ''reverse'' '',''))
            (''Converting'' (''joinedStringFrom:to:''))))
        (''Interval'' (
            (''Initialization'' (''initializeFrom:to:by:''))
            (''Accessing'' (''size'' ''at:'' ''isEmpty'' ''includes:''))
            (''Enumerating'' (''do:'' ''collect:'' ''select:''))
            (''Copying'' ('',''))))
        (''BlockClosure'' (
            (''Evaluation'' (''value'' ''value:'' ''value:value:'' ''argumentCount'' ''valueWithArguments:''))
            (''Exception Handling'' (''on:do:''))
            (''Termination'' (''ensure:'' ''ifCurtailed:''))
            (''Looping'' (''whileTrue'' ''whileFalse'' ''whileTrue:'' ''whileFalse:''))))
        (''FailedMessage'' ((''Accessing'' (''selector'' ''arguments''))))
        (''Exception'' (
            (''Exception Description'' (''messageText'' ''messageText:'' ''tag'' ''tag:'' ''description'' ''isResumable''))
            (''Signaling'' (''signal'' ''signal:'' ''defaultAction'' ''_signalException'' ''_failUnhandledException''))
            (''Handler Control'' (''isNested'' ''outer'' ''pass'' ''resignalAs:'' ''resume'' ''resume:''
                ''retry'' ''retryUsing:'' ''return'' ''return:''))))
        (''ExceptionSet'' ((''Handler Selection'' (''selectors:'' ''handles:'' '',''))))
        (''MessageNotUnderstood'' ((''Exception Description'' (''receiver:message:'' ''receiver'' ''message'' ''description'' ''isResumable''))))
        (''ZeroDivide'' ((''Exception Description'' (''dividend:'' ''dividend'' ''description'' ''isResumable''))))
        (''Transcript'' (
            (''Writing'' (''show:'' ''nextPut:'' ''nextPutAll:'' ''cr'' ''space'' ''tab'' ''flush''))
            (''Buffer Management'' (''clear'' ''record:''))))
        (''Counter'' (
            (''Initialization'' (''initialize''))
            (''Accessing'' (''value''))
            (''Counting'' (''increment'' ''add:''))))
        (''STCompilerList'' (
            (''Initialization'' (''initialize''))
            (''Accumulating'' (''add:''))
            (''Extracting Contents'' (''elements'' ''joinedString''))))
        (''STScanner'' (
            (''Input Setup'' (''initialize'' ''source:''))
            (''Character Stream'' (''peek'' ''peekAhead:'' ''advance''))
            (''Character Classification'' (''isBinary:'' ''isIdentifierStart:'' ''isIdentifierPart:''))
            (''Tokenization'' (''nextToken'' ''readToken'' ''token:value:'' ''skipTrivia'' ''readComment''))
            (''Literal Scanning'' (''readNumber'' ''readDigits'' ''readRadixInteger:'' ''integerToken:radix:'' ''readString'' ''readSymbol''))
            (''Identifier Scanning'' (''readIdentifier'' ''readWord''))
            (''Error Reporting'' (''fail:''))))
        (''STSourceScanner'' ((''Highlighting'' (''nextHighlight'' ''token:value:'' ''highlight:'' ''fail:''))))
        (''STCompiler'' (
            (''Compilation'' (''initialize'' ''start:'' ''workspace:'' ''method:''))
            (''Token Handling'' (''advance'' ''expect:'' ''kind'' ''tokenValue'' ''tokenLabel:'' ''identifier''))
            (''Body Parsing'' (''workspaceBody'' ''bodyUntil:'' ''blockAt:'' ''returnStatement''))
            (''Expression Parsing'' (''expression'' ''expressionNode'' ''primary'' ''unaryExpression'' ''binaryExpression'' ''keywordExpression''))
            (''Message Parsing'' (''unaryMessage'' ''binaryMessage'' ''keywordMessage'' ''cascadeMessage''))
            (''Literal Parsing'' (''arrayElement'' ''arrayElements'' ''negativeNumber'' ''floatFrom:''))
            (''Syntax Trees'' (''node:at:with:with:'' ''single:'' ''pair:with:'' ''triple:with:with:'' ''sendTo:message:''))
            (''Validation and Errors'' (''fail:'' ''validateNames:'' ''validate:separateFrom:error:''))))
        (''Model'' (
            (''Initialization'' (''initialize''))
            (''Managing Dependents'' (''dependents'' ''addDependent:'' ''removeDependent:''))
            (''Change Notifications'' (''changed'' ''changed:''))))
        (''Controller'' (
            (''Initialization'' (''initialize''))
            (''Model Access'' (''model'' ''model:''))))
        (''UIBinding'' (
            (''Configuration'' (''initialize'' ''source:aspect:view:property:''))
            (''Binding Properties'' (''source'' ''aspect'' ''view'' ''property'' ''active''))
            (''Connection Lifecycle'' (''connect'' ''disconnect'' ''reconcileMount:''))
            (''Model Updates'' (''update:''))))
        (''SystemWindow'' (
            (''Initialization'' (''initialize''))
            (''Identity and Content'' (''id'' ''id:'' ''kind'' ''kind:'' ''title'' ''title:'' ''text'' ''text:''))
            (''Window Lifecycle'' (''open'' ''close'' ''canClose'' ''activate'' ''minimized'' ''minimized:''))
            (''Geometry'' (''x'' ''y'' ''width'' ''height'' ''moveToX:y:'' ''resizeWidth:height:'' ''placeX:y:width:height:''))
            (''Size Constraints'' (''minimumWidth'' ''minimumHeight'' ''maximumWidth'' ''maximumHeight''
                ''minimumWidth:height:'' ''maximumWidth:height:'' ''nativeMinimumWidth:height:maximumWidth:height:''))
            (''Native Synchronization'' (''frameRevision'' ''stateRevision'' ''frameApplied:x:y:width:height:''
                ''observeX:y:width:height:'' ''observeMinimized:''))))
        (''DesktopModel'' (
            (''Initialization'' (''initialize''))
            (''Window State'' (''windows'' ''windows:'' ''activeWindow'' ''activeWindow:''))
            (''Window Identifiers'' (''nextID'' ''nextID:''))
            (''Display State'' (''screens'' ''screens:''))
            (''Focus Requests'' (''focusRevision'' ''requestFocus''))))
        (''DisplayScreen'' (
            (''Identity and Bounds'' (''id'' ''x'' ''y'' ''width'' ''height''))
            (''Window Placement Metrics'' (''distanceTo:'' ''overlapWith:''))))
        (''DesktopManager'' (
            (''Initialization'' (''initialize''))
            (''Window Registry'' (''windows'' ''append:'' ''nextID'' ''windowAt:'' ''windowOfKind:'' ''activeWindow''))
            (''Opening Tools'' (''createKind:title:'' ''windowClassFor:'' ''openWorkspace'' ''showWorkspace''
                ''openBrowser'' ''openTranscript'' ''openChanges'' ''showChangesFor:selector:side:'' ''openWindow''))
            (''Tool Synchronization'' (''catalogChanged'' ''synchronizeChanges''))
            (''Window Lifecycle'' (''open:'' ''requestClose:'' ''close:'' ''minimize:''))
            (''Focus and Ordering'' (''chooseActive'' ''bringToFront:'' ''activate:'' ''observeActivation:'' ''observeMinimized:value:''))
            (''Displays and Placement'' (''screens'' ''screenFor:'' ''screensChanged:'' ''constrain:'' ''restoreWindows'' ''cascadeTool:'' ''arrangeTools''))))
        (''UIElement'' (
            (''Initialization'' (''initialize''))
            (''Identity and Appearance'' (''identifier:'' ''role:''))
            (''Interaction State'' (''enabled'' ''enabled:'' ''visible'' ''visible:''))
            (''Size Constraints'' (''widthFrom:to:'' ''heightFrom:to:''))
            (''Model Bindings'' (''bindings'' ''bind:to:aspect:'' ''unbind:'' ''unbindAll''))))
        (''UILabel'' (
            (''Initialization'' (''initialize''))
            (''Text'' (''text'' ''text:''))))
        (''UIButton'' (
            (''Initialization'' (''initialize''))
            (''Labeling'' (''title'' ''title:'' ''shortcutHint:'' ''icon:''))
            (''Action Configuration'' (''action:'' ''command:'' ''onClickSend:to:'' ''selectionFrom:action:''))
            (''Activation'' (''click'' ''clickWithSelection:''))))
        (''UITextField'' (
            (''Initialization'' (''initialize''))
            (''Label and Placeholder'' (''label'' ''label:'' ''placeholder'' ''placeholder:''))
            (''Text'' (''text'' ''text:''))
            (''Input Handling'' (''editText:'' ''onChangeSend:to:''))))
        (''UICodeEditor'' (
            (''Initialization'' (''initialize''))
            (''Editing Permissions'' (''readOnly:'' ''undoEnabled:''))
            (''Source Display'' (''role:'' ''lineNumbers:'' ''syntaxHighlighting:''))
            (''Context Menu'' (''contextMenu'' ''contextMenu:'' ''editingMenu:''))))
        (''UIList'' (
            (''Initialization'' (''initialize''))
            (''List Contents'' (''items:''))
            (''Selection'' (''selection:'' ''select:'' ''onSelectSend:to:''))))
        (''UIHistoryList'' (
            (''Initialization'' (''initialize''))
            (''History Entries'' (''entries:'' ''includes:'' ''rowIdentifierPrefix:'' ''command:''))))
        (''UISourceView'' (
            (''Initialization'' (''initialize''))
            (''Source'' (''text:'' ''line:column:''))))
        (''UIValueTable'' (
            (''Initialization'' (''initialize''))
            (''Table Contents'' (''rows:'' ''headings:'' ''rowIdentifierPrefix:''))
            (''Layout'' (''nameWidth:classWidth:'' ''columnSpacing:padding:'' ''valueLines:''))
            (''Selection'' (''command:'' ''readOnly:''))))
        (''UIContainer'' (
            (''Initialization'' (''initialize''))
            (''Child Management'' (''children'' ''children:'' ''add:'' ''remove:'' ''removeAll''))
            (''Layout Spacing'' (''spacing'' ''spacing:'' ''padding'' ''padding:''))))
        (''UIWindow'' (
            (''Initialization'' (''initialize''))
            (''Window Content'' (''content'' ''content:''))))
        (''UIVerticalSplit'' ((''Initialization'' (''initialize''))))
        (''UIScroll'' ((''Context Menu'' (''contextMenu:''))))
        (''UIMenu'' (
            (''Initialization'' (''initialize''))
            (''Labeling'' (''title:''))))
        (''BrowserGroup'' (
            (''Initialization'' (''initialize''))
            (''Naming'' (''name'' ''name:'' ''defaultName'' ''defaultName:'' ''isDeclared''))
            (''Membership'' (''items'' ''items:'' ''includes:''))))
        (''BrowserGrouping'' (
            (''Initialization'' (''initialize'' ''defineDefaults:'' ''defineGroup:items:''))
            (''Group Lookup'' (''names'' ''namesWith:'' ''groupNamed:''))
            (''Group Editing'' (''addGroup:'' ''renameGroup:to:'' ''nameError:''))
            (''Membership'' (''explicitGroupOf:'' ''groupOf:default:'' ''move:to:''))))
        (''BrowserOrganization'' (
            (''Initialization'' (''initialize'' ''shippedProtocols'' ''shippedClassSideProtocols''
                ''refreshShippedProtocols'' ''fileShippedProtocolsOf:side:into:''))
            (''Class Categories'' (''classCategories'' ''categoryOf:'' ''defaultCategoryOf:''))
            (''Method Protocols'' (''protocolsOf:'' ''protocolsOf:side:''))))
        (''BrowserOrganizationForm'' (
            (''Initialization'' (''initialize''))
            (''Presenting Edits'' (''edit:name:do:'' ''move:choices:selected:do:''))
            (''Applying Edits'' (''chooseDestination:'' ''apply'' ''cancel''))))
        (''BrowserNavigationPane'' ((''Initialization'' (''initialize''))))
        (''ChangesBrowser'' (
            (''Layout'' (''initialize'' ''buildContent''))
            (''History'' (''showClass:selector:side:'' ''allChanges'' ''synchronizeHistory'' ''reload''))
            (''Version Selection'' (''select:'' ''restoreSelected''))))
        (''InspectorModel'' (
            (''Opening'' (''openOn:'' ''levelFor:named:'' ''currentLevel''))
            (''Navigation'' (''dropTo:'' ''back'' ''follow:''))
            (''Pagination'' (''page:'' ''changePageBy:'' ''pageSize''))
            (''Snapshot'' (''refresh''))))
        (''ObjectInspectorWindow'' (
            (''Initialization'' (''initialize''))))
        (''DevelopmentWindow'' (
            (''Shared Layout'' (''heading:'' ''caption:'' ''resultPane'' ''toggleResult'' ''resultExpanded:''))
            (''Result Display'' (''result:''))))
        (''DebuggerWindow'' (
            (''Initialization'' (''initialize''))))
        (''WorkspaceWindow'' (
            (''Initialization'' (''initialize''))
            (''Code Evaluation'' (''text:'' ''sourceForSelection:'' ''doIt:'' ''printIt:'' ''inspect:'' ''debugIt:'' ''execute:printing:''))
            (''Menus'' (''editorMenu'' ''applicationCommands'' ''evaluationMenu'' ''actionsMenu'' ''selectionButton:command:action:''))
            (''Examples'' (''examplesMenu'' ''exampleButton:key:''))))
        (''BrowserWindow'' (
            (''Initialization'' (''initialize''))
            (''Pane Layout'' (''list:selecting:'' ''organizationItem:id:send:'' ''pane:list:action:'' ''withAll:''))
            (''Navigation'' (''chooseCategory:'' ''chooseClass:'' ''chooseProtocol:'' ''chooseMethod:''
                ''filter:'' ''matchesCategory:'' ''selectedClass'' ''protocolOf:in:''
                ''showInstanceMethods'' ''showClassMethods'' ''chooseMethodSide:''))
            (''Catalog Updates'' (''refreshClasses'' ''refreshMethods'' ''refreshTools'' ''refreshOrganizationActions''))
            (''Method Editing'' (''acceptMethod'' ''canAccept:for:'' ''draftChanged:'' ''newMethod'' ''primitiveSelected''
                ''refreshEditor'' ''showVersions''))
            (''Class Definitions'' (''showDefinition'' ''acceptDefinition''))
            (''Bytecode'' (''toggleBytecode'' ''refreshBytecode''))
            (''Result Display'' (''result:''))
            (''Organization Editing'' (''editGroupIn:named:prompt:selecting:'' ''moveItem:in:from:prompt:selecting:''
                ''newCategory'' ''renameCategory'' ''moveClass'' ''newProtocol'' ''renameProtocol'' ''moveMethod'' ''organizationEdited:''))))
        (''TranscriptModel'' (
            (''Initialization'' (''initialize''))
            (''Output Buffer'' (''text'' ''append:'' ''clear''))))
        (''TranscriptWindow'' (
            (''Initialization'' (''initialize''))))
        (''SettingsWindow'' (
            (''Layout'' (''initialize'' ''buildContent''))))
        (''TestCase'' (
            (''Fixtures'' (''setUp'' ''tearDown''))
            (''Assertions'' (''assert:'' ''deny:'' ''assert:equals:'' ''fail:''))))
        (''TestOutcome'' (
            (''Initialization'' (''initialize'' ''testClass:selector:''))
            (''Outcome'' (''testClass'' ''selector'' ''diagnostics'' ''status'' ''record:during:''))))
        (''TestResult'' (
            (''Initialization'' (''initialize'' ''outcomes:''))
            (''Results'' (''outcomes'' ''testCount'' ''passedCount'' ''failureCount'' ''errorCount'' ''isSuccess'' ''summary''))))
        (''CounterTest'' (
            (''Fixtures'' (''setUp''))
            (''Tests'' (''testIncrement'' ''testCountersStartIndependently''))))
        (''CollectionsTest'' (
            (''Tests'' (''testArrayCollectAndSelect'' ''testFalseAndDoesNotEvaluateItsBlock''))))
        (''BindingTestModel'' (
            (''Accessing'' (''caption'' ''caption:''))))
        (''UIBindingTest'' (
            (''Fixtures'' (''setUp'' ''tearDown''))
            (''Tests'' (''testBindingReadsAndUpdatesTheLabel'' ''testUnbindingStopsUpdates''))))
        (''ANSIDispatchProbe'' ((''Dispatch'' (''touch'' ''doesNotUnderstand:'')) (''Exception Selection'' (''handles:''))))
        (''ANSIClassStateProbe'' ((''Accessing'' (''slot''))))
        (''ANSIProbeException'' ((''Signaling'' (''defaultAction'' ''isResumable''))))
        (''ANSISmalltalkTest'' (
            (''Language Tests'' (''testMessagePrecedence'' ''testCascadeUsesTheSameReceiver''
                ''testMethodReturnAndSuper'' ''testFailedSendCarriesSelectorAndArguments''
                ''testRadixLiteralsAndFloorDivision'' ''testFloatLiteralsAndPrecisionOrdering''
                ''testCharacterLiteralsAndStringElements'' ''testLiteralArrayValuesAndSymbolIdentity''
                ''testLexicalBlockBindings'' ''testValuableProtocol'' ''testBooleanShortCircuitAndLoop''
                ''testCleanupRunsInUnwindOrder''))
            (''Class Tests'' (''testClassObjectsHaveDistinctMetaclasses'' ''testClassInstanceVariablesBelongToTheReceivingClass''))
            (''Object Tests'' (''testObjectCopyClassTestsAndHash''))
            (''Text Tests'' (''testStringFactoriesAndReadableStringProtocols''))
            (''Number Tests'' (''testLargeIntegerArithmetic'' ''testLargeIntegerFloorDivision'' ''testExactFractions''
                ''testScaledDecimalLiterals'' ''testScaledDecimalExactArithmetic'' ''testScaledDecimalDivision''
                ''testScaledDecimalMixedNumericTypes'' ''testScaledDecimalConversions'' ''testScaledDecimalWithWideCoefficient''
                ''testIntegerBitAndNumberTheoryProtocols'' ''testNumericConversionsAndIntervals''))
            (''Collection Tests'' (''testArrayFactoriesAndIndexedCopy'' ''testLargeArrayIsOneBasedAndInitiallyNil''
                ''testCollectionSearchingAndEnumeration'' ''testSequenceCopyAndOverlappingReplacement''
                ''testBagCountsAndRemovesOccurrences'' ''testSetUsesEqualityAndSuppressesDuplicates''
                ''testOrderedCollectionInsertsAndRemovesAtBoundaries'' ''testOrderedCollectionSnapshotsOverlappingUpdates''
                ''testByteArrayFactoriesBoundsAndReplacement'' ''testSortedCollectionInsertionAndResorting''
                ''testSortedCollectionResultsKeepTheirRequiredOrdering'' ''testCollectionConversions''))
            (''Dictionary Tests'' (''testDictionaryUsesEquivalentKeys'' ''testIdentityDictionaryKeepsEquivalentKeysSeparate''
                ''testDictionaryDistinguishesNilValuesFromAbsentKeys'' ''testDictionaryEnumeratesKeysAndValues''
                ''testDictionaryCollectionOperationsPreserveKeysAndType'' ''testDictionaryCopiesMergesAndRemovesKeyGroups''
                ''testDictionaryEnumerationVisitsASnapshot''))
            (''Exception Tests'' (''testExceptionNormalCompletion'' ''testExceptionSignalersAndMetadata''
                ''testExceptionSelectsNearestMatchingHandler'' ''testExceptionFromAnActionUsesTheOuterEnvironment''
                ''testExceptionHandlerRunsBeforeUnwindBlocks'' ''testExceptionActionCanReturnFromItsHomeMethod''
                ''testExceptionSelectorUsesHandles'' ''testExceptionDefaultAction''
                ''testExceptionRetryReturnAndResignal'' ''testExceptionResumeOuterPassAndSets'' ''testStandardErrorsCarryTheirArguments''))
            (''Test Support'' (''returnThroughCleanup:'' ''returnThroughException:''))))
    )'.

BrowserOrganization compile: 'shippedClassSideProtocols
    ^ #(
        (''Collection'' ((''Instance Creation'' (''with:'' ''with:with:'' ''with:with:with:'' ''with:with:with:with:'' ''withAll:''))))
        (''UnorderedCollection'' ((''Instance Creation'' (''new:''))))
        (''Dictionary'' ((''Instance Creation'' (''new:'' ''withAll:''))))
        (''ByteArray'' ((''Instance Creation'' (''new:'' ''withAll:''))))
        (''OrderedCollection'' ((''Instance Creation'' (''new:''))))
        (''SortedCollection'' (
            (''Instance Creation'' (''new:'' ''withAll:'' ''sortBlock:''))
            (''Sorting'' (''_defaultSortBlock''))))
        (''Array'' ((''Instance Creation'' (''with:'' ''with:with:'' ''with:with:with:'' ''with:with:with:with:'' ''withAll:''))))
        (''String'' ((''Instance Creation'' (''with:'' ''with:with:'' ''with:with:with:'' ''with:with:with:with:'' ''withAll:''))))
        (''Character'' (
            (''Instance Creation'' (''codePoint:''))
            (''Control Characters'' (''cr'' ''lf'' ''space'' ''tab''))))
        (''Float'' (
            (''Representation'' (''radix'' ''precision'' ''emin'' ''emax'' ''denormalized'' ''epsilon'' ''fmax''
                ''fmin'' ''fminNormalized'' ''fminDenormalized''))
            (''Constants'' (''pi'' ''e''))))
        (''Fraction'' ((''Instance Creation'' (''numerator:denominator:''))))
        (''Exception'' ((''Signaling'' (''signal'' ''signal:'')) (''Handler Selection'' (''handles:'' '',''))))
        (''ZeroDivide'' ((''Signaling'' (''dividend:''))))
        (''Interval'' ((''Instance Creation'' (''from:to:'' ''from:to:by:''))))
    )'.
