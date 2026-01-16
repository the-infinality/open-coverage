import { Loader2, AlertCircle } from "lucide-react"
import { useAccount, useSwitchChain, useChainId } from "wagmi"
import { supportedChains } from "@/lib/wagmi"
import { Button } from "@/components/ui/button"

type SupportedChainId = (typeof supportedChains)[number]["id"]

interface WalletRequirementProps {
  requiredChainId: number
  children: React.ReactNode
}

export function WalletRequirement({ 
  requiredChainId, 
  children 
}: WalletRequirementProps) {
  const { isConnected } = useAccount()
  const currentChainId = useChainId()
  const { switchChain, isPending: isSwitching } = useSwitchChain()

  const isWrongChain = isConnected && currentChainId !== requiredChainId
  const chainName = supportedChains.find(c => c.id === requiredChainId)?.name || `Chain ${requiredChainId}`

  if (!isConnected) {
    return (
      <div className="rounded-lg border border-yellow-500/50 bg-yellow-500/10 p-4">
        <div className="flex items-center gap-2 text-yellow-600 dark:text-yellow-500">
          <AlertCircle className="size-4" />
          <span className="text-sm font-medium">Wallet not connected</span>
        </div>
        <p className="mt-1 text-xs text-muted-foreground">
          Please connect your wallet to interact with this contract.
        </p>
      </div>
    )
  }

  if (isWrongChain) {
    return (
      <div className="rounded-lg border border-yellow-500/50 bg-yellow-500/10 p-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2 text-yellow-600 dark:text-yellow-500">
            <AlertCircle className="size-4" />
            <span className="text-sm font-medium">Wrong network</span>
          </div>
          <Button
            size="sm"
            variant="outline"
            onClick={() => switchChain({ chainId: requiredChainId as SupportedChainId })}
            disabled={isSwitching}
          >
            {isSwitching ? (
              <>
                <Loader2 className="mr-2 size-3 animate-spin" />
                Switching...
              </>
            ) : (
              `Switch to ${chainName}`
            )}
          </Button>
        </div>
        <p className="mt-1 text-xs text-muted-foreground">
          Please switch to {chainName} to interact with this contract.
        </p>
      </div>
    )
  }

  return <>{children}</>
}

