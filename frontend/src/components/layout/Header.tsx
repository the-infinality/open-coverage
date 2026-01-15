import { useAccount, useConnect, useDisconnect, useChainId, useSwitchChain } from "wagmi"
import { Button } from "@/components/ui/button"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { CopyableAddress } from "@/components/ui/copyable-address"
import { supportedChains } from "@/lib/wagmi"

export function Header() {
  const { address, isConnected } = useAccount()
  const { connect, connectors } = useConnect()
  const { disconnect } = useDisconnect()
  const chainId = useChainId()
  const { switchChain } = useSwitchChain()

  return (
    <header className="flex h-16 items-center justify-between border-b bg-background px-6">
      <div className="flex items-center gap-4">
        <h1 className="text-lg font-semibold">Open Coverage</h1>
      </div>

      <div className="flex items-center gap-4">
        {isConnected && (
          <Select
            value={chainId.toString()}
            onValueChange={(value) => switchChain({ chainId: parseInt(value) as 1 | 11155111 | 31337 })}
          >
            <SelectTrigger className="w-40">
              <SelectValue placeholder="Select Network" />
            </SelectTrigger>
            <SelectContent>
              {supportedChains.map((chain) => (
                <SelectItem key={chain.id} value={chain.id.toString()}>
                  {chain.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        )}

        {isConnected ? (
          <div className="flex items-center gap-2">
            <CopyableAddress
              address={address!}
              variant="inline"
              size="sm"
              className="text-muted-foreground"
            />
            <Button variant="outline" size="sm" onClick={() => disconnect()}>
              Disconnect
            </Button>
          </div>
        ) : (
          <Button
            onClick={() => connect({ connector: connectors[0] })}
            size="sm"
          >
            Connect Wallet
          </Button>
        )}
      </div>
    </header>
  )
}
