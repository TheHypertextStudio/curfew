import { describe, expect, it } from "vitest";

import {
  blockerPrompt,
  buildReviewMessage,
  developmentBlockerFixture,
} from "../src/blocker-state";

describe("blocker state", () => {
  it("restores the targeted challenge after a blocker-page reload", () => {
    expect(blockerPrompt({
      question: "What will you do here?",
      challengeQuestion: "Which release section do you need?",
    })).toEqual({
      question: "Which release section do you need?",
      isChallenge: true,
    });
  });

  it("submits a reloaded challenge answer without restarting the initial review", () => {
    expect(buildReviewMessage("request-1", "The packaging section.", true)).toEqual({
      type: "review_destination",
      requestID: "request-1",
      justification: "The packaging section.",
      challengeAnswer: "The packaging section.",
    });
  });

  it("rejects answers over 8,192 UTF-8 bytes in the blocker page", () => {
    expect(buildReviewMessage("request-1", "é".repeat(4_096), false)).toMatchObject({
      justification: "é".repeat(4_096),
    });
    expect(buildReviewMessage("request-1", "é".repeat(4_097), false)).toBeNull();
  });

  it("exposes the screenshot state only in an explicit development fixture", () => {
    const href = "chrome-extension://curfew/blocker.html?curfew-demo=1";

    expect(developmentBlockerFixture(href)).toEqual({
      taskTitle: "Complete LVBT social strategy",
      hostname: "instagram.com",
      question:
        "What will you do on instagram.com, and what will you produce for Complete LVBT social strategy?",
    });
    expect(developmentBlockerFixture("chrome-extension://curfew/blocker.html")).toBeNull();
  });
});
