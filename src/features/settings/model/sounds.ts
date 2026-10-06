import { play, setEnabled, setVolume, type SoundName } from "cuelume";
import {
  allowsProjectNotification,
  type NotificationSubject,
} from "../../notifications/model/notificationPreferences";

const KEY = "loci.sounds";
const ENABLED_AT_KEY = "loci.soundsEnabledAt";

export const SOUNDS_DEFAULT = true;

/** Soft enough to sit in the background while a turn runs in another app. */
export const SOUNDS_VOLUME = 0.55;

export const SOUNDS_CHANGE_EVENT = "loci:sounds-change";

export type SoundCue =
  | "turnFinished"
  | "switch"
  | "copy";

const CUES: Record<SoundCue, SoundName> = {
  turnFinished: "success",
  switch: "toggle",
  copy: "scan",
};

export function loadSoundsEnabled(): boolean {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw == null) return SOUNDS_DEFAULT;
    return raw === "1" || raw === "true";
  } catch {
    return SOUNDS_DEFAULT;
  }
}

export function saveSoundsEnabled(value: boolean) {
  const resuming = value && !loadSoundsEnabled();
  try {
    localStorage.setItem(KEY, value ? "1" : "0");
    if (resuming) localStorage.setItem(ENABLED_AT_KEY, String(Date.now()));
  } catch {
    // private mode / quota
  }
  applySoundEngine();
  if (typeof window === "undefined") return;
  window.dispatchEvent(
    new CustomEvent<boolean>(SOUNDS_CHANGE_EVENT, { detail: value }),
  );
}

function applySoundEngine() {
  setEnabled(loadSoundsEnabled());
  setVolume(SOUNDS_VOLUME);
}

/** Apply the stored mute/volume before the first cue. */
export function initSounds() {
  applySoundEngine();
}

type ProjectSoundCue = "turnFinished";

/** Project cues require their subject so new sources cannot bypass project policy. */
export function playCue(cue: Exclude<SoundCue, ProjectSoundCue>): boolean;
export function playCue(
  cue: ProjectSoundCue,
  subject: NotificationSubject,
): boolean;
export function playCue(cue: SoundCue, subject?: NotificationSubject): boolean {
  if (!loadSoundsEnabled()) return false;
  if (subject && !allowsProjectNotification(subject)) return false;
  if (subject?.occurredAt !== undefined) {
    try {
      if (subject.occurredAt < Number(localStorage.getItem(ENABLED_AT_KEY)))
        return false;
    } catch {
      /* Audio can still play when storage is unavailable. */
    }
  }
  applySoundEngine();
  play(CUES[cue]);
  return true;
}
