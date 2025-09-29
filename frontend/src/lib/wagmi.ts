import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { sepolia } from "wagmi/chains";

export const config = getDefaultConfig({
  appName: "Honey Protocol",
  projectId: process.env.NEXT_PUBLIC_WC_PROJECT_ID ?? "dummy_project_id_replace_me",
  chains: [sepolia],
  ssr: true,
});
