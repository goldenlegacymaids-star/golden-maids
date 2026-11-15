import { describe, expect, it } from "vitest";

import { friendlyError } from "./errors";

describe("friendlyError", () => {
  it("explains common sign-in and access errors", () => {
    expect(friendlyError({ code: "invalid_credentials" })).toBe("Incorrect email or password.");
    expect(friendlyError({ code: "42501" })).toBe("Your role is not allowed to do this.");
    expect(friendlyError({ message: "TypeError: Failed to fetch" })).toMatch(/internet/);
  });

  it("never shows raw technical messages", () => {
    expect(friendlyError({ message: 'relation "x" does not exist', code: "42P01" })).toBe(
      "Something went wrong. Please try again.",
    );
    expect(friendlyError(null)).toBe("Something went wrong. Please try again.");
  });
});
