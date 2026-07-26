#!/usr/bin/env node
'use strict';

const assert = require('assert');
const { assertPublishable, compareStable } = require('./check-release-version');

assert.strictEqual(compareStable('1.2.0', '1.1.2'), 1);
assert.strictEqual(compareStable('1.1.2', '1.1.2'), 0);
assert.strictEqual(compareStable('1.1.1', '1.1.2'), -1);
assert.doesNotThrow(() => assertPublishable('1.2.0', '1.1.2', ['1.1.1', '1.1.2']));
assert.throws(
  () => assertPublishable('1.1.2', '1.1.2', ['1.1.1', '1.1.2']),
  /already published/,
);
assert.throws(
  () => assertPublishable('1.1.1', '1.1.2', ['1.1.1', '1.1.2']),
  /already published/,
);
assert.throws(
  () => assertPublishable('1.1.3', '1.2.0', ['1.1.2', '1.2.0']),
  /must be greater/,
);
assert.throws(
  () => assertPublishable('next', '1.1.2', ['1.1.2']),
  /stable x\.y\.z/,
);
assert.throws(
  () => assertPublishable('1.2.0', '1.1.2', '1.1.2'),
  /JSON array/,
);

console.log('PASS: release candidate must be new and greater than npm latest');
