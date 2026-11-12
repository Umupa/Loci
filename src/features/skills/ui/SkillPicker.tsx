import { useUiText } from "../../../shared/i18n/SettingsLanguage";
import {
  useEffect,
  useRef,
  type MouseEvent as ReactMouseEvent,
} from "react";
import type { Skill } from "../model/skills";
import { useLockOverscroll } from "../../../shared/hooks/useLockOverscroll";

type Props = {
  skills: Skill[];
  query: string;
  active: number;
  compact?: boolean;
  onActive: (index: number) => void;
  onPick: (skill: Skill) => void;
};

/** The composer's slash menu: Loci's own commands and the provider's native ones. */
export function SkillPicker({
  skills,
  query,
  active,
  compact = false,
  onActive,
  onPick,
}: Props) {
  return (
    <div
      data-skill-picker
      className={
        compact
          ? "overflow-hidden"
          : "overflow-hidden rounded-lg border border-content/10 bg-content/5 backdrop-blur-xl"
      }
    >
      <SkillList
        skills={skills}
        query={query}
        active={active}
        compact={compact}
        onActive={onActive}
        onPick={onPick}
      />
    </div>
  );
}

function SkillList({
  skills,
  query,
  active,
  compact,
  onActive,
  onPick,
}: {
  skills: Skill[];
  query: string;
  active: number;
  compact?: boolean;
  onActive: (index: number) => void;
  onPick: (skill: Skill) => void;
}) {
  const { t } = useUiText();
  const lockOverscroll = useLockOverscroll<HTMLDivElement>();
  const activeRef = useRef<HTMLButtonElement>(null);
  const pointer = useRef({ x: Number.NaN, y: Number.NaN, allow: false });
  const fromPointer = useRef(false);

  useEffect(() => {
    pointer.current.allow = false;
  }, [skills]);

  useEffect(() => {
    if (fromPointer.current) {
      fromPointer.current = false;
      return;
    }
    pointer.current.allow = false;
    activeRef.current?.scrollIntoView({ block: "nearest" });
  }, [active]);

  const onListMouseMove = (e: ReactMouseEvent<HTMLDivElement>) => {
    if (e.clientX === pointer.current.x && e.clientY === pointer.current.y) {
      return;
    }
    pointer.current = { x: e.clientX, y: e.clientY, allow: true };
  };

  const onRowEnter = (index: number) => {
    if (!pointer.current.allow) return;
    fromPointer.current = true;
    onActive(index);
  };

  if (skills.length === 0) {
    return (
      <p className="px-3 py-2.5 text-[12px] text-content/50">
        {query.trim() ? t("No matching commands") : t("No commands yet")}
      </p>
    );
  }

  return (
    <div
      ref={lockOverscroll}
      role="listbox"
      aria-label={t("Commands")}
      onMouseMove={onListMouseMove}
      className={`${compact ? "max-h-48" : "max-h-[min(240px,40vh)]"} overflow-y-auto overscroll-none px-1 py-1`}
    >
      {skills.map((skill, index) => {
        const highlighted = index === active;
        return (
          <button
            key={`${skill.kind}:${skill.source}:${skill.invocation}`}
            ref={highlighted ? activeRef : undefined}
            type="button"
            role="option"
            aria-selected={highlighted}
            onMouseDown={(e) => e.preventDefault()}
            onMouseEnter={() => onRowEnter(index)}
            onClick={() => onPick(skill)}
            className={`flex w-full rounded-md px-2 text-left ${
              compact ? "h-8 items-center" : "flex-col gap-0.5 py-1.5"
            } ${
              highlighted ? "bg-content/10 text-content" : "text-content"
            }`}
          >
            <span className="flex min-w-0 w-full items-baseline gap-2">
              <span className="truncate text-[13px]">
                /{skill.invocation}
              </span>
              <span className="shrink-0 text-[11px] text-content/40">
                {scopeLabel(skill)}
              </span>
            </span>
            {!compact && skill.description ? (
              <span className="line-clamp-2 text-[11px] leading-4 text-content/50">
                {skill.description}
              </span>
            ) : null}
            {!compact && skill.kind === "native" && (skill.inputHint || skill.subcommands?.length) ? (
              <span className="line-clamp-2 text-[11px] text-content/40">
                {skill.inputHint || skill.subcommands?.map((sub) => sub.usage || sub.name).join(" · ")}
              </span>
            ) : null}
          </button>
        );
      })}
    </div>
  );
}

function scopeLabel(skill: Skill): string {
  if (skill.kind === "native") {
    return skill.origin ? `${skill.source} · ${skill.origin}` : skill.source;
  }
  return "loci";
}
