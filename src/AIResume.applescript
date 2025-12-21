on run
  if shouldThrottle(2) then return

  set returnApp to consumeReturnApp()
  if returnApp is "" then return

  resetAttentionThrottle()

  if returnApp is "Google Chrome" then
    resumeChrome()
  else
    activateApp(returnApp)
  end if
end run

on resetAttentionThrottle()
  try
    set otherLastFile to (POSIX path of (path to temporary items)) & "ai_attention_last"
    do shell script "rm -f " & quoted form of otherLastFile
  end try
end resetAttentionThrottle

on shouldThrottle(secondsWindow)
  set lastFile to (POSIX path of (path to temporary items)) & "ai_resume_last"
  set nowSec to (do shell script "date +%s")

  try
    set lastSec to (do shell script "cat " & quoted form of lastFile)
    if (nowSec - lastSec) as integer ≤ secondsWindow then
      return true
    end if
  end try

  do shell script "echo " & nowSec & " > " & quoted form of lastFile
  return false
end shouldThrottle

on consumeReturnApp()
  try
    set appName to do shell script "cat /tmp/ai_attention_return_app 2>/dev/null || true"
    do shell script "rm -f /tmp/ai_attention_return_app >/dev/null 2>&1 || true"
    return appName
  on error
    return ""
  end try
end consumeReturnApp

on activateApp(appName)
  try
    tell application appName to activate
  end try
end activateApp

on resumeChrome()
  if not isProcessRunning("Google Chrome") then return

  -- Check if we should resume (consume the state file)
  set shouldResume to false
  try
    set stateContent to do shell script "cat /tmp/ai_attention_chrome_state 2>/dev/null || echo false"
    if stateContent contains "true" then set shouldResume to true
    
    -- Consume the state so we don't accidentally resume later if manually paused
    do shell script "rm -f /tmp/ai_attention_chrome_state"
  end try

  tell application "Google Chrome"
    -- 1. Aktivuj okno
    activate
    
    if shouldResume then
      -- 2. Pusti video LEN na aktívnom tabe aktívneho okna
      try
        set currentTab to active tab of front window
        set u to URL of currentTab
        execute currentTab javascript "(() => { document.querySelectorAll('video,audio').forEach(m=>{try{m.play()}catch(e){}}); return true; })();"
      on error
        -- Ak nie je okno alebo tab, nevadi
      end try
    end if
  end tell
  
end resumeChrome

on isProcessRunning(procName)
  try
    do shell script "pgrep -x " & quoted form of procName & " >/dev/null 2>&1"
    return true
  on error
    return false
  end try
end isProcessRunning
