export interface BlockerPromptContext {
  question: string;
  challengeQuestion?: string;
}

export const invalidAnswerMessage = "Answer must be between 1 and 8,192 UTF-8 bytes.";

const answerLimitBytes = 8_192;
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

export function buildReviewMessage(
  requestID: string,
  rawAnswer: string,
  isChallenge: boolean,
): Record<string, unknown> | null {
  const answer = rawAnswer.trim();
  if (answer.length === 0 || textEncoder.encode(answer).byteLength > answerLimitBytes) {
    return null;
  }
  return {
    type: "review_destination",
    requestID,
    justification: answer,
    ...(isChallenge ? { challengeAnswer: answer } : {}),
  };
}
