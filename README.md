# AirPods Mouse

Control your Mac's cursor with your AirPods: move your head to move the cursor, and press the stem, tap an earbud or flip the case lid to click.

| Gesture                       | Default action            |
| ----------------------------- | ------------------------- |
| Turn head left / right        | Move cursor horizontally  |
| Tilt head up / down           | Move cursor vertically    |
| Stem press ×1                 | Left click                |
| Stem press ×2                 | Right click               |
| Stem press ×3                 | Pause / resume tracking   |
| Tap on an earbud              | Left click                |
| Double tap on an earbud       | Do nothing (off)          |
| Open or close the case lid    | Left click                |

You can change every click gesture in the menu bar icon → **Gestures**. Each one can be a left, right,
middle or double click, pause/resume tracking, or do nothing.

It's a small menu bar app (headphones icon) with settings for sensitivity, axis inversion and pausing.

## Requirements

- macOS 14 or later
- AirPods with head tracking (AirPods Pro, AirPods Max, AirPods 3rd gen or later) connected to the Mac
- Xcode command-line tools (`swift`)

## Build & run

```bash
./build.sh
open "build/AirPods Mouse.app"
```

On first launch macOS asks for three permissions:

1. **Motion & Fitness**: lets the app read AirPods head motion and earbud taps. Allow it.
2. **Bluetooth**: lets the app see the case lid opening and closing. Allow it.
3. **Accessibility**: lets the app move the cursor and click. Turn on *AirPods Mouse* in
   System Settings → Privacy & Security → Accessibility, then quit and reopen the app.

> **Rebuilding:** macOS links the Accessibility permission to the app's code signature. The
> default ad-hoc signature changes on every build, so after a rebuild you need to remove
> *AirPods Mouse* from the Accessibility list and add it again. To avoid that, sign with a
> stable identity: `SIGN_IDENTITY="Apple Development: …" ./build.sh`
> (find yours with `security find-identity -v -p codesigning`).

## How it works

- **Head motion:** `CMHeadphoneMotionManager` streams the AirPods' orientation at about 25 Hz.
  The app turns the change in yaw and pitch between samples into cursor movement. A small
  deadzone filters out drift, and mild acceleration lets slow movements stay precise while
  fast ones cover distance. A 120 Hz smoothing loop keeps the cursor from stuttering between samples.
- **Taps:** AirPods don't send raw taps to macOS. Stem presses arrive as media commands
  (play/pause, next, previous) sent to the system's *Now Playing* app. AirPods Mouse becomes the
  Now Playing app by publishing now-playing info and playing a silent audio stream, then turns
  those commands into clicks.
- **Earbud taps:** a tap on an earbud shows up as a sudden spike in the AirPods accelerometer
  that's gone by the next sample. Head movement builds up more slowly and lasts longer, so it
  isn't counted as a tap. While a spike is being checked, cursor movement is frozen, and the click
  lands where the cursor was *before* the tap jolted your head. Turning on Earbud Double Tap
  delays single taps by about 0.45 s while the app waits for a possible second tap.
- **Case lid:** AirPods broadcast a Bluetooth LE "proximity pairing" packet (the same one that
  shows the battery pop-up on an iPhone). One byte in it changes when the case lid opens or closes.
  The app scans for those packets and treats a change in that byte as the gesture. This only works
  while **at least one earbud is in the case**, since the earbuds only know the lid state then.
  Packets weaker than -70 dBm are ignored so other people's AirPods don't click for you, and
  opening and then closing within 1.5 s counts as one gesture. Bluetooth scanning only runs while
  the lid gesture is set to something other than *Do Nothing*.

## Troubleshooting

- **Clicks stop working after you play music:** Music or Spotify took over Now Playing.
  Choose **Reclaim AirPods Controls** (⌘R) from the menu bar icon.
- **Cursor moves the wrong way:** use **Invert Horizontal** or **Invert Vertical** in the menu.
- **Cursor drifts or jitters:** lower the sensitivity, or pause tracking with a triple press.
- **Earbud taps are missed or fire by accident:** change **Gestures → Earbud Tap Sensitivity**.
  Turn on **Debug Log**, then use **Show Debug Log** to see how strong each spike was in g,
  and pick a level just below your taps.
- **Case lid does nothing:** check the menu shows *Case lid: listening*, and keep an earbud in the case.
  With Debug Log on, each detected lid change is logged with the raw packet.
- **Cursor doesn't move at all:** check that the menu shows *Accessibility: granted* and
  *AirPods: connected*, and that both AirPods are in your ears.
