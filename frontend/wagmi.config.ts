import { defineConfig } from "@wagmi/cli"
import { foundry } from "@wagmi/cli/plugins"

export default defineConfig({
    out: "src/generated/abis.ts",
    contracts: [],
    plugins: [
        foundry({
            project: "..",
            include: [
                "ICoverageAgent.sol/ICoverageAgent.json",
                "ICoverageProvider.sol/ICoverageProvider.json",
                "IEigenServiceManager.sol/IEigenServiceManager.json",
                "IAssetPriceOracleAndSwapper.sol/IAssetPriceOracleAndSwapper.json",
                "IEigenOperatorProxy.sol/IEigenOperatorProxy.json",
                "IDiamondOwner.sol/IDiamondOwner.json",
            ],
        }),
    ],
})
