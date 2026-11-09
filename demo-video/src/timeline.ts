// Scene lengths in frames at 30 fps. VOICEOVER.md is timed against these, so update both together.
export const scenes = {
  opening: { from: 0, duration: 150 },
  mac: { from: 150, duration: 600 },
  statements: { from: 750, duration: 150 },
  end: { from: 900, duration: 180 },
};

export const totalFrames = 1080;

// Moments inside the Mac scene, relative to the start of that scene.
export const mac = {
  zoomToNotch: 45,
  atNotch: 90,
  openNotch: 100,
  panelOpen: 116,
  cameraOnPanel: 135,
  typingStart: 138,
  typingEnd: 195,
  cursorAtOptimize: 225,
  clickOptimize: 228,
  result: 300,
  resultOpen: 316,
  scrollStart: 345,
  scrollEnd: 450,
  cursorAtCopy: 475,
  clickCopy: 478,
  closeNotch: 500,
  notchClosed: 511,
  paste: 530,
  cameraOnTerminal: 540,
};

export const request = "my app is slow and buggy, fix it";
