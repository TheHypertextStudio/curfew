interface BlockerContext {
  taskTitle: string;
  hostname: string;
  question: string;
}

export {};

type ReviewOutcome =
  | { status: "grant" }
  | { status: "challenge"; question: string }
  | { status: "deny"; reason: string }
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
const challenge = document.querySelector<HTMLElement>("#challenge")!;
const challengeQuestion = document.querySelector<HTMLElement>("#challenge-question")!;
const challengeAnswer = document.querySelector<HTMLTextAreaElement>("#challenge-answer")!;
const submit = document.querySelector<HTMLButtonElement>("#submit")!;
const statusMessage = document.querySelector<HTMLElement>("#status")!;

const requestID = new URL(location.href).searchParams.get("request");
let firstJustification: string | null = null;
let challengeIsVisible = false;

function stop(message: string): void {
  statusMessage.textContent = message;
  statusMessage.dataset.tone = "blocked";
  justification.disabled = true;
  challengeAnswer.disabled = true;
  submit.disabled = true;
}

async function load(): Promise<void> {
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
  question.textContent = response.question;
  justification.focus();
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  if (requestID === null) {
    return;
  }
  const plan = (firstJustification ?? justification.value).trim();
  const followUp = challengeIsVisible ? challengeAnswer.value.trim() : undefined;
  if (plan.length === 0 || (challengeIsVisible && followUp?.length === 0)) {
    return;
  }
  submit.disabled = true;
  statusMessage.textContent = "Curfew is checking this request.";
  statusMessage.dataset.tone = "working";
  void chromeAPI.runtime.sendMessage({
    type: "review_destination",
    requestID,
    justification: plan,
    ...(followUp === undefined ? {} : { challengeAnswer: followUp }),
  }).then((value) => {
    const outcome = value as ReviewOutcome;
    if (outcome.status === "grant") {
      statusMessage.textContent = "Access granted. Returning to the destination.";
      return;
    }
    if (outcome.status === "challenge") {
      firstJustification = plan;
      challengeIsVisible = true;
      justification.readOnly = true;
      challenge.hidden = false;
      challengeQuestion.textContent = outcome.question;
      submit.textContent = "Answer once";
      submit.disabled = false;
      statusMessage.textContent = "Curfew needs one more specific answer.";
      challengeAnswer.focus();
      return;
    }
    if (outcome.status === "deny") {
      stop(outcome.reason);
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
