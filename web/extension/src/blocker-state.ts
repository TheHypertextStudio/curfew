export interface BlockerPromptContext {
  question: string;
  challengeQuestion?: string;
}

export interface BlockerDisplayContext extends BlockerPromptContext {
  taskTitle: string;
  hostname: string;
}

export const invalidJustificationMessage =
  "Justification must contain 20 to 1,000 characters.";
export const invalidChallengeAnswerMessage =
  "Challenge answer must contain 1 to 1,000 characters.";

const answerLimitBytes = 8_192;
const maximumAnswerCharacters = 1_000;
const textEncoder = new TextEncoder();

export function blockerPrompt(context: BlockerPromptContext): {
  question: string;
  isChallenge: boolean;
} {
  if (context.challengeQuestion !== undefined) {
    return { question: context.challengeQuestion, isChallenge: true };
  }
  return { question: context.question, isChallenge: false };
}

export function developmentBlockerFixture(href: string): BlockerDisplayContext | null {
  const url = new URL(href);
  if (url.searchParams.get("curfew-demo") !== "1") {
    return null;
  }
  return {
    taskTitle: "Complete LVBT social strategy",
    hostname: "instagram.com",
    question:
      "What will you do on instagram.com, and what will you produce for Complete LVBT social strategy?",
  };
}

export function buildReviewMessage(
  requestID: string,
  rawAnswer: string,
  isChallenge: boolean,
): Record<string, unknown> | null {
  const answer = rawAnswer.trim();
  const minimumCharacters = isChallenge ? 1 : 20;
  if (answer.length < minimumCharacters || answer.length > maximumAnswerCharacters ||
      textEncoder.encode(answer).byteLength > answerLimitBytes) {
    return null;
  }
  return {
    type: "review_destination",
    requestID,
    ...(isChallenge ? { challengeAnswer: answer } : { justification: answer }),
  };
}
