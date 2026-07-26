const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2);
const valueAfter = (name, fallback = "") => {
  const index = args.indexOf(name);
  return index >= 0 && index + 1 < args.length ? args[index + 1] : fallback;
};

if (args.includes("--version")) {
  console.log("comfy-cli version 1.12.0");
  process.exit(0);
}

if (args.includes("run")) {
  const workflow = path.basename(valueAfter("--workflow"));
  if (workflow.startsWith("timeout")) {
    setTimeout(() => {}, 5000);
    return;
  }
  if (workflow.startsWith("malformed")) {
    process.stdout.write("{ malformed");
    process.exit(0);
  }
  if (workflow.startsWith("failed")) {
    console.log(JSON.stringify({ schema: "envelope/1", ok: false, error: { code: "fixture_failure" } }));
    process.exit(1);
  }
  const promptId = workflow.startsWith("missing-output") ? "missing-output"
    : workflow.startsWith("malformed-download") ? "malformed-download"
      : workflow.startsWith("node-error") ? "node-error" : "success";
  console.log(JSON.stringify({
    schema: "envelope/1",
    ok: true,
    data: {
      status: "completed",
      prompt_id: promptId,
      node_errors: promptId === "node-error" ? { "7": { errors: [{ message: "fixture node error" }] } } : {}
    }
  }));
  process.exit(0);
}

if (args.includes("download")) {
  const promptId = args[args.indexOf("download") + 1];
  const outputDir = valueAfter("--out-dir");
  if (promptId === "malformed-download") {
    process.stdout.write("not json");
    process.exit(0);
  }
  fs.mkdirSync(outputDir, { recursive: true });
  if (promptId !== "missing-output") fs.writeFileSync(path.join(outputDir, "candidate.bin"), "fixture generated media\n");
  console.log(JSON.stringify({ schema: "envelope/1", ok: true, data: { prompt_id: promptId } }));
  process.exit(0);
}

console.log(JSON.stringify({ schema: "envelope/1", ok: true, data: {} }));
