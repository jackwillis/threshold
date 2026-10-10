// Keyboard shortcuts for the player's movement choices. Pure logic only: the hook supplies the
// event and the current moves; this decides whether a keypress should request a move and which
// one. The server still validates every move, so a wrong guess here can only be refused.

export type Shortcut = { key: string | null; destination: string };

export type KeyEventLike = {
  code: string;
  key: string;
  repeat: boolean;
  ctrlKey: boolean;
  altKey: boolean;
  metaKey: boolean;
  shiftKey: boolean;
  defaultPrevented: boolean;
  isComposing?: boolean;
  target: { tagName?: string; isContentEditable?: boolean } | null;
};

export type ShortcutContext = {
  /** The map is loaded and no walking animation or pending request is in progress. */
  idle: boolean;
  modalOpen: boolean;
};

const TYPING_TAGS = new Set(["INPUT", "TEXTAREA", "SELECT"]);

/** The digit a key event stands for, or null. Top-row digits go by `code` so layouts whose digit row types symbols still work. */
export function digitOf(event: Pick<KeyEventLike, "code" | "key">): string | null {
  const row = /^Digit([0-9])$/.exec(event.code);
  if (row) return row[1]!;
  const pad = /^Numpad([0-9])$/.exec(event.code);
  // With Num Lock off the numpad types navigation keys (End, ArrowDown, ...), not digits.
  if (pad && event.key === pad[1]) return pad[1]!;
  return null;
}

/** The destination to request for a keypress, or null when the key must be left alone. */
export function destinationForKey(event: KeyEventLike, moves: Shortcut[], context: ShortcutContext): string | null {
  const digit = digitOf(event);
  if (digit === null) return null;
  if (event.defaultPrevented || event.repeat || event.isComposing) return null;
  if (event.ctrlKey || event.altKey || event.metaKey || event.shiftKey) return null;
  if (!context.idle || context.modalOpen) return null;
  const target = event.target;
  if (target && (target.isContentEditable || (target.tagName && TYPING_TAGS.has(target.tagName.toUpperCase())))) return null;
  return moves.find(move => move.key === digit)?.destination ?? null;
}
