import { describe, expect, test } from "bun:test";
import { destinationForKey, digitOf, type KeyEventLike, type Shortcut } from "./shortcuts";

const moves: Shortcut[] = [
  { key: "1", destination: "pn:north" },
  { key: "2", destination: "pn:east" },
  { key: "0", destination: "pn:tenth" },
  { key: null, destination: "pn:eleventh" },
];
const idle = { idle: true, modalOpen: false };

function press(code: string, overrides: Partial<KeyEventLike> = {}): KeyEventLike {
  return {
    code, key: code.replace(/^(Digit|Numpad)/, ""), repeat: false, ctrlKey: false, altKey: false,
    metaKey: false, shiftKey: false, defaultPrevented: false, target: { tagName: "BODY" }, ...overrides,
  };
}

describe("digitOf", () => {
  test("reads the top row by code, even when the layout types symbols", () => {
    expect(digitOf({ code: "Digit1", key: "&" })).toBe("1");
    expect(digitOf({ code: "Digit0", key: "0" })).toBe("0");
  });
  test("accepts numpad digits only with Num Lock on", () => {
    expect(digitOf({ code: "Numpad3", key: "3" })).toBe("3");
    expect(digitOf({ code: "Numpad3", key: "PageDown" })).toBeNull();
  });
  test("ignores everything else", () => {
    expect(digitOf({ code: "KeyA", key: "a" })).toBeNull();
    expect(digitOf({ code: "Enter", key: "Enter" })).toBeNull();
  });
});

describe("destinationForKey", () => {
  test("maps digits to the displayed destination, including 0 and the numpad", () => {
    expect(destinationForKey(press("Digit1"), moves, idle)).toBe("pn:north");
    expect(destinationForKey(press("Numpad2"), moves, idle)).toBe("pn:east");
    expect(destinationForKey(press("Digit0"), moves, idle)).toBe("pn:tenth");
  });
  test("a digit with no displayed move does nothing", () => {
    expect(destinationForKey(press("Digit7"), moves, idle)).toBeNull();
  });
  test("a move beyond the tenth has no shortcut", () => {
    expect(moves.filter(m => m.key === null)).toHaveLength(1);
    expect(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].map(d => destinationForKey(press(`Digit${d}`), moves, idle))).not.toContain("pn:eleventh");
  });
  test("ignores held-key repeats", () => {
    expect(destinationForKey(press("Digit1", { repeat: true }), moves, idle)).toBeNull();
  });
  test("leaves browser and assistive shortcuts alone", () => {
    for (const mod of ["ctrlKey", "altKey", "metaKey", "shiftKey"] as const) {
      expect(destinationForKey(press("Digit1", { [mod]: true }), moves, idle)).toBeNull();
    }
    expect(destinationForKey(press("Digit1", { defaultPrevented: true }), moves, idle)).toBeNull();
    expect(destinationForKey(press("Digit1", { isComposing: true }), moves, idle)).toBeNull();
  });
  test("never fires while typing", () => {
    for (const tagName of ["INPUT", "TEXTAREA", "SELECT", "input"]) {
      expect(destinationForKey(press("Digit1", { target: { tagName } }), moves, idle)).toBeNull();
    }
    expect(destinationForKey(press("Digit1", { target: { tagName: "DIV", isContentEditable: true } }), moves, idle)).toBeNull();
  });
  test("waits while busy or when a dialog is open", () => {
    expect(destinationForKey(press("Digit1"), moves, { idle: false, modalOpen: false })).toBeNull();
    expect(destinationForKey(press("Digit1"), moves, { idle: true, modalOpen: true })).toBeNull();
  });
});
