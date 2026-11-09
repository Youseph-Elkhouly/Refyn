import { AbsoluteFill, Composition, Sequence } from "remotion";

import { MacScene } from "./MacScene";
import { colors } from "./theme";
import { EndCard, Opening, Statements } from "./TextScenes";
import { scenes, totalFrames } from "./timeline";

const RefynDemo: React.FC = () => (
  <AbsoluteFill style={{ background: colors.black }}>
    <Sequence name="Opening" from={scenes.opening.from} durationInFrames={scenes.opening.duration}>
      <Opening />
    </Sequence>
    <Sequence name="Mac walkthrough" from={scenes.mac.from} durationInFrames={scenes.mac.duration}>
      <MacScene />
    </Sequence>
    <Sequence name="Local AI" from={scenes.statements.from} durationInFrames={scenes.statements.duration}>
      <Statements />
    </Sequence>
    <Sequence name="End card" from={scenes.end.from} durationInFrames={scenes.end.duration}>
      <EndCard />
    </Sequence>
  </AbsoluteFill>
);

export const MyComposition = () => (
  <Composition id="RefynDemo" component={RefynDemo} durationInFrames={totalFrames} fps={30} width={1920} height={1080} />
);
