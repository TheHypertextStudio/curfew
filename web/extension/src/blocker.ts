import {
  blockerPrompt,
  buildReviewMessage,
  developmentBlockerFixture,
  invalidChallengeAnswerMessage,
  invalidJustificationMessage,
} from "./blocker-state";

interface BlockerContext {
  taskTitle: string;
  hostname: string;
  question: string;
  challengeQuestion?: string;
}

export {};

type ReviewOutcome =
  | { status: "grant" }
  | { status: "challenge"; question: string }
  | { status: "deny"; reason: string }
  | { status: "invalid_answer"; reason: string }
  | { status: "stale_session" | "host_failure" | "expired" };

interface BlockerChromeAPI {
  runtime: {
    sendMessage(message: Record<string, unknown>): Promise<unknown>;
  };
}

const chromeAPI = chrome as BlockerChromeAPI;
const task = document.querySelector<HTMLElement>("#task-title")!;
const host = document.querySelector<HTMLElement>("#target-host")!;
const question = document.querySelector<HTMLElement>("#question")!;
const form = document.querySelector<HTMLFormElement>("#review-form")!;
const justification = document.querySelector<HTMLTextAreaElement>("#justification")!;
const submit = document.querySelector<HTMLButtonElement>("#submit")!;
const statusMessage = document.querySelector<HTMLElement>("#status")!;

const requestID = new URL(location.href).searchParams.get("request");
const demoContext = __CURFEW_BLOCKER_DEMO__
  ? developmentBlockerFixture(location.href)
  : null;
let challengeIsVisible = false;

function stop(message: string): void {
  statusMessage.textContent = message;
  statusMessage.dataset.tone = "blocked";
  justification.disabled = true;
  submit.disabled = true;
}

async function load(): Promise<void> {
  if (demoContext !== null) {
    task.textContent = demoContext.taskTitle;
    host.textContent = demoContext.hostname;
    question.textContent = demoContext.question;
    statusMessage.textContent = "Development fixture. Curfew will not send or save an answer.";
    justification.focus();
    return;
  }
  if (requestID === null) {
    stop("This blocked request is missing its private request ID.");
    return;
  }
  const response = await chromeAPI.runtime.sendMessage({
    type: "get_blocker_context",
    requestID,
  }) as BlockerContext | null;
  if (response === null) {
    stop("This request expired. Return to the task before opening another destination.");
    return;
  }
  task.textContent = response.taskTitle;
  host.textContent = response.hostname;
  const prompt = blockerPrompt(response);
  question.textContent = prompt.question;
  challengeIsVisible = prompt.isChallenge;
  if (prompt.isChallenge) {
    submit.textContent = "Answer once";
  }
  justification.focus();
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  if (demoContext !== null) {
    statusMessage.textContent = "Development fixture. Curfew did not send or save this answer.";
    return;
  }
  if (requestID === null) {
    return;
  }
  const message = buildReviewMessage(requestID, justification.value, challengeIsVisible);
  if (message === null) {
    statusMessage.textContent = challengeIsVisible
      ? invalidChallengeAnswerMessage
      : invalidJustificationMessage;
    statusMessage.dataset.tone = "blocked";
    return;
  }
  submit.disabled = true;
  statusMessage.textContent = "Curfew is checking this request.";
  statusMessage.dataset.tone = "working";
  void chromeAPI.runtime.sendMessage(message).then((value) => {
    const outcome = value as ReviewOutcome;
    if (outcome.status === "grant") {
      statusMessage.textContent = "Access granted. Returning to the destination.";
      return;
    }
    if (outcome.status === "challenge") {
      challengeIsVisible = true;
      question.textContent = outcome.question;
      justification.value = "";
      submit.textContent = "Answer once";
      submit.disabled = false;
      statusMessage.textContent = "Curfew needs one more specific answer.";
      justification.focus();
      return;
    }
    if (outcome.status === "deny") {
      stop(outcome.reason);
      return;
    }
    if (outcome.status === "invalid_answer") {
      statusMessage.textContent = outcome.reason;
      statusMessage.dataset.tone = "blocked";
      submit.disabled = false;
      return;
    }
    if (outcome.status === "stale_session") {
      stop("The active task changed. This request cannot carry over to the new task.");
      return;
    }
    if (outcome.status === "expired") {
      stop("This request expired. Return to the task before trying again.");
      return;
    }
    statusMessage.textContent = "Curfew could not reach its local host. The destination remains blocked.";
    statusMessage.dataset.tone = "blocked";
    submit.disabled = false;
  }).catch(() => {
    statusMessage.textContent = "Curfew could not reach its local host. The destination remains blocked.";
    statusMessage.dataset.tone = "blocked";
    submit.disabled = false;
  });
});

void load().catch(() => {
  stop("Curfew could not load this request. The destination remains blocked.");
});
