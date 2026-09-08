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
      challengeAnswer: "The packaging section.",
    });
  });

  it("uses Docket's UTF-16 character limits for an initial justification", () => {
    expect(buildReviewMessage("request-1", "😀".repeat(10), false)).toMatchObject({
      justification: "😀".repeat(10),
    });
    expect(buildReviewMessage("request-1", "short", false)).toBeNull();
    expect(buildReviewMessage("request-1", "😀".repeat(500), false)).not.toBeNull();
    expect(buildReviewMessage("request-1", "😀".repeat(501), false)).toBeNull();
  });

  it("accepts one through 1,000 UTF-16 characters for a challenge answer", () => {
    expect(buildReviewMessage("request-1", "x", true)).toEqual({
      type: "review_destination",
      requestID: "request-1",
      challengeAnswer: "x",
    });
    expect(buildReviewMessage("request-1", "😀".repeat(500), true)).not.toBeNull();
    expect(buildReviewMessage("request-1", "😀".repeat(501), true)).toBeNull();
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
