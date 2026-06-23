import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { TronWeb } from "tronweb";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, "..");

const USDT = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t";
const treasury = process.env.MESH_FEE_TREASURY_ADDRESS?.trim();
const privateKey = process.env.DEPLOYER_PRIVATE_KEY?.trim()?.replace(/^0x/i, "");

if (!privateKey || !/^[0-9a-fA-F]{64}$/.test(privateKey)) {
  console.error("Set DEPLOYER_PRIVATE_KEY (64 hex)");
  process.exit(1);
}
if (!treasury) {
  console.error("Set MESH_FEE_TREASURY_ADDRESS");
  process.exit(1);
}

const artifactPath = path.join(root, "build", "MeshSendRouter.json");
if (!fs.existsSync(artifactPath)) {
  console.error("Run: npm run compile");
  process.exit(1);
}
const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
const bytecode = artifact.evm.bytecode.object;
const abi = artifact.abi;

const host = process.env.TRONGRID_HOST || "https://api.trongrid.io";
const headers = {};
if (process.env.TRONGRID_API_KEY) {
  headers["TRON-PRO-API-KEY"] = process.env.TRONGRID_API_KEY;
}

const tronWeb = new TronWeb({ fullHost: host, headers, privateKey });
const usdtHex = tronWeb.address.toHex(USDT);
const treasuryHex = tronWeb.address.toHex(treasury);

const contract = await tronWeb.contract().new({
  abi,
  bytecode,
  parameters: [usdtHex, treasuryHex],
  feeLimit: 1_000_000_000,
});

const address = tronWeb.address.fromHex(contract.address);
console.log("MeshSendRouter deployed:", address);
console.log("Add to Info.plist MESH_SEND_ROUTER_ADDRESS and wrangler secret MESH_SEND_ROUTER_ADDRESS");
