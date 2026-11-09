// Scene lengths in frames at 30 fps. VOICEOVER.md is timed against these, so update both together.
export const scenes = {
  hook: { from: 0, duration: 104 },
  mac: { from: 104, duration: 270 },
  statements: { from: 374, duration: 72 },
  end: { from: 446, duration: 120 },
};

export const totalFrames = 566;

// Moments inside the Mac scene, relative to the start of that scene.
export const mac = {
  zoomToNotch: 2,
  atNotch: 18,
  openNotch: 22,
  panelOpen: 34,
  cameraOnPanel: 46,
  typingStart: 38,
  typingEnd: 62,
  cursorAtOptimize: 72,
  clickOptimize: 74,
  result: 104,
  resultOpen: 114,
  scrollStart: 134,
  scrollEnd: 186,
  cursorAtCopy: 198,
  clickCopy: 200,
  closeNotch: 212,
  notchClosed: 222,
  paste: 232,
  cameraOnTerminal: 240,
};

export const request = "my app is slow and buggy, fix it";
