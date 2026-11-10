"use strict"

// QML's `.pragma library` directive is not valid JavaScript, so the test
// runner strips it and evaluates the module in a CommonJS-shaped scope.
const fs = require("node:fs")
const path = require("node:path")

const source = fs.readFileSync(path.join(__dirname, "..", "Nyxiri.js"), "utf8")
const body = source.replace(/^\s*\.pragma\s+library\s*/, "")
const loaded = { exports: {} }
new Function("module", "exports", body)(loaded, loaded.exports)
module.exports = loaded.exports
