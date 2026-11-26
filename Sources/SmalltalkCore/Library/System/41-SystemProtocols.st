"Shipped method organization, including the VM primitives exposed by the browser."

BrowserOrganization compile: 'shippedProtocols
    ^ #(
        (''Object'' (
            (''Initialization'' (''initialize''))
            (''Comparing'' (''='' ''=='' ''~='' ''~~''))
            (''Nil Testing'' (''isNil'' ''notNil'' ''ifNil:'' ''ifNotNil:''))
            (''Reflection'' (''class'' ''respondsTo:'' ''perform:'' ''perform:with:'' ''perform:with:with:''
                ''perform:with:with:with:'' ''perform:withArguments:''))
            (''Printing'' (''printString''))
            (''Identity'' (''yourself''))
            (''Error Reporting'' (''error:'' ''error:line:column:''))))
        (''Class'' (
            (''Instance Creation'' (''new'' ''new:''))
            (''Class Structure'' (''name'' ''superclass'' ''subclasses'' ''allSuperclasses'' ''allSubclasses'' ''instanceVariableNamesText''))
            (''Subclass Definition'' (''subclass:instanceVariableNames:'' ''subclass:instanceVariableNames:classInstanceVariableNames:''
                ''subclass:instanceVariableNames:classVariableNames:poolDictionaries:category:''))
            (''Method Dictionary'' (''compile:'' ''compileClass:'' ''methodNames'' ''methodSourceAt:'' ''classMethodNames'' ''classMethodSourceAt:'' ''isPrimitiveAt:''))))
        (''Metaclass'' ((''Class Structure'' (''instanceClass'' ''instanceVariableNames:''))))
        (''Integer'' (
            (''Arithmetic'' (''+'' ''-'' ''*'' ''/'' ''//'' ''\\'' ''negated'' ''abs'' ''squared''))
            (''Comparing'' (''<'' ''>'' ''<='' ''>=''))
            (''Bounds'' (''min:'' ''max:'' ''clampFrom:to:''))
            (''Rational Access'' (''numerator'' ''denominator''))
            (''Converting'' (''asCharacter'' ''asFloat'' ''asFloatE'' ''asFloatD'' ''asFloatQ'' ''asScaledDecimal:''))
            (''Iteration'' (''timesRepeat:'' ''to:do:'' ''to:by:do:''))))
        (''Boolean'' (
            (''Logical Operations'' (''not'' ''and:'' ''or:'' ''&'' ''|'' ''eqv:'' ''xor:''))
            (''Conditionals'' (''ifTrue:'' ''ifFalse:'' ''ifTrue:ifFalse:'' ''ifFalse:ifTrue:''))))
        (''Fraction'' (
            (''Rational Access'' (''numerator'' ''denominator''))
            (''Arithmetic'' (''+'' ''-'' ''*'' ''/'' ''//'' ''\\'' ''negated'' ''abs'' ''squared''))
            (''Comparing'' (''<'' ''>'' ''<='' ''>=''))
            (''Converting'' (''asFloat'' ''asFloatE'' ''asFloatD'' ''asFloatQ'' ''asScaledDecimal:'' ''floor'' ''ceiling'' ''rounded'' ''truncated''))))
        (''ScaledDecimal'' (
            (''Accessing'' (''scale'' ''integerPart'' ''fractionPart''))
            (''Arithmetic'' (''+'' ''-'' ''*'' ''/'' ''//'' ''\\'' ''negated'' ''abs'' ''squared'' ''reciprocal''))
            (''Comparing'' (''<'' ''>'' ''<='' ''>='' ''negative'' ''positive'' ''strictlyPositive'' ''sign''))
            (''Converting'' (''asFraction'' ''asScaledDecimal:'' ''asFloat'' ''asFloatE'' ''asFloatD'' ''asFloatQ''
                ''asInteger'' ''rounded'' ''floor'' ''ceiling'' ''truncated''))))
        (''Float'' (
            (''Arithmetic'' (''+'' ''-'' ''*'' ''/'' ''//'' ''\\'' ''negated'' ''abs'' ''squared''))
            (''Comparing'' (''<'' ''>'' ''<='' ''>=''))
            (''Converting'' (''asFloat'' ''asFloatE'' ''asFloatD'' ''asFloatQ'' ''asScaledDecimal:'' ''ceiling'' ''floor'' ''truncated'' ''rounded''))
            (''Mathematical Functions'' (''sqrt'' ''exp'' ''ln'' ''raisedTo:'' ''sin'' ''cos'' ''tan''))))
        (''String'' (
            (''Accessing'' (''size'' ''at:'' ''characters''))
            (''Combining'' ('',''))
            (''Searching'' (''includes:''))
            (''Character Testing'' (''isLetter'' ''isNumber'' ''isASCIIDigit'' ''isLowercase'' ''isWhitespace'' ''isLineBreak''))
            (''Converting'' (''asString'' ''asSymbol'' ''asCharacter'' ''asIntegerOrNil'' ''parseIntegerMagnitudeRadix:'' ''parseFloatOrNil'' ''parseScaledDecimalOrNil''))))
        (''Character'' (
            (''Converting'' (''asString'' ''asLowercase'' ''asUppercase'' ''codePoint''))
            (''Testing'' (''isAlphaNumeric'' ''isDigit'' ''isLetter'' ''isLowercase'' ''isUppercase''))
            (''Identity'' (''hash'' ''identityHash''))))
        (''Symbol'' (
            (''Converting'' (''asString''))))
        (''Array'' (
            (''Accessing'' (''size'' ''at:'' ''at:ifAbsent:'' ''first'' ''last''))
            (''Updating'' (''at:put:''))
            (''Enumerating'' (''do:'' ''collect:'' ''select:''))
            (''Testing'' (''isEmpty'' ''includes:''))
            (''Copying'' (''copyWith:'' ''copyFrom:to:'' ''reverse''))
            (''Converting'' (''joinedStringFrom:to:''))))
        (''BlockClosure'' (
            (''Evaluation'' (''value'' ''value:'' ''value:value:'' ''argumentCount'' ''valueWithArguments:''))
            (''Exception Handling'' (''on:do:''))
            (''Termination'' (''ensure:'' ''ifCurtailed:''))
            (''Looping'' (''whileTrue'' ''whileFalse'' ''whileTrue:'' ''whileFalse:''))))
        (''FailedMessage'' ((''Accessing'' (''selector'' ''arguments''))))
        (''Exception'' (
            (''Exception Description'' (''messageText'' ''messageText:'' ''tag'' ''tag:'' ''description'' ''isResumable''))
            (''Signaling'' (''signal'' ''signal:'' ''defaultAction'' ''_signalException'' ''_failUnhandledException''))))
        (''Transcript'' (
            (''Writing'' (''show:'' ''cr''))
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
            (''Initialization'' (''initialize'' ''shippedProtocols''))
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
            (''Number Tests'' (''testLargeIntegerArithmetic'' ''testLargeIntegerFloorDivision'' ''testExactFractions''
                ''testScaledDecimalLiterals'' ''testScaledDecimalExactArithmetic'' ''testScaledDecimalDivision''
                ''testScaledDecimalMixedNumericTypes'' ''testScaledDecimalConversions'' ''testScaledDecimalWithWideCoefficient''))
            (''Collection Tests'' (''testArrayFactoriesAndIndexedCopy'' ''testLargeArrayIsOneBasedAndInitiallyNil''))
            (''Exception Tests'' (''testExceptionNormalCompletion'' ''testExceptionSignalersAndMetadata''
                ''testExceptionSelectsNearestMatchingHandler'' ''testExceptionFromAnActionUsesTheOuterEnvironment''
                ''testExceptionHandlerRunsBeforeUnwindBlocks'' ''testExceptionActionCanReturnFromItsHomeMethod''
                ''testExceptionSelectorUsesHandles'' ''testExceptionDefaultAction''))
            (''Test Support'' (''returnThroughCleanup:'' ''returnThroughException:''))))
    )'.
