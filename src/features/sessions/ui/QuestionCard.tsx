import { useEffect, useState } from "react";
import { isImeComposition } from "../../../shared/lib/keyboard";
import { Check, X } from "../../../shared/ui/icons";
import {
  buildQuestionReply,
  isOtherOption,
  questionIsComplete,
  type UserQuestion,
  type UserQuestionPrompt,
  type UserQuestionReply,
} from "../model/userQuestion";

type Props = {
  prompt: UserQuestionPrompt;
  onReply: (requestId: number, reply: UserQuestionReply) => void;
  /** The user has started answering, so a deadline the provider set no longer applies. */
  onInteraction?: (requestId: number) => void;
};

const LETTERS = "ABCDEFGHIJ";

/**
 * A question as a card in the chat, where the agent's next message would be:
 * choices to pick with one click, and a line for an answer of the user's own.
 * One question with one answer sends on the pick; anything more asks once at
 * the end, so nothing goes out half-answered.
 */
export function QuestionCard({ prompt, onReply, onInteraction }: Props) {
  const [step, setStep] = useState(0);
  const [answers, setAnswers] = useState<Record<string, string[]>>({});
  const [custom, setCustom] = useState<Record<string, string>>({});
  useEffect(() => {
    setStep(0);
    setAnswers({});
    setCustom({});
  }, [prompt.requestId]);

  const questions = prompt.questions;
  const index = Math.min(step, Math.max(questions.length - 1, 0));
  const question: UserQuestion | undefined = questions[index];
  if (!question) return null;
  const last = index >= questions.length - 1;
  const selected = answers[question.id] ?? [];
  const typed = custom[question.id] ?? "";
  // When custom answers are allowed, "Other" uses the input below.
  const options = question.options.filter((option) => !question.allowCustom || !isOtherOption(option));
  const interact = () => {
    if (prompt.autoResolveAt != null) onInteraction?.(prompt.requestId);
  };
  const advance = (nextAnswers = answers, nextCustom = custom) => {
    if (!last) {
      setStep(index + 1);
      return;
    }
    onReply(prompt.requestId, buildQuestionReply(questions, nextAnswers, nextCustom));
  };
  const pick = (optionId: string) => {
    interact();
    if (question.multiSelect) {
      setAnswers((current) => {
        const chosen = current[question.id] ?? [];
        return { ...current, [question.id]: chosen.includes(optionId) ? chosen.filter((id) => id !== optionId) : [...chosen, optionId] };
      });
      return;
    }
    const nextAnswers = { ...answers, [question.id]: [optionId] };
    const nextCustom = { ...custom, [question.id]: "" };
    setAnswers(nextAnswers);
    setCustom(nextCustom);
    advance(nextAnswers, nextCustom);
  };
  const submitTyped = () => {
    if (!typed.trim()) return;
    // An answer of their own stands in for the choices of a single-answer question.
    const nextAnswers = question.multiSelect ? answers : { ...answers, [question.id]: [] };
    setAnswers(nextAnswers);
    advance(nextAnswers, custom);
  };
  const ready = questionIsComplete(question, answers, custom);

  return (
    <div data-question-card className="mx-4 my-1.5 flex w-fit min-w-[min(100%,20rem)] max-w-[min(100%,36rem)] flex-col gap-2.5 rounded-[1.25rem] bg-content/6 p-3.5 font-sans">
      <div className="flex items-start gap-3">
        <div className="min-w-0 flex-1">
          <p className="text-[14px] leading-snug text-content">{question.prompt}</p>
          <p className="mt-0.5 text-xs text-content/45">
            {questions.length > 1 ? `${index + 1} of ${questions.length} · ` : ""}
            {question.multiSelect ? "Pick any that apply" : "Pick one"}
            {question.allowCustom ? ", or type your own." : "."}
          </p>
        </div>
        <button type="button" title="Skip" aria-label="Skip this question" onClick={() => onReply(prompt.requestId, { kind: "skipped" })}
          className="grid size-6 shrink-0 place-items-center rounded-md text-content/40 hover:bg-content/8 hover:text-content">
          <X className="size-3.5" strokeWidth={1.75} />
        </button>
      </div>

      {options.length ? (
        <div role={question.multiSelect ? "group" : "radiogroup"} aria-label={question.prompt} className="flex flex-col overflow-hidden rounded-xl border border-stroke">
          {options.map((option, position) => {
            const on = selected.includes(option.id);
            return (
              <button key={option.id} type="button" role={question.multiSelect ? "checkbox" : "radio"} aria-checked={on} onClick={() => pick(option.id)}
                className={`flex w-full items-start gap-3 border-b border-stroke px-3 py-2.5 text-left last:border-b-0 ${on ? "bg-content/10" : "hover:bg-content/6"}`}>
                <span className={`mt-px grid size-5 shrink-0 place-items-center rounded-md text-[11px] font-medium ${on ? "bg-content text-background-base" : "bg-content/10 text-content/55"}`}>
                  {on && question.multiSelect ? <Check className="size-3" strokeWidth={2.5} /> : (LETTERS[position] ?? position + 1)}
                </span>
                <span className="flex min-w-0 flex-1 flex-col">
                  <span className="text-[13px] leading-snug text-content">{option.label}</span>
                  {option.description ? <span className="text-xs leading-snug text-content/50">{option.description}</span> : null}
                </span>
              </button>
            );
          })}
        </div>
      ) : null}

      {question.allowCustom ? (
        <input aria-label="Your own answer" value={typed} placeholder="Type your own answer"
          className="w-full rounded-xl bg-background-base/60 px-3 py-2 text-[13px] text-content outline-none placeholder:text-content/35 focus:bg-background-base"
          onChange={(event) => { interact(); setCustom((current) => ({ ...current, [question.id]: event.target.value })); }}
          onKeyDown={(event) => {
            if (event.key !== "Enter" || isImeComposition(event.nativeEvent)) return;
            event.preventDefault();
            submitTyped();
          }} />
      ) : null}

      {question.multiSelect || (!last && questions.length > 1 && ready) ? (
        <div className="flex justify-end">
          <button type="button" disabled={!ready} onClick={() => advance()}
            className="primary-action rounded-lg px-3 py-1 text-xs font-medium disabled:opacity-40">
            {last ? "Send" : "Next"}
          </button>
        </div>
      ) : null}
    </div>
  );
}
