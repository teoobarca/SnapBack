# SnapBack - Market Research

## The Problem

When using AI coding agents (Claude Code, Cursor, GitHub Copilot, etc.), developers face a common workflow issue:

**The agent works autonomously, but periodically needs human input** (permission requests, clarification questions, review). During this time, developers:
- Watch YouTube, browse, or do other tasks
- Miss when the agent needs attention → agent sits idle
- Context switch back too late → wasted time
- Get distracted and forget to check back

This creates a "babysitting" problem where you either:
1. Stare at the terminal waiting (wastes focus time)
2. Do something else and miss the prompt (wastes agent time)

### The "Inference Gap" Problem

Chad IDE (YC-backed) articulates this well:
> "AI coding creates a time span that isn't long enough to do something new, and it's not short enough to be entirely negligible."

**The 1-5 minute gap:**
- Too long to just wait
- Too short to start meaningful work
- Results in doom-scrolling on phone
- People often forget to come back
- Context-switching builds mental fatigue

## Existing Solutions

### 1. Claude Code Notification Hooks (Official)

Claude Code has built-in hook system for notifications:
- `Notification` hook with matchers: `permission_prompt`, `idle_prompt`
- `PermissionRequest` hook - fires when permission dialog appears
- `Stop` hook - fires when Claude stops working

**Common implementations:**
- `terminal-notifier` for macOS desktop notifications
- `say` command for audio alerts
- OSC escape sequences for terminal notifications (works over SSH)
- ntfy.sh for push notifications

**Limitations:**
- No built-in solution out of the box
- Requires manual configuration
- No media control
- No automatic focus management

### 2. Warp Terminal Agent Mode

Warp has built-in agent mode notifications:
- Desktop notifications when agent completes task
- Notifications when agent needs attention (permission review, unsafe commands)
- Configurable in `Features > Notifications`

**Limitation:** Only works with Warp terminal

### 3. Chad IDE (YC S25) - cladlabs.ai

**The "Brainrot IDE"** - takes the opposite approach to SnapBack:
- Instead of pulling you OUT of distraction → embeds distraction INTO the IDE
- Integrates TikTok, Instagram, X, Stake (gambling), Tinder directly in IDE
- Auto-ends brainrot session when code is ready
- Has "Parallel Agents" for multitasking
- Analytics tracking for entertainment usage during coding

**Their pitch:**
> "Chad aims to manage your AI coding inference time effectively by integrating the modern workflow into a single IDE."

**Reported results:** 15 minutes saved per hour of vibe coding (anecdotal from beta users)

**Philosophy difference:**
| Chad IDE | SnapBack |
|----------|-------------|
| Embrace brainrot, contain it | Interrupt brainrot, return to it |
| Distraction IN the IDE | Distraction OUTSIDE the IDE |
| Entertainment + coding merged | Entertainment + coding separated |
| Ends distraction automatically | Pauses distraction, resumes later |

### 4. Community Notification Projects

**Elevator Music Plugin** (github.com/Sevii/agent-marketplace)
- Plays elevator music when Claude Code waits for input
- Triggers on: idle prompts, permission prompts, Stop events
- Auto-stops after 30 seconds

**pchalasani/claude-code-tools**
- notification_hook.sh - sends ntfy.sh notifications
- Various safety hooks for Claude Code

**kane.mx notification hooks**
- OSC escape sequences for terminal notifications
- UUID-based terminal mapping (knows which tab to notify)
- Works over SSH with VSCode
- Solves "knowing exactly when Claude finishes so you can review results promptly without wasting time and breaking focus"

**zerotopete.com guide**
- Simple terminal-notifier setup
- Uses `say` command for audio alerts
- Basic macOS notification integration

## What Makes SnapBack Different

| Feature | Notification Hooks | Warp | Chad IDE | Elevator Music | SnapBack |
|---------|-------------------|------|----------|----------------|-------------|
| Audio alert | ✅ (manual) | ✅ | ❓ | ✅ (music) | ✅ |
| Desktop notification | ✅ (manual) | ✅ | ❌ | ❌ | ❌ |
| Pause media | ❌ | ❌ | ❌ | ❌ | ✅ |
| Resume media | ❌ | ❌ | ❌ | ❌ | ✅ |
| Focus management | ❌ | ❌ | ✅ (built-in) | ❌ | ✅ |
| Return to previous app | ❌ | ❌ | ❌ | ❌ | ✅ |
| Works with any terminal | N/A | ❌ | N/A | ✅ | ✅ |
| Keeps distraction separate | N/A | N/A | ❌ | N/A | ✅ |

**SnapBack's unique value:**
1. **Media pause/resume** - pauses YouTube/video when attention needed
2. **Window management** - brings IDE + terminal to foreground
3. **Context restoration** - returns you to previous app when done
4. **Seamless workflow** - no manual alt-tab required
5. **Separation of concerns** - keeps entertainment outside IDE

## User Pain Points (from GitHub issues, Reddit, forums)

1. **"Running Claude Code in multiple VSCode windows and needing audio notification when human intervention is required"** - GitHub issue #13203

2. **"I want to play an audio chime whenever Claude needs my attention so I know to check back on it"** - GitHub issue #13024

3. **"I found myself leaving sessions idle while I actually code"** - Reddit r/ClaudeCode

4. **"The hook keeps triggering way too often"** - Reddit (throttling issue - SnapBack solves this)

5. **"Knowing exactly when Claude finishes so you can review the results promptly without wasting time and breaking focus"** - kane.mx

6. **"1-5 minute wasted downtime between prompts"** - Chad IDE problem statement

7. **"People often forget to come back to their code"** - Chad IDE problem statement

8. **"Context-switching builds mental fatigue → decreased efficiency"** - Chad IDE problem statement

## Market Opportunity

The problem is universal across AI coding tools:
- Claude Code users
- Cursor users
- GitHub Copilot Agent users
- Warp Agent Mode users
- Any autonomous AI coding agent

**Two philosophical approaches emerging:**

1. **Integrate distraction (Chad IDE)** - "if you can't beat 'em, join 'em"
2. **Manage distraction (SnapBack)** - "smooth context switching"

Current solutions focus only on **notification** (alert me), not on **attention management** (help me switch context smoothly).

## Competitive Positioning

**SnapBack vs Chad IDE:**
- Chad requires switching to a new IDE
- SnapBack works with existing setup (Cursor, VSCode, any terminal)
- Chad embraces the brainrot culture
- SnapBack is more "professional" / less meme-y
- Both solve the same core problem differently

**Target users:**
- Developers who use Cursor/VSCode and don't want to switch IDEs
- People who prefer keeping work and entertainment separate
- Users who watch YouTube/videos while waiting for AI
- Anyone who alt-tabs away during AI inference time

## Potential Improvements for SnapBack

1. **Cross-platform support** - Linux, Windows (currently macOS only)
2. **Spotify integration** - pause/resume Spotify (not just browser)
3. **Configurable focus apps** - not just Cursor/Ghostty
4. **Multiple browser support** - Firefox, Arc, Safari
5. **Slack/Discord status** - auto-set "focusing" status
6. **Time tracking** - log how long agent waited vs worked
7. **Analytics** - like Chad IDE's entertainment usage tracking
8. **Multiple AI tool support** - detect when ANY AI tool needs attention

## Key Insights

1. **The problem is real and growing** - as AI agents become more autonomous, the "wait gap" becomes more pronounced

2. **YC is funding solutions** - Chad IDE got into YC S25, validating the market

3. **Two valid approaches exist:**
   - Embrace distraction (Chad IDE)
   - Manage distraction (SnapBack)

4. **No one else does media control** - this is SnapBack's unique differentiator

5. **Context switching cost is well-documented** - studies show 23 minutes to regain focus after interruption

6. **The "brainrot" framing resonates** - Chad IDE's viral marketing proves the cultural moment

## Sources

- https://www.ycombinator.com/launches/OgV-chad-ide-the-first-brainrot-ide
- https://cladlabs.ai
- https://kane.mx/posts/2025/claude-code-notification-hooks/
- https://www.zerotopete.com/p/stop-babysitting-claude-code-by-setting
- https://github.com/anthropics/claude-code/issues/13203
- https://github.com/anthropics/claude-code/issues/13024
- https://github.com/Sevii/agent-marketplace
- https://docs.warp.dev/getting-started/changelog
- https://github.com/pchalasani/claude-code-tools
