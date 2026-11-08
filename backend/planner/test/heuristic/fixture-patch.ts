import { deepClone, isDict, type J } from "../../src/heuristic/core.ts";

const UNSAFE_KEYS = new Set(["__proto__", "constructor", "prototype"]);

function unsafePath(path: string): never {
  throw new Error(`Unsafe patch path: ${path}`);
}

function pointer(path: string): string[] {
  if (typeof path !== "string" || !path.startsWith("/")) unsafePath(path);
  return path.slice(1).split("/").map((part) => {
    if (/~(?![01])/.test(part)) unsafePath(path);
    const token = part.replaceAll("~1", "/").replaceAll("~0", "~");
    if (UNSAFE_KEYS.has(token)) unsafePath(path);
    return token;
  });
}

function arrayIndex(token: string, length: number, add: boolean, path: string): number {
  if (add && token === "-") return length;
  const index = Number(token);
  if (!/^(0|[1-9][0-9]*)$/.test(token) || !Number.isSafeInteger(index) || index > (add ? length : length - 1)) {
    unsafePath(path);
  }
  return index;
}

/** Apply the fixture's replace/add/remove subset to a deep copy, never traversing inherited properties. */
export function applyPatch(document: J, operations: J[]): J {
  const doc = deepClone(document);
  for (const op of operations) {
    const tokens = pointer(op.path);
    let parent = doc;
    for (const token of tokens.slice(0, -1)) {
      if (!Array.isArray(parent) && !isDict(parent)) unsafePath(op.path);
      const key = Array.isArray(parent) ? arrayIndex(token, parent.length, false, op.path) : token;
      if (!Object.hasOwn(parent, key)) unsafePath(op.path);
      parent = Array.isArray(parent) ? parent[key as number] : parent[key];
    }
    const last = tokens[tokens.length - 1];
    if (op.op !== "add" && op.op !== "replace" && op.op !== "remove") throw new Error(`unsupported patch op ${op.op}`);
    if (Array.isArray(parent)) {
      const index = arrayIndex(last, parent.length, op.op === "add", op.path);
      if (op.op === "add") parent.splice(index, 0, deepClone(op.value));
      else if (op.op === "remove") parent.splice(index, 1);
      else parent[index] = deepClone(op.value);
    } else {
      if (!isDict(parent) || (op.op !== "add" && !Object.hasOwn(parent, last))) unsafePath(op.path);
      if (op.op === "remove") delete parent[last];
      else Object.defineProperty(parent, last, { value: deepClone(op.value), enumerable: true, writable: true, configurable: true });
    }
  }
  return doc;
}
