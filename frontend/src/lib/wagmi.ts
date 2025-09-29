import { http, createConfig } from "wagmi";
import { foundry } from "wagmi/chains";

export const config = createConfig({
  chains: [foundry],
  transports: {
    [foundry.id]: http("http://127.0.0.1:8545"),
  },
});
