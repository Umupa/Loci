import { useState, type CSSProperties } from "react";
import { useTurnCelebration } from "../../sessions/ui/turnCelebration";

const CELEBRATE_MS = 3400;
const SPARKLE_COUNT = 18;
const STAR_PATH =
  "M12 0C12.9 6.6 17.4 11.1 24 12C17.4 12.9 12.9 17.4 12 24C11.1 17.4 6.6 12.9 0 12C6.6 11.1 11.1 6.6 12 0Z";
const DIAMOND_PATH = "M12 2L22 12L12 22L2 12Z";

type LearnSparkle = {
  shape: "star" | "diamond" | "dot";
  x: number;
  size: number;
  delay: number;
  duration: number;
  drift: number;
  spin: number;
};

function makeLearnSparkles(): LearnSparkle[] {
  return Array.from({ length: SPARKLE_COUNT }, (_, i) => {
    const mod = i % 3;
    const shape: LearnSparkle["shape"] =
      mod === 0 ? "star" : mod === 1 ? "diamond" : "dot";
    return {
      shape,
      x: Math.min(96, Math.max(4, ((i + Math.random()) / SPARKLE_COUNT) * 100)),
      size: shape === "dot" ? 2.5 + Math.random() * 2 : 6 + Math.random() * 6,
      delay: 100 + Math.random() * 1000,
      duration: 1400 + Math.random() * 1000,
      drift: (Math.random() - 0.5) * 32,
      spin: (Math.random() < 0.5 ? -1 : 1) * (60 + Math.random() * 150),
    };
  }).sort(() => Math.random() - 0.5);
}

/** A one-shot burst of rising sparkles inside a freshly sent /learn bubble. */
export function LearnSparkles({
  blockId,
  startedAt,
}: {
  blockId: string;
  startedAt?: number;
}) {
  const active = useTurnCelebration(blockId, startedAt, CELEBRATE_MS);
  const [sparkles] = useState(makeLearnSparkles);

  if (!active) return null;
  return (
    <span aria-hidden className="learn-sparkles">
      {sparkles.map((sparkle, index) => (
        <span
          key={index}
          className="learn-sparkle"
          style={
            {
              "--x": `${sparkle.x}%`,
              "--size": `${sparkle.size}px`,
              "--delay": `${sparkle.delay}ms`,
              "--duration": `${sparkle.duration}ms`,
              "--drift": `${sparkle.drift}px`,
              "--spin": `${sparkle.spin}deg`,
            } as CSSProperties
          }
        >
          {sparkle.shape === "star" ? (
            <svg viewBox="0 0 24 24" className="learn-sparkle-glyph">
              <path d={STAR_PATH} fill="currentColor" />
            </svg>
          ) : sparkle.shape === "diamond" ? (
            <svg viewBox="0 0 24 24" className="learn-sparkle-glyph">
              <path d={DIAMOND_PATH} fill="currentColor" />
            </svg>
          ) : (
            <span className="learn-sparkle-glyph learn-sparkle-ember" />
          )}
        </span>
      ))}
    </span>
  );
}
