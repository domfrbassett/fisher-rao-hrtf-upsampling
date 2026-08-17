"use strict";

const fs = require("node:fs/promises");
const path = require("node:path");

const projectRoot = path.resolve(__dirname, "..");
const publicRoot = path.join(projectRoot, "public");
const workerSource = path.join(projectRoot, "worker", "sites-worker.js");
const distRoot = path.join(projectRoot, "dist");

async function main() {
  await fs.rm(distRoot, { recursive: true, force: true });
  await fs.mkdir(path.join(distRoot, "server"), { recursive: true });
  await fs.copyFile(workerSource, path.join(distRoot, "server", "index.js"));
  console.log(`Built Sites worker package at ${distRoot}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
