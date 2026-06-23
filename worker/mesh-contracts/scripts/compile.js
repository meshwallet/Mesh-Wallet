import solc from "solc";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, "..");
const sourcePath = path.join(root, "contracts", "MeshSendRouter.sol");
const source = fs.readFileSync(sourcePath, "utf8");

const input = {
  language: "Solidity",
  sources: { "MeshSendRouter.sol": { content: source } },
  settings: {
    optimizer: { enabled: true, runs: 200 },
    outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } },
  },
};

const output = JSON.parse(solc.compile(JSON.stringify(input)));
const errors = (output.errors || []).filter((e) => e.severity === "error");
if (errors.length) {
  console.error(errors.map((e) => e.formattedMessage).join("\n"));
  process.exit(1);
}

const contract = output.contracts["MeshSendRouter.sol"].MeshSendRouter;
const outDir = path.join(root, "build");
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, "MeshSendRouter.json"), JSON.stringify(contract, null, 2));
console.log("Wrote build/MeshSendRouter.json");
