import test from "node:test";
import assert from "node:assert/strict";
import {
  getNodeLabelPolicy,
  getScreenMode,
} from "../src/layout.js";

test("getScreenMode picks tiny for cramped phone-sized viewports", () => {
  assert.equal(getScreenMode({ width: 390, height: 700 }), "tiny");
  assert.equal(getScreenMode({ width: 840, height: 460 }), "tiny");
});

test("getScreenMode picks compact for tablet and narrow desktop viewports", () => {
  assert.equal(getScreenMode({ width: 820, height: 900 }), "compact");
  assert.equal(getScreenMode({ width: 1180, height: 620 }), "compact");
});

test("getScreenMode picks wide when the dashboard has room for full panels", () => {
  assert.equal(getScreenMode({ width: 1440, height: 900 }), "wide");
});

test("getNodeLabelPolicy reduces canvas label density by screen mode", () => {
  assert.deepEqual(getNodeLabelPolicy("wide"), { showSecondary: true, maxLength: 22, fontScale: 1 });
  assert.deepEqual(getNodeLabelPolicy("compact"), { showSecondary: false, maxLength: 16, fontScale: 0.92 });
  assert.deepEqual(getNodeLabelPolicy("tiny"), { showSecondary: false, maxLength: 10, fontScale: 0.82 });
});
