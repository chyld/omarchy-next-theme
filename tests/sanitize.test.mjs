// Exercises sanitize() from BarWidget.qml against theme names a third-party
// theme could choose. The function body is extracted from the QML file rather
// than copied, so these cases test the regexes that actually ship.
//
//   node tests/sanitize.test.mjs

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const qml = readFileSync(join(here, "..", "BarWidget.qml"), "utf8");

const match = qml.match(/function sanitize\(value\) \{(.*?)\n {2}\}/s);
if (!match) {
  console.error("could not find sanitize() in BarWidget.qml");
  process.exit(1);
}

const MAX_NAME_CHARS = 128;
const sanitize = new Function(
  "value",
  match[1].replace(/root\.maxNameChars/g, String(MAX_NAME_CHARS)),
);

const cases = [
  { input: "Tokyo Night", expected: "Tokyo Night", label: "ordinary name is untouched" },
  { input: "  Nord  ", expected: "Nord", label: "surrounding whitespace trimmed" },
  { input: "<img src=x onerror=alert(1)>", expected: "img src=x onerror=alert(1)", label: "angle brackets stripped" },
  { input: "A&B", expected: "AB", label: "ampersand stripped" },
  { input: "Evil‮gnisreveR", expected: "EvilgnisreveR", label: "bidi override stripped" },
  { input: "Bellhere", expected: "Bellhere", label: "C0 control stripped" },
  { input: "Padhere", expected: "Padhere", label: "C1 control stripped" },
  { input: "x".repeat(200), expected: "x".repeat(MAX_NAME_CHARS), label: "capped at 128 characters" },
  { input: "", expected: "", label: "empty stays empty" },
  { input: null, expected: "", label: "null becomes empty" },
];

let failures = 0;
for (const { input, expected, label } of cases) {
  const actual = sanitize(input);
  if (actual === expected) {
    console.log(`ok       ${label}`);
  } else {
    console.log(`NOT OK   ${label}\n  expected ${JSON.stringify(expected)}\n  actual   ${JSON.stringify(actual)}`);
    failures += 1;
  }
}

if (failures > 0) {
  console.error(`\n${failures} failure(s)`);
  process.exit(1);
}
console.log("\nall sanitize cases passed");
