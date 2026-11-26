# Smalltalk/80

A small native macOS system with a language inspired by Smalltalk-80. The native app and VM are written in Swift. The compiler and system library are written in Smalltalk.

## Run in Xcode

1. Open `Smalltalk80.xcodeproj`.
2. Select the **Smalltalk80** scheme and **My Mac** as the destination.
3. Press **⌘R**.

The project contains five targets.

| Target | Purpose |
| --- | --- |
| Smalltalk80 | Native macOS windows with SwiftUI content and an AppKit text editor |
| SmalltalkCore | Swift bytecode VM with object memory and the Smalltalk compiler |
| SmalltalkCoreTests | Language, image, and window model tests |
| Smalltalk80Tests | Native window presentation and editor draft tests |
| Smalltalk80UITests | Workspaces, live method editing, native windows, and image restoration after relaunch |

Local builds use ad hoc signing, so you can run the app without a development team. You need macOS 14 or later and Xcode with Swift 6.

## Usage

- In a **Workspace**, click **Do it** in the title bar or press **⌘D**. The evaluation commands use the selected code or the whole buffer when there is no selection.
- **Do it** has a budget of 100,000 VM steps. Use **Run with Budget** for a single run with 1,000,000 or 10,000,000 steps. **Stop** interrupts a running evaluation at the next VM check. Changes already made by the evaluation are kept.
- The ellipsis next to **Do it** and the editor's context menu offer **Print it** (**⌘P**), **Inspect it** (**⌘I**) and **Debug it** (**⌘⇧D**). **Print it** adds the result to the Transcript. **Inspect it** opens the value in the Object Inspector, and **Debug it** pauses at entry.
- The result row below the Workspace editor shows the latest result. Click **Result** or **Error** to expand it. Choose **Smalltalk → Clear Transcript** or use the Transcript's context menu to clear the output.
- The **System Browser** has four lists for class categories, classes, protocols, and methods. Switch between **Instance** and **Class** above the lists. Each side has its own protocols, methods, and editor draft. Start with **New Method**, and use **Accept** or **⌘S** to compile a changed method. Its history is under **Method Actions → Versions**.
  If the selected method changed elsewhere while you were editing, Accept keeps your draft and reports the conflict. Reopen the method to work from its current version.
- The Workspace and method editors show line numbers and highlight Smalltalk syntax. The image’s `STSourceScanner` shares the compiler’s lexical rules and tolerates unfinished input. It supplies text ranges to the native editor.
- With a method selected, click **Bytecode** below the source editor to expand a read-only listing of the compiled method, including the instructions inside blocks. The listing updates when you accept a source edit. The browser identifies VM primitives that have no bytecode.
- Selecting a class shows its definition in the source editor. **Definition** returns to it from a method. Edit the superclass or instance variable names in `subclass:instanceVariableNames:` and press **⌘S**. Use **Move Class …** to change the category.
- Create classes in the Workspace by evaluating `Object subclass: #Greeter instanceVariableNames: 'name'`. Use **New Method** in the browser to add a method. The browser shows the selected class's own methods. Select its superclass to browse inherited methods.
- Evaluate `ToolVM bindingSummary` in a Workspace to list shared variables with their classes and values.
- **Tools → Workspace** (**⌘W**) opens a new editor containing `Transcript show: 'Hello'; cr.`. Click **Do it** to run the example. **Tools → Browser** (**⌘B**) opens a new browser. **Tools → Transcript** (**⌘T**) opens the output window or brings the existing one forward. Use the macOS **Window** menu to switch between open windows and **File → Close** (**⇧⌘W**) to close the active window.
- With a Workspace open, **Smalltalk → Examples** opens sample code for counters, arrays and blocks, class definitions, native windows, and custom interfaces. Edit the sources and menu entries on the class side of `WorkspaceExamples` in the **Examples** category.

The Object Inspector shows a value's class, instance variables, and one-based array elements. Open a row to follow its value, use **Back** to return, and use **Refresh** after another workspace changes the object. Long arrays are shown one page at a time. Smalltalk code can also open the window with `ToolVM inspect: anObject`.

An open inspector keeps its current value and navigation history reachable for garbage collection. `ObjectInspectorWindow` defines the title, dimensions, and control actions in `42-Inspector.st`. The shared native backend hosts the window. `InspectorPresentation` builds its controls, and `InspectorModel` manages the path, follows references, and pages through members. Loading an image or resetting the session closes the inspectors.

**Smalltalk/80 → Settings…** (**⌘,**) opens `SettingsWindow` from the image in a native window. Older images use the bundled Smalltalk definition.

The debugger pauses at entry. `DebuggerWindow` defines its title, dimensions, frame selection, command policy, and recovery view in the image. `DebuggerPresentation` builds the controls from immutable stack snapshots on a separate interpreter thread. The shared native window backend hosts the window. **Stop** and closing the window use a direct command channel to end the evaluation and keep effects already performed. Select a stack frame to see its source, current instruction, receiver, and variables. **Step Into** follows calls, **Step Over** runs to the next location in the current frame or its caller, and **Step Out** returns to the caller. **Continue** runs until completion or a runtime error. An error shows the failing stack.

## Save and load images

The app starts from the bundled image with an empty desktop on every launch. Open a saved image with **⌘⇧O — Open Image …**.

- **⌘⇧S — Save Image** saves the running session as a `.stimage` file. The first save opens the native file dialog. Subsequent saves replace the same file atomically.
- **⌘⌥⇧S — Save Image As …** saves to another image file.
- When you quit with unsaved changes, choose **Save**, **Don’t Save**, or **Cancel**. The app stays open if you cancel the save or if saving fails.
- Opening another image or resetting the session uses the same choice. A cancelled or failed save leaves the current session available. Reset also keeps the current session if its new changes log cannot be created.
- Accept browser edits with **⌘S** before saving an image. The image stores accepted methods.

An image preserves classes and their hierarchy, accepted methods (including changes to built-in classes), workspace variables, instance variables, arrays, and saved blocks with their lexical contexts. It preserves shared references and cyclic object graphs. It also saves all workspace buffers, open windows with their size, position, order, and minimized state, and the Transcript. Unreachable objects are omitted.

The VM builds and validates a separate session before replacing the active one. It validates the saved method structure and source references. Loading performs no compilation or Smalltalk execution and leaves completed block return contexts closed. If an image is invalid or incompatible, the active session remains available.

**Reset Session** starts a fresh session with an empty desktop.

The JSON image format (`format: st80-image`, `version: 6`) stores an object table, bytecode for methods and blocks, source positions, and source references. Use a fresh session when upgrading from an earlier image version. The core API `imageData` produces a portable image with embedded method sources. Each image can contain up to 32 MiB and 40,000 reachable reference objects.

### Sources and changes

Saving produces three related files.

| File | Contents |
|---|---|
| `MyWorld.stimage` | Object graph, classes, executable methods, and the last saved changes checkpoint |
| `Smalltalk80-<sources-id>.sources` | Immutable source archive for the base system, shareable by multiple images |
| `MyWorld.changes` | Append-only log of accepted class and method definitions, including earlier versions |

The original Smalltalk sources live under `Sources/SmalltalkCore/Library`. Xcode and Swift Package Manager bundle the generated `Smalltalk80.sources` with the executable `Kernel.seed.json`. On a cold start, the VM installs the precompiled methods and the Smalltalk compiler compiles `InitialWorld.st`.

Accepting code writes and syncs the changes entry before installing the method in the live image. This also applies to `SomeClass compile:` and `SomeClass compileClass:` in a workspace. A write failure prevents installation. Before the first image save, the log lives in `~/Library/Application Support/Smalltalk80/Changes/`. The Code Changes window shows its path. **Smalltalk → Open Changes File …** can import a log for review even if its session never saved an image. The import checks the size and entry limits before appending the entries in one write, then rolls back the write if it fails.

**Smalltalk → Code Changes …** opens the history. The `ChangesBrowser` window holds its controls, filters, and selection in the image’s object graph and asks the VM to retrieve or restore journal entries. **Versions …** in the browser opens this window directly and filters the history to the selected method, including its shipped baseline from the sources archive. **Restore Version** compiles the selected source and logs the restoration as a new change. Entries after the saved image checkpoint are marked and are never replayed automatically on load. To restore a new class, restore its definition before its methods. The log records accepted code changes. Arbitrary object mutations and unaccepted editor contents belong to the live session.

An open Code Changes window retains its last view state in the image. Loading and snapshots display that state without executing Smalltalk; the next evaluation or tool action refreshes it from the journal. Older images without this cached view build it on the next evaluation or when Code Changes is opened again.

Keep the image, its matching `.changes` file, and its referenced sources archive together when copying them. Avoid editing the companion files in a text editor. Missing, corrupt, or mismatched companion files leave the active session intact. After a crash, the loader ignores a truncated final log record. The next append removes it. A corrupt complete record is reported as an error. A changes log can contain up to 64 MiB and 100,000 records. The window shows the latest 2,000.

**Save Image As …** branches the existing history into a separate changes file. The app preserves any existing log that belongs to another image. It writes the companion files before replacing the image atomically, so a failed save leaves the previous image and its source references usable.
If the image write fails, the save removes its newly created, unchanged changes file so you can retry the same name. A changes-log failure remains visible until durable logging is available again.

## Smalltalk compiler and boot image

`Library/Bootstrap` contains the compiler, scanner, and compiler list. The same compiler handles **Do it**, browser **Accept**, `Class>>compile:`, and `Class>>compileClass:`. It builds syntax trees in temporary object memory. Swift validates the trees and lowers them to stack instructions. The VM executes those instructions with the same message lookup, primitives, and lexical scopes for workspace code, methods, and blocks. Each instruction carries a source position for runtime errors. Image loading validates bytecode operands, stack shape, and block scopes before installing the restored world.

Integer literals accept radices from 2 to 36. Floating-point literals and all three exponent markers (`e`, `d`, `q`) use IEEE 754 binary64. Character literals such as `$A` and elements accessed with `String>>at:` are Unicode scalar values. Each scalar occupies one index in a string.

After changing a numbered system source file, rebuild both bundled artifacts from the project directory.

```sh
python3 scripts/generate-sources.py
```

The bootstrap loads the previous compiler from the boot image and rebuilds `Library/Bootstrap` before reading `Library/System`. The rebuilt compiler then compiles the system library, including the core extensions, desktop, tools, syntax highlighter, examples, and tests. The bootstrap checks both stages for reproducibility and packages them into the same boot image. Use `--check` to verify the existing artifacts. Opening a saved image loads the compiler stored in that image.

## Garbage collection

Each runtime has an `ObjectMemory` with a precise, nonmoving mark-and-sweep collector. It manages objects, arrays, blocks, and lexical environments. Roots include globals, the bytecode operand stack, active receivers and environments, and explicit temporary roots held by Swift code. The collector follows object fields, array elements, and block/environment captures. It first detaches every unreachable node's references, then releases the nodes through Swift ARC, including cyclic graphs. Object identity and native window identifiers remain stable.

Collection runs on the interpreter worker at allocation safepoints and, when due, after a completed worker operation. Smalltalk execution pauses during collection. The native UI renders immutable snapshots. Classes, bytecode instructions, and strings remain outside the managed node graph.

The normal heap starts collecting at 4,096 registered nodes. After collection, the threshold becomes the greater of that starting threshold and twice the surviving node count, up to a hard limit of 100,000 nodes. Reaching the hard limit first triggers collection; an allocation fails only if the heap still has no room. The separate temporary compiler runtime uses a starting threshold of 32,768 and a hard limit of 1,000,000 nodes. All four managed node kinds count toward these budgets.

To request a full collection in a Workspace, evaluate:

```smalltalk
ToolVM collectGarbage
```

The result is the number of nodes reclaimed by that collection. `ToolVM gcStatistics` returns an array of alternating symbols and integers: `#nodes`, `#objects`, `#arrays`, `#blocks`, `#environments`, `#slots`, `#collections`, `#reclaimed`, and `#lastPauseNanoseconds`. The node counts report registered heap occupancy when sampled; between collections they can include unreachable nodes. Slots count logical value/reference slots, not bytes or process resident memory. The Swift session API provides `collectGarbage()` and `garbageCollectionStatistics()` returning `GCStatistics`.

Images contain the reachable object graph. Loading suspends collection while the new graph is allocated and connected, while retaining the hard allocation limit.

## Native window management

The Workspace, System Browser, and Transcript are separate macOS windows. You can open multiple Workspaces and Browsers, up to 128 windows on the Smalltalk desktop. Use the standard title bars to move, resize, minimize, and close them. Workspaces share one Smalltalk session and each keeps its own text, selection, and last result. Browsers have their own navigation and editor state while sharing the system catalog. The Transcript is blank until it receives output. Its buffer also receives output while the window is closed.

The bundled desktop places new tools slightly offset from the frontmost visible window of the same kind. Saved images restore their own windows and positions. **Smalltalk → Arrange Tools** arranges the backmost Browser, Workspace, and Transcript into two columns when all three kinds are open. The group occupies at most 1800 × 1000 screen points. This command installs the arrangement method in an older image if it is missing. The **Tools** menu updates earlier stock tool methods on first use and records the updates in the changes log. An image's customized methods still apply.

Smalltalk implements window management. The global `Desktop` holds the `DesktopManager` controller. Its `DesktopModel` tracks the window list, order, active window, and display information. `SystemWindow` is a subclass of `Model` that reports state changes through the standard observer protocol.

When an operation marks the catalog as changed, the VM sends `catalogChanged` to `Desktop` at the end of the operation with a separate step budget. The manager chooses which tools to refresh. The stock hook's budget accounts for the number of open windows. Snapshots and image loading read the resulting state without running this hook.

`Library/20-Windows.st` implements opening, closing, activation, minimization, size limits, placement, display selection, and restoration. You can edit these methods in the browser. The display with the largest overlap wins, with distance breaking ties. When a monitor is disconnected, windows are constrained to the remaining visible display areas. Logical minimum sizes are preserved even if a small display temporarily requires smaller native limits.

`NativeWindowBackend` manages the individual AppKit windows, reports available display areas and native events, and displays SwiftUI content. Smalltalk owns the size and placement rules. A native close attempt asks `canClose`. Moves, resizes, and focus changes report events that have already occurred. The backend acknowledges revisioned Smalltalk requests with the native geometry it applied. Session identifiers, event sequence numbers, and acknowledgements prevent stale events from overriding new requests or a newly loaded image. Native events are processed promptly while the editors stay usable.

```smalltalk
window := Desktop openWorkspace.
window title: 'My Workspace'.
window text: '6 * 7'.
window moveToX: 180 y: 240.
window resizeWidth: 700 height: 500
```

Other messages include `Desktop openBrowser`, `Desktop openTranscript`, `Desktop openChanges`, `Desktop windows`, `Desktop activeWindow`, `Desktop activate: window`, and `Desktop close: window`.

```smalltalk
window minimumWidth: 600 height: 400.
window maximumWidth: 1200 height: 900.

"A custom window can veto a close request."
UIWindow subclass: #ProtectedWindow instanceVariableNames: ''.
ProtectedWindow compile: 'canClose ^ false'.
ProtectedWindow new open
```

See `Examples/WindowPolicy.st` for a complete example of a close veto.

A custom `DesktopManager` subclass can override `screenFor:`, `constrain:`, `requestClose:`, or `createKind:title:`, for example. The base classes and their model are ordinary Smalltalk objects stored in the image.

In the bundled desktop, `openWorkspace` and `openBrowser` create windows, and `openTranscript` reuses the existing transcript when one is open. Coordinates use macOS screen points with the origin at the bottom left. On load, windows are adjusted to the available displays.

The app sends window text to the Smalltalk objects before an evaluation or image save. The saved object graph includes the Transcript and the browser selection.

If the live window model or a control tree becomes invalid, the app keeps the last valid native tools and their editor drafts visible. A retained Workspace can still run **Do it**, **Print it**, and **Inspect it** to repair the image. Normal controls resume after a valid projection is restored.

## Tools in Smalltalk

`40-Tools.st` defines `WorkspaceWindow`, `BrowserWindow`, and `TranscriptWindow`. You can edit those classes in the browser and subclass them to create new windows. `DesktopManager>>windowClassFor:` chooses the class to instantiate when opening a tool.

Smalltalk workspace actions use the native text selection when present and the whole buffer otherwise. The browser manages filters, selection, drafts, class definition edits, and method acceptance in Smalltalk. It reads VM reflection through `ToolVM` and `Class`. `Transcript show:`, `cr`, and `clear` update the observable `TranscriptBuffer` model, which retains the last 64 KiB of output.

The **⋯** menus in **Class Categories** and **Protocols** let you create and rename groups and move the selected class or method. Select an existing group before choosing **Rename Category …** or **Rename Protocol …**. Use **Move Class …** or **Move Method …** to choose a destination. The browser files new classes and methods into the current category or protocol when one is selected. A method with no assignment appears under **Unclassified**.

`BrowserOrganization class>>shippedClassCategories` defines the class groups in the startup image. The Browser lists the compiler, source editor, desktop, MVC, debugging, and recovery classes in dedicated groups. New classes without an explicit category appear under **User Classes**.

Protocols are specific to each class. The shipped system groups methods by purpose in `41-SystemProtocols.st`. For example, `Integer` has **Arithmetic** and **Bounds**, and `Model` has **Managing Dependents** and **Change Notifications**. `SystemOrganization` holds protocol names and assignments in Smalltalk. Saving the image preserves them even if the browser is closed.

Accepting a revised class definition updates existing instances of the class and its subclasses. Fields with matching names retain their values. New fields start as `nil`. The editor rejects cycles and conflicting fields. Fields cannot be removed while they hold values or are referenced by installed methods, running code, or retained blocks. A superclass change is rejected if it would detach a retained class-side block or running class method from its defining class. The selected class name identifies the definition being edited. Built-in VM class layouts are read-only. Accepted definitions appear in **Code Changes**, and saving an image preserves the new layout.

The Browser, Workspace, and Transcript use the same SwiftUI control renderer as custom windows. Their Smalltalk descriptions place controls, set their visibility, and handle disclosure buttons and menus. A direct child of the content with role `#windowToolbar` mounts in the native title bar. The Workspace supplies its Examples submenu with role `#applicationMenu`. A menu with role `#applicationCommands` in the active window supplies commands for the Smalltalk menu.

`ApplicationMenu` in `49-ApplicationMenu.st` defines the app's menu groups, the two app-specific menus, and their keyboard shortcuts. Menu buttons use `shortcutHint:` with chords such as `⇧⌘D`. Focused tool commands can supply their own chord or use the defaults in `workspaceShortcuts`. The bundled Smalltalk recovery commands supply both the menu entries and the evaluation, printing, and inspection policy for a damaged desktop. Swift mounts the menus and dispatches the native actions, including file dialogs.

`UICodeEditor` configures line numbers, syntax highlighting, undo, and the order and labels of standard editing actions. The `#source` role enables line numbers and highlighting by default. `UIValueTable` defines its headings, column widths, spacing, and value line limit. The native renderer supplies TextKit and renders table rows as they come into view.

## Interfaces with MVC

Choose **Smalltalk → Examples → Custom Interface** for a complete MVC example. The source is also available in `Examples/GreetingWindow.st`.

| Role | Responsibility in the example |
| --- | --- |
| `GreetingModel`, a subclass of `Model` | Holds `name`, computes `greeting`, and notifies observers. It is independent of UI classes. |
| `GreetingView`, a subclass of `UIWindow` | Defines the layout, controls, and bindings. It forwards input to the controller. |
| `GreetingController`, a subclass of `Controller` | Handles input and button actions by updating the model. Bindings update the labels and fields. |

After running the example, evaluate this in the workspace.

```smalltalk
greetingModel name: 'Ada'
```

The input field and greeting update automatically. A second view can observe the same model.

```smalltalk
secondView := GreetingView new.
secondView moveToX: 650 y: 200.
secondView model: greetingModel controller: greetingController; open
```

Model changes appear in both windows as you type, without pressing Return or clicking a button.

### Change notifications and bindings

A domain model inherits from `Model`. Its setters use `self changed` to announce changes to all aspects or `self changed: #name` for a single aspect. The example specifies the setter below.

```smalltalk
name: aString
    name := aString.
    self changed
```

The view binds properties to model getters and routes input to the controller.

```smalltalk
input bind: #text to: greetingModel aspect: #name.
input onChangeSend: #nameChanged: to: greetingController.
output bind: #text to: greetingModel aspect: #greeting.
button onClickSend: #clear to: greetingController
```

The controller's `nameChanged:` method sends `model name: aString`. The model notifies its observers, then the bindings read the affected getters and set the view properties. For computed values such as `greeting`, the example uses `changed` to notify observers about all aspects.

`Model` also provides `addDependent:`, `removeDependent:`, and `dependents`. Custom observers implement `update:`, which receives the changed aspect or `nil` for all aspects. Registering the same observer again does not duplicate notifications.

You can bind `text` on labels and text fields, `title` on buttons, `enabled` and `visible` on all UI elements, and `spacing` and `padding` on layouts. Use `unbind: #text` to remove one binding or `unbindAll` to clear a view's bindings. Rebinding a property replaces the previous binding. At the end of an evaluation or native event, bindings on removed controls and closed windows disconnect. Reopening reconnects them with the current model values.

The VM reads the window and control fields to detect attachment changes, then sends `reconcileMount:` to the affected `UIBinding` objects. The image can edit this method to customize the lifecycle. Images must provide `UIBinding>>reconcileMount:` to load. Loading validates the stored bindings without calling any of these methods.

### Controls and rendering

| Class | Messages |
| --- | --- |
| `UIWindow` | `title:`, `content:`, `open`, `moveToX:y:`, `resizeWidth:height:` |
| `UILabel` | `text:`, `text` |
| `UIButton` | `title:`, `action:`, `onClickSend:to:`, `selectionFrom:action:` for actions that use the code editor selection |
| `UITextField` | `label:`, `placeholder:`, `text:`, `text`, `onChangeSend:to:` |
| `UICodeEditor` | Text field messages, plus `readOnly:`, native text selection, and `contextMenu:` to attach a `UIMenu` of buttons and dividers |
| `UIList` | `items:` with unique strings, `selection:`, `onSelectSend:to:` |
| `UISplit`, `UIVerticalSplit`, `UIScroll`, `UIMenu` | Containers for split views, scrolling, and menus. `UISplit` stacks its panes with `role: #vertical`. `UIVerticalSplit` stacks resizable panes and applies their height limits to the divider. `UIMenu` also supports `title:`. `UIScroll` accepts `contextMenu:` for a menu of buttons and dividers. |
| `UIDivider` | Separator |
| `UIColumn`, `UIRow` | `add:`, `remove:`, `removeAll`, `children:`, `spacing:`, `padding:` |
| `UISpacer` | Flexible space in a row or column |
| All UI elements | `enabled:`, `visible:`, `identifier:`, `role:`, `widthFrom:to:`, `heightFrom:to:`, `bind:to:aspect:`, `unbind:`, `unbindAll` |

You can nest rows and columns. `add:` returns the added element. `spacing:` accepts 0 to 128 points and `padding:` accepts 0 to 256. An interface is a tree of at most 512 elements and 16 nesting levels. Each element can appear only once in a window. A disabled layout also disables its children.

Smalltalk objects stay on the interpreter thread. `SmalltalkCore` projects immutable snapshots and runs the Smalltalk tool operations. `Smalltalk80` renders the snapshots and keeps native window state, unsent edits, selections, and file associations. `AppController` forwards native events and publishes the resulting snapshots. Smalltalk handles change notifications directly without polling.

`ToolWindowFeedback` in `48-ToolWindowFeedback.st` builds the error and repair views on a separate interpreter thread using the bundled Smalltalk definition. This allows a retained Workspace to show feedback while the active image's desktop or control tree is invalid.

Text fields with an input controller send changes after an 80 ms pause while keeping the field active. Before button actions, workspace evaluations, and image saves, the app flushes pending input in order. Model-driven changes do not generate more input events. If a model or controller method fails, the workspace and browser remain available for repair. Once repaired, the app retries pending input.

### Images

Images preserve domain models, controllers, views, bindings, and observer relationships. Model updates and input work after loading. The image stores the last valid view state so loading can display it without calling `initialize` or bound getters.

## Try it

```smalltalk
counter := Counter new.
5 timesRepeat: [ counter increment ].
counter value
```

The result is `5`. In the browser, change `Counter » value` to the following and accept it.

```smalltalk
value
    ^ count + 100
```

Back in the workspace, select just `counter value` and evaluate it. The existing object now answers `105`.

You can also create classes by sending messages.

```smalltalk
Object subclass: #Greeter instanceVariableNames: 'name'.
Greeter compile: 'name: aString
    name := aString'.
Greeter compile: 'greeting
    ^ ''Hello, '', name'.

greeter := Greeter new.
greeter name: 'Moritz'.
greeter greeting
```

## Language support

The language supports arbitrary-precision integers, exact fractions, binary64 floating-point numbers, characters, strings, symbols, arrays, `nil`, booleans, assignments, local variables, unary, binary, and keyword messages, cascades, lexical blocks, non-local returns with `^`, classes, instance variables, single inheritance, and `super`.

Unary messages bind before binary messages, and binary messages before keyword messages. Binary messages are evaluated left to right, so `3 + 4 * 2` evaluates to `14`. The language follows Goldberg and Robson's [Smalltalk-80: The Language and Its Implementation](https://rmod-files.lille.inria.fr/FreeBooks/BlueBookHughes/BlueBookImplementationTOC.html).

The prototype has these limits.

- The interpreter uses this project's stack instruction set. Images are specific to this VM.
- Classes share a simplified `Class` and have separate method dictionaries for the instance and class sides. Class methods inherit along the superclass chain. In a class method, `self` is the receiving class and `super` starts lookup above the defining class. The simplified model has no individual metaclass objects or class instance variables.
- `subclass:instanceVariableNames:` is the short form. The longer Smalltalk-80 message is accepted with empty class variables and pool dictionaries.
- `new` sends `initialize`. With no explicit `^`, a method returns `self` and a block returns its last expression.
- Assigning an undeclared name in a workspace creates a persistent workspace variable. `| temp |` declares a local that lasts for the evaluation.
- Integer and fraction arithmetic remains exact until it mixes with a floating-point operand. The VM uses [attaswift/BigInt](https://github.com/attaswift/BigInt) for large integers and charges the execution budget before expensive library calls. Scaled decimals are still missing.
- Strings are Unicode values and `==` compares them by value.
- Value previews and `printString` produce at most 64 KiB and visit at most 4,096 values, ending with `…` when truncated. Binding previews share a 64 KiB budget per snapshot and use at most 4 KiB per binding.
- Object memory uses the collector described above. The system does not yet include Smalltalk processes or BitBlt.
- The default evaluation budget is 100,000 execution steps, including bytecode instructions and call entry. The VM allows 128 call levels and 32 syntactic nesting levels. The normal heap permits up to 100,000 registered nodes after collection, and arrays can hold 65,535 elements. A class can have 127 named instance variables including inherited fields and can define 1,000 methods per side. Changes already performed survive an evaluation error.

## App icon

The app icon combines overlapping windows with a message bubble. The original transparent artwork is in `Design/AppIcon.png` and the ImageGen prompts are in `Design/AppIcon-prompt.txt`.

The Xcode target uses `Assets.xcassets/AppIcon.appiconset` with all ten macOS sizes from 16 to 1024 pixels. Regenerate the renditions with macOS system tools.

```sh
python3 scripts/prepare-app-icon.py Design/AppIcon.png
```

The project generator preserves the asset catalog and app icon settings for Debug and Release.

## Smalltalk tests

Run `TestRunner runAll summary` in a fresh Workspace to run all bundled tests. `ANSISmalltalkTest run summary` runs 17 tests for supported behavior from the ANSI Smalltalk draft, including literals, exact arithmetic, message dispatch, blocks, and arrays. You can browse their source under **Tests** in the System Browser.

Define a subclass of `TestCase` in the Workspace or Browser. Its own parameterless instance methods named `testSomething` run in alphabetical order. Each method runs on a fresh instance. Override `setUp` and `tearDown` for fixtures.

```smalltalk
TestCase subclass: #MyCounterTest instanceVariableNames: 'counter'.
MyCounterTest compile: 'setUp
    counter := Counter new'.
MyCounterTest compile: 'testIncrement
    counter increment.
    self assert: counter value equals: 1'.
MyCounterTest run summary
```

Use `(MyCounterTest run: #testIncrement) summary` to run one method, or `TestRunner runAll summary` for every test class. The available assertions are `assert:`, `deny:`, `assert:equals:` and `fail:`. `TestResult>>outcomes` lists the individual results. Each outcome has a `status` of `#passed`, `#failure` or `#error`. Its `diagnostics` are arrays of phase, status, message, line and column. Unavailable positions are `nil`.

Workspace runs use the live image. The automated suite uses the same bundled test classes in a fresh boot image and checks their result in both SwiftPM and Xcode. `swift test --filter SmalltalkTestFrameworkTests` runs the Smalltalk suite and the runner's regression tests.

## Build and test

```sh
xcodebuild -project Smalltalk80.xcodeproj -scheme Smalltalk80 \
  -destination 'platform=macOS' -derivedDataPath .build/xcode build

xcodebuild -project Smalltalk80.xcodeproj -scheme Smalltalk80 \
  -destination 'platform=macOS' -derivedDataPath .build/xcode \
  -only-testing:SmalltalkCoreTests -only-testing:Smalltalk80Tests test

xcodebuild -project Smalltalk80.xcodeproj -scheme Smalltalk80 \
  -destination 'platform=macOS' -derivedDataPath .build/xcode \
  -only-testing:Smalltalk80UITests test
```

You can also run the unit tests with `swift test`. The checked-in Xcode project is ready to open and build. After adding source files, use `python3 scripts/generate-project.py` to recreate it. Regeneration replaces manual project edits.
