import { AbsoluteFill, Composition, Sequence } from "remotion";

import { ChatScene } from "./ChatScene";
import { MacScene } from "./MacScene";
import { colors } from "./theme";
import { EndCard, Problem, Statements } from "./TextScenes";
import { scenes, totalFrames } from "./timeline";

const RefynDemo: React.FC = () => (
  <AbsoluteFill style={{ background: colors.black }}>
    <Sequence name="Chat app" from={scenes.chat.from} durationInFrames={scenes.chat.duration}>
      <ChatScene />
    </Sequence>
    <Sequence name="The problem" from={scenes.problem.from} durationInFrames={scenes.problem.duration}>
      <Problem />
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
