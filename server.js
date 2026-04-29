import { createTailopsServer } from "./src/server.js";

const host = process.env.HOST || "0.0.0.0";
const port = Number(process.env.PORT || 4173);
const server = createTailopsServer();

server.listen(port, host, () => {
  console.log(`TailOps Monitor available on http://${host}:${port}`);
  console.log("Agent phonebook available at /api/agents");
});
