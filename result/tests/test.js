const { io } = require("socket.io-client");

const VOTE_URL = process.env.VOTE_URL || "http://vote:8000";
const RESULT_URL = process.env.RESULT_URL || "http://result:8000";
const TIMEOUT_MS = Number(process.env.TIMEOUT_MS || 90000);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Poll the vote service until it answers
async function waitForVote() {
  const deadline = Date.now() + TIMEOUT_MS;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(VOTE_URL);
      if (res.ok) return;
    } catch (_) {
      // not up yet
    }
    await sleep(1000);
  }
  throw new Error("vote service did not become ready in time");
}

// The scores payload is a JSON string like {"a": 1, "b": 2}
function total(payload) {
  const data = typeof payload === "string" ? JSON.parse(payload) : payload;
  return (Number(data.a) || 0) + (Number(data.b) || 0);
}

async function main() {
  await waitForVote();
  console.log("vote service is up");

  await new Promise((resolve, reject) => {
    const socket = io(RESULT_URL);
    let baseline = null;

    const fail = (err) => {
      clearTimeout(timer);
      socket.close();
      reject(err);
    };

    const timer = setTimeout(
      () => fail(new Error(`vote did not appear in results within ${TIMEOUT_MS / 1000}s`)),
      TIMEOUT_MS
    );

    socket.on("connect_error", (err) =>
      console.log(`waiting for result service: ${err.message}`)
    );

    socket.on("scores", async (payload) => {
      try {
        const current = total(payload);

        // First scores event: remember the starting total, then cast a vote
        if (baseline === null) {
          baseline = current;
          console.log(`starting total: ${baseline}; casting a vote for b`);
          const res = await fetch(VOTE_URL, {
            method: "POST",
            headers: { "content-type": "application/x-www-form-urlencoded" },
            body: "vote=b",
          });
          if (!res.ok) throw new Error(`vote POST returned ${res.status}`);
          return;
        }

        // Later events: pass once our vote has flowed through worker and db
        if (current >= baseline + 1) {
          console.log(`total is now ${current}`);
          clearTimeout(timer);
          socket.close();
          resolve();
        }
      } catch (err) {
        fail(err);
      }
    });
  });
}

main()
  .then(() => {
    console.log("Tests passed");
    process.exit(0);
  })
  .catch((err) => {
    console.error(`Tests failed: ${err.message}`);
    process.exit(1);
  });