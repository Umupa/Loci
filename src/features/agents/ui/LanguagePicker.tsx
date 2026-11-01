import { useRef, useState } from "react";
import { Check, ChevronDown } from "../../../shared/ui/icons";
import { Popover } from "../../../shared/ui/Popover";
import {
  LEARNING_LANGUAGES,
  learningLanguageLabel,
  useLearningLanguage,
  type LearningLanguage,
} from "../model/learningLanguage";

/**
 * A mentor's language: Settings' choice (named, so it is clear what that is),
 * or one of its own.
 */
export function LanguagePicker({ value, onChange }: {
  value: LearningLanguage | undefined;
  onChange: (value: LearningLanguage | undefined) => void;
}) {
  const [open, setOpen] = useState(false);
  const anchor = useRef<HTMLButtonElement>(null);
  const [fallback] = useLearningLanguage();
  const defaultLabel = `Default (${learningLanguageLabel(fallback)})`;
  const options: { value: LearningLanguage | undefined; label: string }[] = [
    { value: undefined, label: defaultLabel },
    { value: "auto", label: learningLanguageLabel("auto") },
    ...LEARNING_LANGUAGES.map((language) => ({ value: language.id, label: language.label })),
  ];
  const shown = value === undefined ? defaultLabel : learningLanguageLabel(value);
  return <>
    <button ref={anchor} type="button" aria-haspopup="menu" aria-expanded={open} aria-label={`Language: ${shown}`}
      onClick={() => setOpen((next) => !next)}
      className="flex max-w-52 items-center gap-1.5 rounded-md border border-content/10 bg-content/5 px-2 py-1 text-[12px] text-content hover:border-content/20">
      <span className="min-w-0 truncate">{shown}</span>
      <ChevronDown className="size-3.5 shrink-0 text-content/50" />
    </button>
    {open ? <Popover anchor={anchor} side="bottom" align="end" width={208} role="menu" aria-label="Language" onDismiss={() => setOpen(false)} className="p-1 font-sans">
      {options.map((option) => <button key={option.value ?? "default"} type="button" role="menuitemradio" aria-checked={option.value === value}
        onClick={() => { setOpen(false); onChange(option.value); }}
        className="flex h-8 w-full items-center gap-2 rounded-md px-2 text-left text-[13px] text-content hover:bg-content/6">
        <span className="min-w-0 flex-1 truncate">{option.label}</span>
        {option.value === value ? <Check className="size-3.5 shrink-0" /> : null}
      </button>)}
    </Popover> : null}
  </>;
}
