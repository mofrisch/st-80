"Shipped method organization, including the VM primitives exposed by the browser."

BrowserOrganization compile: 'shippedProtocols
    ^ #(
        (''Object'' (
            (''Initialization'' (''initialize''))
            (''Comparing'' (''='' ''=='' ''~=''))
            (''Nil Testing'' (''isNil'' ''notNil'' ''ifNil:'' ''ifNotNil:''))
            (''Reflection'' (''class'' ''respondsTo:'' ''perform:'' ''perform:with:''))
            (''Printing'' (''printString''))
            (''Identity'' (''yourself''))
            (''Error Reporting'' (''error:line:column:''))))
        (''Class'' (
            (''Instance Creation'' (''new'' ''new:''))
            (''Class Structure'' (''name'' ''superclass'' ''subclasses'' ''instanceVariableNamesText''))
            (''Subclass Definition'' (''subclass:instanceVariableNames:'' ''subclass:instanceVariableNames:classVariableNames:poolDictionaries:category:''))
            (''Method Dictionary'' (''compile:'' ''compileClass:'' ''methodNames'' ''methodSourceAt:'' ''classMethodNames'' ''classMethodSourceAt:'' ''isPrimitiveAt:''))))
        (''Integer'' (
            (''Arithmetic'' (''+'' ''-'' ''*'' ''/'' ''//'' ''\\'' ''negated'' ''abs'' ''squared''))
            (''Comparing'' (''<'' ''>'' ''<='' ''>=''))
            (''Bounds'' (''min:'' ''max:'' ''clampFrom:to:''))
            (''Iteration'' (''timesRepeat:'' ''to:do:'' ''to:by:do:''))))
        (''Boolean'' (
            (''Logical Operations'' (''not'' ''and:'' ''or:''))
            (''Conditionals'' (''ifTrue:'' ''ifFalse:'' ''ifTrue:ifFalse:'' ''ifFalse:ifTrue:''))))
        (''String'' (
            (''Accessing'' (''size'' ''at:'' ''characters''))
            (''Combining'' ('',''))
            (''Searching'' (''includes:''))
            (''Character Testing'' (''isLetter'' ''isNumber'' ''isASCIIDigit'' ''isLowercase'' ''isWhitespace'' ''isLineBreak''))
            (''Converting'' (''asString'' ''asSymbol'' ''asIntegerOrNil''))))
        (''Symbol'' (
            (''Converting'' (''asString''))))
        (''Array'' (
            (''Accessing'' (''size'' ''at:''))
            (''Updating'' (''at:put:''))
            (''Enumerating'' (''do:'' ''collect:'' ''select:''))
            (''Testing'' (''isEmpty'' ''includes:''))
            (''Copying'' (''copyWith:''))
            (''Converting'' (''joinedStringFrom:to:''))))
        (''BlockClosure'' (
            (''Evaluation'' (''value'' ''value:'' ''value:value:''))
            (''Looping'' (''whileTrue:'' ''whileFalse:''))))
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
            (''Literal Scanning'' (''readNumber'' ''readString'' ''readSymbol''))
            (''Identifier Scanning'' (''readIdentifier'' ''readWord''))
            (''Error Reporting'' (''fail:''))))
        (''STSourceScanner'' ((''Highlighting'' (''nextHighlight'' ''token:value:'' ''highlight:'' ''fail:''))))
        (''STCompiler'' (
            (''Compilation'' (''initialize'' ''start:'' ''workspace:'' ''method:''))
            (''Token Handling'' (''advance'' ''expect:'' ''kind'' ''tokenValue'' ''tokenLabel:'' ''identifier''))
            (''Body Parsing'' (''workspaceBody'' ''bodyUntil:'' ''blockAt:''))
            (''Expression Parsing'' (''expression'' ''expressionNode'' ''primary'' ''unaryExpression'' ''binaryExpression'' ''keywordExpression''))
            (''Message Parsing'' (''unaryMessage'' ''binaryMessage'' ''keywordMessage'' ''cascadeMessage''))
            (''Literal Parsing'' (''arrayElement'' ''arrayElements'' ''negativeNumber''))
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
            (''Connection Lifecycle'' (''connect'' ''disconnect''))
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
                ''openBrowser'' ''openTranscript'' ''openChanges'' ''openWindow''))
            (''Window Lifecycle'' (''open:'' ''requestClose:'' ''close:'' ''minimize:''))
            (''Focus and Ordering'' (''chooseActive'' ''bringToFront:'' ''activate:'' ''observeActivation:'' ''observeMinimized:value:''))
            (''Displays and Placement'' (''screens'' ''screenFor:'' ''screensChanged:'' ''constrain:'' ''restoreWindows'' ''arrangeTools''))))
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
            (''Labeling'' (''title'' ''title:'' ''shortcutHint:''))
            (''Action Configuration'' (''action:'' ''command:'' ''onClickSend:to:'' ''selectionFrom:action:''))
            (''Activation'' (''click'' ''clickWithSelection:''))))
        (''UITextField'' (
            (''Initialization'' (''initialize''))
            (''Label and Placeholder'' (''label'' ''label:'' ''placeholder'' ''placeholder:''))
            (''Text'' (''text'' ''text:''))
            (''Input Handling'' (''editText:'' ''onChangeSend:to:''))))
        (''UICodeEditor'' (
            (''Initialization'' (''initialize''))
            (''Editing Permissions'' (''readOnly:''))
            (''Context Menu'' (''contextMenu'' ''contextMenu:''))))
        (''UIList'' (
            (''Initialization'' (''initialize''))
            (''List Contents'' (''items:''))
            (''Selection'' (''selection:'' ''select:'' ''onSelectSend:to:''))))
        (''UIContainer'' (
            (''Initialization'' (''initialize''))
            (''Child Management'' (''children'' ''children:'' ''add:'' ''remove:'' ''removeAll''))
            (''Layout Spacing'' (''spacing'' ''spacing:'' ''padding'' ''padding:''))))
        (''UIWindow'' (
            (''Initialization'' (''initialize''))
            (''Window Content'' (''content'' ''content:''))))
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
        (''DevelopmentWindow'' (
            (''Shared Layout'' (''heading:'' ''caption:'' ''resultPane'' ''toggleResult'' ''resultExpanded:''))
            (''Result Display'' (''result:''))))
        (''WorkspaceWindow'' (
            (''Initialization'' (''initialize''))
            (''Code Evaluation'' (''text:'' ''sourceForSelection:'' ''doIt:'' ''printIt:'' ''inspect:'' ''debugIt:'' ''execute:printing:''))
            (''Editor Menu'' (''editorMenu'' ''actionsMenu'' ''selectionButton:command:action:''))
            (''Examples'' (''examplesMenu'' ''exampleButton:key:''))))
        (''BrowserWindow'' (
            (''Initialization'' (''initialize''))
            (''Pane Layout'' (''list:selecting:'' ''organizationItem:id:send:'' ''pane:list:action:'' ''withAll:''))
            (''Navigation'' (''chooseCategory:'' ''chooseClass:'' ''chooseProtocol:'' ''chooseMethod:''
                ''filter:'' ''matchesCategory:'' ''selectedClass'' ''protocolOf:in:''
                ''showInstanceMethods'' ''showClassMethods'' ''chooseMethodSide:''))
            (''Catalog Updates'' (''refreshClasses'' ''refreshMethods'' ''refreshTools'' ''refreshOrganizationActions''))
            (''Method Editing'' (''acceptMethod'' ''draftChanged:'' ''newMethod'' ''primitiveSelected''
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
    )'.
