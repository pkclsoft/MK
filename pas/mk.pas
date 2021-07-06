{$ keep 'mk' }
{$ memorymodel 1   }
Program make(makefile,output,erroroutput);
{ Program description: 
 
    This program reads a makefile description, and works out which targets
    are out of date. It passes the commands required to bring these up to
    date to a  subprocess.
 
    AUTHOR: Peter C. Easdown }

uses Common, ControlMgr, MscToolSet, IntegerMath, ToolLocator, MenuMgr,
     GSOS, ORCAShell;

{$ libprefix 'int/' }

uses EZConst, EZMisc, EZString, EZDates;

const
    maxchar                     = 255;

    commentChar                 = $21;    { start of comment marker - at start }
    lineContinueChar            = $2d;    { continued line character - at end }
    space                       = $20;    { space - separator }
    simpleCommandChar           = $3d;    { start of simple command sequence }
    compoundCommandChar         = $7b;    { start of compound command sequence }
    endCompoundCommandChar      = $7d;    { end of compount command sequence }
    continueChar                = $2d;    { line continuation char }
    tabChar                     = $09;    { tab character }

    noErrors                    = 0;

type
    { a command entry - may be in a chain }
    makeCommandPtr              = ^makeCommand;
    makeCommand                 = record
                                    action  : pString;
                                    actions : makeCommandPtr;
                                  end;    { makeCommand }

    fileName                    = pString;
    targetPtr                   = ^target;
    sourcePtr                   = ^source;
    sourceNodePtr               = ^sourceNode;
    fileNamePtr                 = ^fileNameEntry;
    fileTime                    = Longint;

    { an entry in the target tree }
    target                      = record
                                    left,right  : targetPtr;      { other targets - sorted structure }
                                    name        : fileName;       { name of this target }
                                    built       : boolean;        { if this target has been built }
                                    failed      : boolean;        { if this target failed build }
                                    builtTime   : fileTime;       { time/date stamp of this target }
                                    sources     : sourcePtr;      { chain of sources - nil if childless }
                                    actions     : makeCommandPtr; { command chain }
                                  end; { target }

    { an entry in a source list for a target }
    source                      = record
                                    node        : sourceNodePtr; { source node for this entry }
                                    others      : sourcePtr;     { other sources for parent target }
                                  end; { source }

    { an entry in the source tree }
    sourceNode                  = record
                                    left, right : sourceNodePtr; { links to others in source tree }
                                    name        : fileName;      { file name }
                                    targetId    : targetPtr;     { ptr to target if this source is a target }
                                    built       : boolean;       { if this source has been built }
                                    failed      : boolean;       { if this source failed build }
                                    builtTime   : fileTime;      { time stamp of this source }
                                  end; { sourceNode }

    fileNameEntry               = record
                                    name        : fileName;      { file name }
                                    next        : fileNamePtr;   { and the rest }
                                  end; { fileNameEntry }

var
    requestedTargets            : fileNamePtr;  { requested target chain }

    makefile                    : text;         { make instruction file }
    theCommandFile              : text;         { a  command file }
    commandFileName             : fileName;     { name of the  command file }
    commandFileOpen             : boolean;      { if we have opened the command file }
    pipeFileName                : fileName;
    pipeFileOpen                : boolean;

    targetTree                  : targetPtr;      { target list }
    sourceTree                  : sourceNodePtr;  { source tree }

    alwaysBuild                 : boolean;      { flag to always build }
    doCommands                  : boolean;      { flag to execute commands or not }
    debugTimes                  : boolean;      { flag to report times as we go }
    debugEverything             : boolean;      { flag to report times as we go }
    commandMake                 : boolean;      { flag to build a command file }
    listDepend                  : boolean;      { flag to list target dependencies }
    ignoreNonCompileErrors      : boolean;      { flag to ignore non compiler errors }
    pipeOutput                  : boolean;      { flag to send output to a file }

    programStatus               : integer;

Procedure outputSource(theSource: sourcePtr);
begin
  Write('  source:');
  WriteLn(theSource^.node^.name);
end;

Procedure outputAction(theAction: makeCommandPtr);
begin
    Write('  action: ');
    WriteLn(theAction^.action);
end;

Procedure outputTarget(theTarget: targetPtr);
var 
  theSource: sourcePtr;
  theAction: makeCommandPtr;
begin
    Write('target: ');
    WriteLn(theTarget^.name);
    
    theSource := theTarget^.sources;
    while (theSource <> nil) do
    begin
      outputSource(theSource);
      
      theSource := theSource^.others;
    end;
    
    theAction := theTarget^.actions;
    
    while (theAction <> nil) do
    begin
      outputAction(theAction);
      
      theAction := theAction^.actions;
    end;
end;

Procedure outputAll;
var
  theTarget : targetPtr;
begin
  theTarget := targetTree;
  
  while (theTarget <> nil) do
  begin
    outputTarget(theTarget);
    
    theTarget := theTarget^.right;
  end;
end;

Procedure CheckUserAbort;
var
  stopparms    : stopDCB;
begin
   stop(stopParms);

   If stopParms.stopFlag then
       Halt(0);
end;

Procedure SystemError(errorNumber : Integer);
begin
    programStatus := errorNumber;

    CheckUserAbort;
end;

function doCommand(var inString : pString) : integer;
{ Executes the command line given.
  Requests the status of the subprocess having done the command.
  Loops getting output from the subprocess, writing the output to output until
  it gets the status response, and then passes back the status to the caller. }
var
    Stat        : ReadVariableDCB;
    UnStat      : UnSetVariableDCB;
    SetStat     : SetDCB;
    commstr     : pString;
    errorNumber : integer;
    Comm        : ExecuteDCB;

begin   { doCommand }
    if debugTimes THEN BEGIN
        writeln('DO <', inString, '>');
    END;

    if doCommands then begin
        Comm.Flag := $8000;
        SetStat.VarName := @'Status';
        SetStat.Value := @'0';

        if pipeOutput then begin
          if pipeFileOpen then begin
            inString := concat(inString, ' >> ', pipeFileName);
          end else begin
            inString := concat(inString, ' > ', pipeFileName);
            pipeFileOpen := true;
          end;
        end;

        new(Comm.CommandString);
        Comm.CommandString^ := concat(copy(inString,1,length(inString)),chr(13),chr(0));
        Execute(Comm);
        dispose(Comm.CommandString);

        Stat.VarName := @'Status';
        new(Stat.Value);
        Stat.Value^ := '';
        Read_Variable(Stat);

        UnStat.name := @'Status';
        UnSetVariable(UnStat);

        doCommand := cnvsi(Stat.Value^);
    end else begin
        { asked to not execute commands }
        { see if we are supposed to be putting this out into theCommandFile }
        if commandMake then begin
            if not commandFileOpen then begin
                { file not open yet }
                { and open the command file }
                rewrite(theCommandFile, commandFileName);
                commandFileOpen := true;
            end;    { check on whether command file is open yet or not }

            writeln ( theCommandFile, inString );
        end;    { test for whether we are making command file }
        
        doCommand := 0;
    end;

    CheckUserAbort;
end;    { doCommand }

Procedure getFileTime(var testFile      : fileName;
                      var fileTime      : LongInt;
                      var noFile        : Boolean);
{ Determines the modify time and date of a file and returns is for easy
  comparison against other files. }
var
    getInfoParms    :   getFileInfoOSDCB;
    theName         :   GSOSInString;
    tempFileTime    :   TimeRecord;
    tempFileDate    :   DateRecord;
begin
    With getInfoParms do
    begin
        theName.theString := testFile;
        theName.size := length(testFile);

        pCount := 7;
        pathName := @theName;

        GetFileInfoGS(getInfoParms);

        If toolError <> 0 then begin
            noFile := True;
            writeln(errorOutput, '<mk> No file :', testFile);
        end else begin
            
            ConvFileDateToSeconds(modDateTime, fileTime);
            noFile := False;

            If debugTimes then begin
                ConvFileDateToDate(modDateTime, tempFileDate, tempFileTime);

                writeln(errorOutput, '<mk - dbg> file ', testFile, ' date/time ', 
                        tempFileDate.Date, ' / ',  tempFileTime.Time, ', seconds: ', fileTime);
            end;
        end;
   end;
end;    { getFileTime }

function currentTime : Longint;
{ Return the current time. }
var
    result : longint;
begin   { currentTime }
    result := GetSysDate;
    if debugEverything then
        writeln(errorOutput, 'currentTime: ', result);
    
    currentTime := result;
end;    { currentTime }

Function findTarget(    targetList : targetPtr;
                    var targetName : fileName ) : targetPtr;
{ Searches the targetList chain for an entry with this targetName.
  Returns pointer to the target entry found, or nil.
  NB targetList MUST NOT be a var parameter. }

var
    doneSearch : boolean;  { flag to indicate finished searching for target }

begin   { findTarget }
    { clear search flag }
    doneSearch := false;

    repeat
        if targetList = nil then begin
            { give up - ran out of options }
            doneSearch := true;
        end else begin
            with targetList^ do begin
                if targetName < name then begin
                    { left branching }
                    targetList := left;
                end else begin
                    if targetName > name then begin
                        { right branching }
                        targetList := right;
                    end else begin
                        { success - found it }
                        doneSearch := true;
                    end;    { test for right or current branch }
                end;    { test for left branch }
            end;        { with targetList }
        end;    { test for end of chain }
    until doneSearch;

    findTarget := targetList;
end; { findTarget }

procedure initializeVars;
{ set up some initial values }
var
    makefileName    : fileName;                 { name of the input file }
    callStatus      : longint;                  { return status from routine calls }
    requestPtr      : fileNamePtr;              { temp 4 adding requested targets }
    done            : boolean;                  { flag for loop completion }
    debugOption     : pString;                  { debug option }
    ignoreOption    : pString;                  { ignore option }
    theCommandLine  : pString;
    switch          : pString;
    makeFileIsOK    : boolean;

    Procedure CheckMakeFileType(var fileIsOK : Boolean);
    var
        getInfoParms    :   getFileInfoOSDCB;
        theName         :   GSOSInString;
    begin
        With getInfoParms do
        begin
            theName.theString := makefileName;
            theName.size := length(makefileName);
    
            pCount := 7;
            pathName := @theName;
    
            GetFileInfoGS(getInfoParms);
    
            If toolError <> 0 then begin
                fileIsOK := false;
                writeln(errorOutput, '<mk> unable to check makefile :', makefileName);
            end else begin
    
                with getInfoParms do
                begin
                    if (fileType = TextFile) or
                       (fileType = SourceFile) then begin
                        fileIsOK := true;
                    end else begin
                        writeln(errorOutput, '<mk> Makefile must be either TXT or SRC.');
                        fileIsOK := false;
                    end;
                end;
            end;
       end;
    end;    { CheckMakeFileType }
    
    Procedure deTabString(var value : pString);
    var
        index   :   integer;
    begin
        If value <> '' then
            For index := 1 to length(value) do
                If value[index] = chr(9) then
                    value[index] := chr(space);
    end;

    Procedure trimString(var value : pString);
    begin
        If value <> '' then begin
            deTabString(value);

            while (value[1] = chr(space)) do
                delete(value, 1, 1);

            while (value[length(value)] = chr(space)) do
                delete(value, length(value), 1);
        end;
    end;

    procedure readMakefile;
    var
        makeLine        : pString;      { a line of data from the makefile }
        currentObject   : pString;      { an object e.g. target, source .. }
        currentTarget   : targetPtr;    { target we are working with }
        charIndex       : integer;      { character index into strings }
        openStatus      : integer;      { return status from open }
        inCommandList   : boolean;

        function createTarget(var targetList : targetPtr;
                              var targetName : fileName ) : targetPtr;
        { Searches the targetList chain for an entry with this targetName.
          If it doesn't find one, then it creates one.
          Returns pointer to the target entry found / created. }
        begin   { createTarget }
            if targetList = nil then begin
                { end of list - create one }
                new(targetList);

                with targetList^ do begin
                    left:= nil;
                    right := nil;
                    name := targetName;
                    built := false;
                    builtTime := 0;
                    sources := nil;
                    actions := nil;
                end;    { with targetList }

                createTarget := targetList;
            end else begin
                { one side or the other }
                with targetList^ do begin
                    if targetName < name then begin
                        { left branching }
                        createTarget := createTarget(left, targetName);
                    end else begin
                        if targetName > name then begin
                            { right branching }
                            createTarget := createTarget(right, targetName);
                        end else begin
                            { duplicate entry }
                            writeln(errorOutput, '<mk> duplicate target :', targetName );
                            createTarget := targetList;
                        end;    { test for right or current branch }
                    end;        { test for left branch }
                end;    { with targetList^ }
            end;    { test for end of chain }
        end;    { createTarget }

        function addFindSourceNode(var sourceList : sourceNodePtr;
                                   var sourceName : fileName ) : sourceNodePtr;
        { Searches the sourceList chain for an entry with this sourceName.
          If it doesn't find one, then it creates one.
          Returns pointer to the target entry found / created. }
        begin   { addFindSourceNode }
            if sourceList = nil then begin
                { end of list - create one }
                new(sourceList);

                with sourceList^ do begin
                    left:= nil;
                    right := nil;
                    name := sourceName;
                    targetId := nil;
                    built := false;
                    failed := false;
                    builtTime := 0;
                end;    { with sourceList }

                If debugTimes then begin
                    writeln(errorOutput, '<mk - src> source:',
                            sourceName);
                end;

                addFindSourceNode := sourceList;
            end else begin
                { one side or the other }
                with sourceList^ do begin
                    if sourceName < name then begin
                        { left branching }
                        addFindSourceNode := addFindSourceNode(left, sourceName);
                    end else begin
                        if sourceName > name then begin
                            { right branching }
                            addFindSourceNode := addFindSourceNode(right, sourceName);

                            If debugTimes then begin
                                writeln(errorOutput, '<mk - src> source:',
                                        sourceName);
                            end;
                        end else begin
                            { already exists }
                            If debugTimes then begin
                                writeln(errorOutput, '<mk - dbg> duplicate source:',
                                        sourceName);
                            end;

                            addFindSourceNode := sourceList;
                        end;    { test for right or current branch }
                    end;        { test for left branch }
                end;    { with sourceList^ }
            end;    { test for end of chain }
        end;    { addFindSourceNode }

        procedure addSource(var sourceName : fileName);
        { Creates a source entry for the current target using the name given. }
        var
            tempSrcPtr  : sourcePtr;
        begin   { addSource }
            { add a source entry into the current target }
            new(tempSrcPtr);

            with tempSrcPtr^ do begin
                node := addFindSourceNode(sourceTree, sourceName);

                { insert in front of current source list }
                others := currentTarget^.sources;
                currentTarget^.sources := tempSrcPtr;
            end;    { with tempSrcPtr }
        end;    { addSource }

        procedure addAction(var sourceAction   : pString);
        { Creates an action entry for the current target using the name given. }
        var
            tempCmdPtr  : makeCommandPtr;

        begin   { addAction }
            { add an action entry into the current target }
            new(tempCmdPtr);

            with tempCmdPtr^ do begin
                action := sourceAction;

                { insert in front of current action list }
                actions := currentTarget^.actions;
                currentTarget^.actions := tempCmdPtr;
            end;    { with tempCmdPtr }
        end;    { addAction }

        procedure stripBlanks;
        var
            done    : boolean;
            dummy   : char;

        begin   { stripBlanks }
            done := false;
            while not done do begin
                if eof(makefile) then begin
                    done := true;
                end else begin
                   if eoln(makefile) then begin
                       readln(makefile);
                   end else begin
                       if (makefile^ = chr(space)) or
                          (makefile^ = chr(tabChar)) then begin
                           get(makefile);
                       end else begin
                           done := true;
                       end;    { not a strippable char }
                   end;    { not eoln }
                end;    { not eof }
            end;    { while not done }
        end;    { stripBlanks }

        procedure readTarget;
        { Routine to read a target name. }

        var
            targetName      : fileName;     { a source file name }
            currentChar     : char;         { char we just read }
            readingTarget   : boolean;      { reading a target }

        begin   { readTarget }
            { we start out looking for a target }
            readingTarget := true;

            while readingTarget do begin
                if eof(makefile) then begin
                    readingTarget := false;
                end else begin
                    { not eof - maybe eoln }
                    if eoln(makefile) then begin
                        { need to read in another line }
                        if not eof(makefile) then begin
                            readln(makefile);
                            { and discard blanks }
                            stripBlanks;
                        end else begin
                            { fell off the end looking for target }
                            readingTarget := false;
                        end;    { test for eof }
                    end else begin
                        { not eoln - see what we can find }
                        { normal characters }
                        if makefile^ = chr(commentChar) then begin
                            { comment line - skip it }
                            readln(makefile);
                            { and strip blanks }
                            stripBlanks;
                        end else begin
                            { not a comment line }
                            targetName := '';

                            while (makefile^ in ['a'..'z','A'..'Z','.','0'..'9',':','/'] ) and (not eof(makefile)) do begin
                                { read another character }
                                read(makefile, currentChar);

                                if currentChar in ['a'..'z'] then
                                    currentChar := upper(currentChar);

                                targetName := concat(targetName, currentChar);
                            end;    { run out of source name characters }

                            { may have read a target name }
                            if targetName <> '' then begin
                              If debugTimes then begin
                                writeln(errorOutput, '<mk - trg> ', targetName);
                              end;

                              readingTarget := false;
                              currentTarget := createTarget(targetTree, targetName);
                            end;    { test for non-null target name }
                        end;    { test for comment line }
                    end;    { test for if eoln }
                end;    { test for eof }
            end;    { while of readingTarget }
        end;    { readTarget }

        procedure readCommand;
        { read a command }
        var
            commandInput    : pString;                           { the line we read in }
            actionString    : pString;                           { the final resultant command }
            continue        : boolean;                           { if we are continueing lines }
            lastChar        : char;

        begin   { readCommand }
            actionString := '';
            continue := true;

            while continue do begin
                stripBlanks;   { discard leading crap }
                readln(makefile, commandInput);
                charIndex := pos(chr(commentChar), commandInput);

                if charIndex <> 0 then begin
                    delete(commandInput, charIndex, length(commandInput) - charIndex + 1);
                end;

                trimString(commandInput);
                lastChar := commandInput[length(commandInput)];

                if commandInput[1] = chr(compoundCommandChar) then begin
                    writeln(erroroutput, '<mk> Single command may not begin with a compound command character.');
                    halt(-1);
                end;

                if lastChar = chr(continueChar) then
                    actionString := concat(actionString,
                                           copy(commandInput, 1, length(commandInput) - 1))
                else begin
                    continue := false;

                    If lastChar = chr(endCompoundCommandChar) then begin
                        delete(commandInput, length(commandInput), 1);
                        trimString(commandInput);
                        lastChar := commandInput[length(commandInput)];

                        If lastChar = chr(continueChar) then begin
                            writeln(erroroutput,'<mk> Invalid command continuation character.');
                            halt(-1);
                        end;

                        inCommandList := False;
                    end;

                    actionString := concat(actionString, commandInput);
                end;    { continued line }
            end;    { while continue loop }

            IF debugTimes then begin
              writeln(errorOutput, '<mk - act> ', actionString);
            end;

            addAction(actionString);
        end;    { readCommand }

        procedure readCommandList;
        { read a sequence of commands }
        begin   { readCommandList }
            inCommandList := true;

            while inCommandList do begin
                stripBlanks;

                if not eof(makefile) then begin
                    case ord(makefile^) of
                        endCompoundCommandChar  :   begin   { finished a command list }
                                                        { skip to end of line }
                                                        readln(makefile);
                                                        inCommandList := false;
                                                    end;    { just finished a command list }
                        commentChar             :   begin   { comment line in command list }
                                                        readln(makefile);
                                                    end;    { comment line in command list }
                        otherwise               :   readCommand;
                    end;    { case makefile^ for command list }
                    
                end else begin
                    inCommandList := false;
                end;    { not eof }
            end;    { while in command list }
        end;    { readCommandList }

        procedure readSourceList;
        { Routine to read a list of sources.
          Discard blanks, and end of line comments.
          Stop when we hit eof, or start of command(s) character. }

        var
            inSourceList    : boolean;      { are we still in a source list }
            sourceName      : fileName;     { a source file name }
            currentChar     : char;         { char we just read }

            Procedure handleNormalChars;
            begin
                { normal characters }
                sourceName := '';
                while ( makefile^ in ['a'..'z','A'..'Z','.','0'..'9',':','/'] ) and (not eof(makefile)) do begin
                    { read another character }
                    read(makefile, currentChar);

                    if currentChar in ['a'..'z'] then
                        currentChar := upper(currentChar);

                    sourceName := concat(sourceName, currentChar);
                end;    { run out of source name characters }

                { may have read a source name }
                if sourceName <> '' then begin
                    { add a source entry to the current target }
                    { and add to current target's source list }
                    addSource(sourceName);
                end;
            end;    { end otherwise char in source list }

        begin   { readSourceList }
            inSourceList := true;

            while inSourceList do begin
                if eof(makefile) then begin
                    { didn't finish a source list before we fell down }
                    inSourceList := false;
                    writeln(errorOutput, '<mk> incomplete makefile - target with no command sequence');
                end else begin
                    { not eof - maybe eoln }
                    if eoln(makefile) then begin
                        { need to read in another line }
                        if not eof(makefile) then begin
                            readln(makefile);
                            { and discard blanks }
                            stripBlanks;
                        end;
                    end else begin
                        { not eoln - see what we can find }
                        case ord(makefile^) of
                            compoundCommandChar,
                            simpleCommandChar      :  inSourceList := false;
                            commentChar            :  readln(makefile);
                            space,
                            tabChar                :  stripBlanks;
                            otherwise              :  handleNormalChars;
                        end;    { case of next char in source list }
                    end;    { test for if eoln }
                end;    { test for if eof }
            end;    { while loop for inSourceList }
        end;    { readSourceList }

        procedure fillSourceChains(sourceEntry : sourceNodePtr);
        { Need to update the source entries targetId fields, now that we know
          all targets. }

        begin   { fillSourceChains }
            if sourceEntry <> nil then begin
                with sourceEntry^ do begin
                    { find target for this source }
                    targetId := findTarget(targetTree, name);

                    { and go update the other branches }
                    fillSourceChains(left);
                    fillSourceChains(right);
                end;    { with sourceEntry }
            end;    { haven't finished the current source }
        end;    { fillSourceChains }

    begin   { readMakefile }
        reset(makefile, makefileName);

        if programStatus <> noErrors then begin
            { open error }
            writeln(errorOutput, '<mk> makefile "', makefileName, '" not found');
            halt(programStatus);
        end;

        while not eof(makefile) do begin
            { read in a line of data }
            readTarget;

            if not eof(makefile) then begin
                readSourceList;

                case ord(makefile^) of
                    compoundCommandChar :   begin
                                                { skip over the start of compound command }
                                                get(makefile);
                                                readCommandList;
                                            end;
                    simpleCommandChar   :   begin
                                                { skip over the start of single command }
                                                get(makefile);
                                                { and read the command }
                                                readCommand;
                                            end;
                    otherwise           :   writeln(erroroutput,'bad case');
                end;    { case of next char }
            end;    { fell off the end of the file }
        end;    { loop on eof ( makefile ) }

        { and now update all of the source lists with target pointers }
        fillSourceChains(sourceTree);
    end;    { readMakefile }

    Procedure getWord(var line  : pString;
                          start : integer;
                      var value : pString);
    var
        count   :   integer;
    begin
        count := start;

        while (line[count] <> chr(space)) and
              (count <= length(line)) do
            count := count + 1;

        count := count - start;

        value := copy(line, start, count);

        delete(line, start, count);

        trimString(line);
    end;

    Function switchPresent : Boolean;
    begin
        If pos(switch, theCommandLine) <> 0 then
            switchPresent := True
        else
            switchPresent := False;
    end;

    Procedure deleteWord(var line   :   pString;
                             start  :   integer);
    var
        dummyWord   :   pString;
    begin
        getWord(line, start, dummyWord);
    end;

    Procedure deleteSwitch;
    begin
        deleteWord(theCommandLine, pos(switch, theCommandLine));
        trimString(theCommandLine);
    end;

    Procedure getSwitchValue(var value  :   pString);
    var
        switchPosition  :   integer;
    begin
        switchPosition := pos(switch, theCommandLine);
        deleteSwitch;
        getWord(theCommandLine, switchPosition, value);
    end;

begin   { initializeVars }

    InitEZDates;

    targetTree := nil;
    sourceTree := nil;
    requestedTargets := nil;
    debugEverything := false;

    CommandLine(theCommandLine);
    deleteWord(theCommandLine, 1);

    switch := '-v';
    if switchPresent then begin
        deleteSwitch;
        writeln('<mk> Version 1.0');
    end;

    switch := '-a';
    if switchPresent then begin
        deleteSwitch;
        alwaysBuild := true;
    end else begin
        alwaysBuild := false;
    end;

    switch := '-e';
    if switchPresent then begin
        deleteSwitch;

        switch := '-noe';
        If switchPresent then begin
            writeln(errorOutput, '<mk> -eXECUTE and -noeXECUTE are mutually exclusive.');
            halt(-1);
        end;

        doCommands := true;
    end else begin
        switch := '-noe';
        if switchPresent then begin
            deleteSwitch;
            doCommands := false;
        end else begin
            doCommands := true;
        end;
    end;

    switch := '-c';
    if switchPresent then begin
        getSwitchValue(commandFileName);
        commandMake := true;
        doCommands := false;
        commandFileOpen := false;
    end else begin
        commandMake := false;
    end;

    switch := '-i';
    if switchPresent then begin
        deleteSwitch;

        switch := '-noi';
        If switchPresent then begin
            writeln(errorOutput, '<mk> -iGNORE and -noiGNORE are mutually exclusive.');
            halt(-1);
        end;

        ignoreNonCompileErrors := True;
    end else begin
        switch := '-noi';
        if switchPresent then begin
            deleteSwitch;
            ignoreNonCompileErrors := False;
        end else begin
            ignoreNonCompileErrors := True;
        end;
    end;

    switch := '-t';
    while switchPresent do begin
        new(requestPtr);
        with requestPtr^ do begin
            getSwitchValue(name);
            next := requestedTargets;
        end;

        requestedTargets := requestPtr;
    end;

    switch := '-l';
    if switchPresent then begin
        if requestedTargets = nil then begin
            writeln(errorOutput, '<mk> Must specify target(s) with LIST option');
            halt(-1);
        end else begin
            deleteSwitch;
            listDepend := true;
        end;
    end else begin
        listDepend := false;
    end;

    switch := '-d';
    if switchPresent then begin
        debugTimes := TRUE;
        deleteSwitch;
    end else begin
        debugTimes := FALSE;
    END;

    switch := '-o';
    if switchPresent then begin
        pipeOutput := true;
        getSwitchValue(pipeFileName);
        pipeFileOpen := false;
    end else begin
        pipeOutput := false;
    end;

    if theCommandLine <> '' then begin
        getWord(theCommandLine, 1, makeFileName);

        if theCommandLine <> '' then begin
            writeln(errorOutput, '<mk> Extraneous information on command line ignored ("',theCommandLine,'"');
        end;
    end else begin
        makeFileName := 'makefile';
    end;

    CheckMakeFileType(makeFileIsOK);
    
    if makeFileIsOK then begin
        readMakefile;
    end;
end;    { initializeVars }

function acceptableStatus(var callStatus : integer;
                          var theCommand : pString) : boolean;
const
  abortMakeError = -45;

   Function aCompile : Boolean;
   begin
       If (pos('COMPILE ',  theCommand) <> 0)   or
          (pos('CMPL ',     theCommand) <> 0)   or
          (pos('CMPLG ',    theCommand) <> 0)   or
          (pos('ASSEMBLE ', theCommand) <> 0)   or
          (pos('ASML ',     theCommand) <> 0)   or
          (pos('ASMLG ',    theCommand) <> 0)   or
          (pos('ASM ',      theCommand) <> 0)
       then
           aCompile := True
       else
           aCompile := False;
   End;

begin   { acceptableStatus }
    UpperStr(theCommand);

    If (callStatus = 0) then begin
      acceptableStatus := True;
    end else begin
      If aCompile then begin
        acceptableStatus := false;
        callStatus := abortMakeError;
      end else begin
        IF callStatus <> abortMakeError then begin
          If ignoreNonCompileErrors then begin
            acceptableStatus := True;
          end else begin
            acceptableStatus := false;
          end;
        end else begin
          acceptableStatus := false;
        end;
      end;
    end;
end;    { acceptableStatus }

function doCommandList(current : makeCommandPtr) : integer;
var
    callStatus : integer;      { status of doing commands }

begin   { doCommandList }
    if current <> nil then begin
        { we have an action to do }
        with current^ do begin
            { first do the tail }
            callStatus := doCommandList(actions);
            { and now do the current one if the operations have been good so far }

            If debugTimes then begin
              writeln(errorOutput, '<mk - deb> ', action);
            end;

            if actions <> NIL then begin
              if acceptableStatus(callStatus, actions^.action) then begin
                  if debugEverything then
                      writeln(errorOutput, '<mk> ', action);
                  doCommandList := doCommand(action);
              end else begin
                  doCommandList := callStatus;
              end;    { test for reasonable status so far }
            end else begin
                if debugEverything then
                    writeln(errorOutput, '<mk> ', action);
                doCommandList := doCommand(action);
            end;    { test for reasonable status so far }
        end;    { with current }
    end else begin
        { end of chain - pass back good status }
        doCommandList := noErrors;
    end;    { end of this command chain }
end;    { doCommandList }

function sourceNewer(oldTime : fileTime;
                     newTime : fileTime) : Boolean;
begin
    If (newTime > oldTime) then
        sourceNewer := True
    else
        sourceNewer := False;
end;

procedure buildSource(    current        : sourcePtr;
                      var buildFailure   : boolean;
                      var theTime        : fileTime); forward;

procedure buildTarget(    current        : targetPtr;
                      var buildFailure   : boolean;
                      var theTime        : fileTime);
{ Routine builds a target if the target has not been built, and the target is
  out of date w.r.t. its sources. }

var     { buildTarget }
    sourceTime          : fileTime;     { temporary timeStamp }
    callStatus          : integer;      { status from  actions }
    noFilePresent       : boolean;      { set to true if a file is missing }
    sourceListFailure   : boolean;      { failure of source list }
    targetFailure       : boolean;      { failure of building target }

begin   { buildTarget }
    if current = nil then begin
        { no target - zero time }
        sourceTime := 0;
        buildFailure := false;     { return success }
        if debugEverything then
            writeln(errorOutput, '<mk - last target built, end of chain');
    end else begin
        with current^ do begin
            if not built then begin
                { not built yet - must go check dates of the sources }
                if debugEverything then
                    writeln(errorOutput, '<mk - building sources of target: ', current^.name);
                buildSource(sources, failed, sourceTime);
                
                if not failed then begin
                    { worth building this target too }
                    if debugEverything then
                        writeln(errorOutput, '<mk - all sources built for target: ', current^.name);
                    getFileTime(name, builtTime, noFilePresent);
                    
                    if noFilePresent or
                       sourceNewer(builtTime, 
                                   sourceTime) or
                       alwaysBuild then begin
                        if debugEverything then begin
                            writeln(errorOutput, '<mk - doing commands for target: ', current^.name);
                            writeln(errorOutput, '<mk - targetMissing: ', noFilePresent);
                            writeln(errorOutput, '<mk - sourcesAreNewer: ', sourceNewer(builtTime, sourceTime));
                        end;
                        callStatus := doCommandList(actions);
                        
                        builtTime := currentTime;
                        
                        failed := not acceptableStatus(callStatus, actions^.action);
                    end else begin
                        if debugEverything then begin
                            writeln(errorOutput, '<mk - no need to do commands for ', current^.name);
                            writeln(errorOutput, '<mk - targetMissing: ', noFilePresent);
                            writeln(errorOutput, '<mk - sourcesAreNewer: ', sourceNewer(builtTime, sourceTime));
                        end;
                    end;        { test for need to build }
                end;    { test for source list failed }

                if failed then begin
                    writeln(errorOutput, '<mk> Errors making ', name, ' :: abondoned');
                    halt(-1);
                end else begin
                    { now built }
                    if debugEverything then
                        writeln(errorOutput, '<mk - target built OK: ', current^.name);
                    built := true;
                end;
            end else begin
                if debugEverything then
                    writeln(errorOutput, '<mk - target has been built already: ', current^.name);
              
                getFileTime(current^.name, builtTime, failed);
            end;    { test for if built already }

            { now built one way or another - pass back failure condition }
            buildFailure := failed;
            sourceTime := builtTime;
        end;    { with current^ }
    end;    { test for end of the line }

    theTime := sourceTime;
end;    { buildTarget }

procedure buildSource;
{ Routine to build a source entry. If the source entry is a target then we 
  build the target, otherwise just get the dateStamp, and build the rest of
  the source list. We return the largest time of this source and the rest of
  the sourceList. }

var
    sourceTime          : fileTime;     { temporary time stamp }
    sourceListTime      : fileTime;     { time stamp of the chain }
    sourceFailure       : boolean;      { failure of building this entry }
    sourceListFailure   : boolean;      { failure of building tail }

begin   { buildSource }
    if current = nil then begin
        { at end of source list }
        sourceTime := 0;
        buildFailure := false;     { return success }
        if debugEverything then
            writeln(errorOutput, '<mk - last source built, end of chain');
    end else begin
        with current^.node^ do begin
            { we have a source entry }
            if not built then begin
                { not built - go get the time }
                if targetId <> nil then begin
                    { must build target }
                    if debugEverything then
                        writeln(errorOutput, '<mk - source <', current^.node^.name, '> is a target, building');
                    
                    buildTarget(targetId, sourceFailure, builtTime);
                end else begin
                    { not target - just get time stamp for source }
                    if debugEverything then
                        writeln(errorOutput, '<mk - source <', current^.node^.name, '> is not a target');
                    
                    getFileTime(name, builtTime, sourceFailure);
                end;    { test for if this source entry is also a target }
            end else begin
                if debugEverything then
                    writeln(errorOutput, '<mk - source <', current^.node^.name, '> has already been built');
            end;    { test for if already inspected }

            If not sourceFailure then begin
                { now built - just use the time in the structure }
                sourceTime := builtTime;

                { build the rest of the chain of sources }
                buildSource(current^.others, sourceListFailure,
                            sourceListTime);

                { return larger of this sources time, and source list tails time }
                if sourceNewer(sourceTime,
                               sourceListTime) then begin
                    if debugEverything then
                        writeln(errorOutput, '<mk - sourceList is newer than source: ', current^.node^.name);
                    sourceTime := sourceListTime;
                end;
            end;

            buildFailure := sourceFailure or sourceListFailure;
        end;    { with current^ }
    end;    { test for end of source list }

    { return the biggest time in the source list including this one - zero if end of the line }
    theTime := sourceTime;
end;    { buildSource }

procedure listDependencies;
{ List the source dependencies for the specific targets requested. }

var
    requestedTargetPtr  : targetPtr;    { pointer to the requested target }
    discard             : boolean;      { discarded status of build }

    procedure listDependents(targetList : targetPtr); forward;

    procedure listSources(sourceList : sourcePtr);
    { List a source entry. }

    begin       { listSources }
        if sourceList <> nil then begin
            with sourceList^ do begin
                with node^ do begin
                    if targetId = nil then begin
                        { no dependents - a true source }
                        writeln(errorOutput, '    ', name);
                    end else begin
                        { this source has sources
                            - don't list it, just it's sources }
                        listDependents ( targetId );
                    end;    { test for dependent source or not }
                end;    { with node^ }
                listSources ( others );
            end;    { with sourceList^ }
        end;    { test for end of source list }
    end;        { listSources }

    procedure listDependents;
    { list the source base for a target }
    begin       { listDependents }
        if targetList <> nil then begin
            { go list the sources }
            listSources(targetList^.sources);
        end;    { test for end of the line }
    end;        { listDependents }

begin   { listDependencies }
    { specific requests - see if it exists }
    while requestedTargets <> nil do begin
        requestedTargetPtr := findTarget(targetTree, requestedTargets^.name);

        if requestedTargetPtr = nil then
            writeln(errorOutput, '<mk> Requested target ', requestedTargets^.name, ' unknown')
        else begin
            { write out the target }
            writeln(errorOutput, requestedTargetPtr^.name);
            listDependents(requestedTargetPtr);
        end;    { we have a target to list }

        { and advance to next - should dispose but who cares }
        requestedTargets := requestedTargets^.next;

        { blank line between lists }
        writeln(errorOutput);
    end;    { test for end of request list }
end;    { listDependencies }

procedure buildSpecificTargets;
{ Build the set of specific targets requested. }

var
    requestedTargetPtr  : targetPtr;    { pointer to the requested target }
    discard             : boolean;      { discarded status of build }
    dummyTime           : fileTime;
    dummyDate           : fileTime;

begin   { buildSpecificTargets }
    { specific requests - see if it exists }
    while requestedTargets <> nil do begin
        requestedTargetPtr := findTarget(targetTree, requestedTargets^.name);

        if requestedTargetPtr = nil then
            writeln(errorOutput, '<mk> Requested target ', requestedTargets^.name, ' unknown')
        else
            buildTarget(requestedTargetPtr, discard, dummyTime);

        { and advance to next - should dispose but who cares }
        requestedTargets := requestedTargets^.next;

        { and a blank line after a targetSource list }
        writeln(errorOutput);
    end;    { test for end of request list }
end;    { buildSpecificTargets }

procedure buildTargets(currentTarget : targetPtr);
{ Routine to build all targets - just make sure we touch on every node in tree. }

var     { buildTargets }
    discard     :   boolean;  { dummy var for calls to buildTarget }
    dummyTime   :   fileTime;
begin   { buildTargets }
    if currentTarget <> nil then begin
        buildTarget(currentTarget, discard, dummyTime);
        buildTargets(currentTarget^.left);
        buildTargets(currentTarget^.right);
    end;    { test for non-existent target }
end;    { buildTargets }

begin   { make program body }
    initializeVars;
    
    if debugEverything then
        outputAll;

    if listDepend then
        listDependencies
    else begin
        { normal case - not list dependencies }
        if requestedTargets <> nil then
            buildSpecificTargets
        else { build everything }
            buildTargets(targetTree);
    end;    { test for LIST option }
end.    { make }
