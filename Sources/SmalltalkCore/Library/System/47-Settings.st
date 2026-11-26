"The application Settings window is rendered by the native snapshot host."

UIWindow subclass: #SettingsWindow instanceVariableNames: 'identifier'.

SettingsWindow compile: 'initialize
    super initialize.
    identifier := ''settingsWindow''.
    self title: ''Settings'';
        minimumWidth: 420 height: 96;
        resizeWidth: 460 height: 112;
        content: self buildContent'.

SettingsWindow compile: 'buildContent
    ^ UIColumn new padding: 24;
        add: (UILabel new identifier: ''settingsImageNote'';
            text: ''Windows and session state are stored in the Smalltalk image.''; yourself);
        yourself'.
