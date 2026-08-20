on elementsWithRole(targetWindow, targetRole)
    set matches to {}
    tell application "System Events"
        repeat with elementRef in (entire contents of targetWindow)
            try
                if role of elementRef is targetRole then set end of matches to elementRef
            end try
        end repeat
    end tell
    return matches
end elementsWithRole

on buttonNamed(targetWindow, targetName)
    tell application "System Events"
        repeat with elementRef in (entire contents of targetWindow)
            try
                if role of elementRef is "AXButton" and description of elementRef is targetName then return elementRef
            end try
        end repeat
    end tell
    error "Missing button: " & targetName
end buttonNamed

tell application "System Events"
    tell process "Pullr"
        set frontmost to true
        set targetWindow to window 1
        set beforeCount to count of my elementsWithRole(targetWindow, "AXScrollArea")
        click my buttonNamed(targetWindow, "Hide inspector")
        delay 0.4
        set afterCount to count of my elementsWithRole(targetWindow, "AXScrollArea")
        if afterCount is not less than beforeCount then error "Inspector stayed visible: scroll areas " & beforeCount & " -> " & afterCount
        click my buttonNamed(targetWindow, "Show inspector")
        return "PASS inspector toggle: scroll areas " & beforeCount & " -> " & afterCount
    end tell
end tell
