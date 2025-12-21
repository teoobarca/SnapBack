on run
  if shouldThrottle(2) then return

  -- If we're already in Ghostty, only play the notification (no focus changes / no media pause)
  if getReturnTargetAppName() is "Ghostty" then
    playNotification()
    return
  end if

  resetResumeThrottle()

  playNotification()

  -- Save the app that was frontmost before we steal focus (no System Events)
  saveReturnApp()
  
  -- Check if Chrome active tab is playing BEFORE we pause
  saveChromeState()

  -- Pause media ASAP (before any focus/delay so video doesn't keep playing in background)
  try
    pauseChrome()
  on error errMsg
    -- log "Error pausing Chrome: " & errMsg
  end try

  -- Focus Apps
  -- Focus Cursor first
  activateApp("Cursor")
  
  -- Focus Ghostty second (to be on top)
  delay 0.5
  activateApp("Ghostty")
end run

on playNotification()
  try
    set p to POSIX path of (path to resource "notification.mp3")
    -- Run sound fully in background; never block the script.
    do shell script "nohup afplay " & quoted form of p & " >/dev/null 2>&1 </dev/null &"
  end try
end playNotification

on resetResumeThrottle()
  try
    set otherLastFile to (POSIX path of (path to temporary items)) & "ai_resume_last"
    do shell script "rm -f " & quoted form of otherLastFile
  end try
end resetResumeThrottle

on shouldThrottle(secondsWindow)
  set lastFile to (POSIX path of (path to temporary items)) & "ai_attention_last"
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

on activateApp(appName)
  try
    tell application appName
      activate
      -- Optional: Ensure it really comes to front by asking twice or using System Events fallback
    end tell
  on error
    -- App might not be running, ignore
  end try
end activateApp

on pauseChrome()
  if not isProcessRunning("Google Chrome") then return

  tell application "Google Chrome"
    try
      if (count of windows) is 0 then return

      -- Fullscreen Chrome can make "front window" not be the one actually playing.
      -- Only check ACTIVE tab per window; pause the first one that's playing.
      repeat with w in windows
        try
          set t to active tab of w
          set isPlaying to false
          try
            set isPlaying to execute t javascript "(() => { return Array.from(document.querySelectorAll('video,audio')).some(m => !m.paused && !m.ended && m.readyState > 2); })();"
          end try

          if isPlaying is true or isPlaying is "true" then
            try
              execute t javascript "(() => { document.querySelectorAll('video,audio').forEach(m=>{try{m.pause()}catch(e){}}); return true; })();"
            end try
            exit repeat
          end if
        end try
      end repeat
    end try
  end tell
end pauseChrome

on isProcessRunning(procName)
  try
    do shell script "pgrep -x " & quoted form of procName & " >/dev/null 2>&1"
    return true
  on error
    return false
  end try
end isProcessRunning

on saveReturnApp()
  set appName to getReturnTargetAppName()
  if appName is "" then return

  -- Ignore ourselves / helper processes
  if appName is "AIAttention" then return
  if appName is "AIResume" then return
  if appName is "applet" then return

  -- If user was already in our target workflow apps, don't schedule a resume
  if appName is "Cursor" then return
  if appName is "Ghostty" then return

  try
    do shell script "printf %s " & quoted form of appName & " > /tmp/ai_attention_return_app"
  end try
end saveReturnApp

on saveChromeState()
  if not isProcessRunning("Google Chrome") then return

  set isPlaying to "false"
  tell application "Google Chrome"
    try
      if (count of windows) > 0 then
        repeat with w in windows
          try
            set currentTab to active tab of w
            set isPlaying to execute currentTab javascript "(() => { return Array.from(document.querySelectorAll('video,audio')).some(m => !m.paused && !m.ended && m.readyState > 2); })();"
            if isPlaying is true or isPlaying is "true" then exit repeat
          end try
        end repeat
      end if
    on error
      -- default to false if error
    end try
  end tell

  -- JavaScript returns boolean, AppleScript sees it as true/false or "true"/"false" depending on version/context.
  -- Execute javascript usually returns the value.
  
  if isPlaying is true or isPlaying is "true" then
    do shell script "echo 'true' > /tmp/ai_attention_chrome_state"
  else
    do shell script "echo 'false' > /tmp/ai_attention_chrome_state"
  end if
end saveChromeState

on getReturnTargetAppName()
  try
    -- Prefer: top-most on-screen window owner (works even if AIAttention becomes frontmost with no UI)
    set winOwner to do shell script "swift -e 'import Cocoa; import Quartz; let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]; guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { exit(0) }; for w in info { let layer = (w[kCGWindowLayer as String] as? Int) ?? -1; if layer != 0 { continue }; let alpha = (w[kCGWindowAlpha as String] as? Double) ?? 1.0; if alpha <= 0.0 { continue }; if let owner = w[kCGWindowOwnerName as String] as? String, !owner.isEmpty { print(owner); break } }'"
    if winOwner is not "" then return winOwner

    -- Fallback: frontmost app
    return do shell script "swift -e 'import AppKit; if let app = NSWorkspace.shared.frontmostApplication { print(app.localizedName ?? \"\") }'"
  on error
    return ""
  end try
end getReturnTargetAppName
