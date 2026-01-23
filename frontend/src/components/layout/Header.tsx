import { useAccount, useConnect, useDisconnect, useChainId } from "wagmi"
import { Button } from "@/components/ui/button"
import { CopyableAddress } from "@/components/ui/copyable-address"
import { ChainBadge } from "@/components/ui/chain-badge"
import { SidebarTrigger } from "@/components/ui/sidebar"

export function Header() {
    const { address, isConnected } = useAccount()
    const { connect, connectors } = useConnect()
    const { disconnect } = useDisconnect()
    const chainId = useChainId()

    return (
        <header className="flex h-16 items-center justify-between border-b bg-background px-6 sticky top-0 z-10">
            <div className="flex items-center gap-4">
                <div className="md:hidden">
                    <SidebarTrigger />
                </div>
            </div>

            <div className="flex items-center gap-4">
                {isConnected && <ChainBadge chainId={chainId} size="md" />}
                {isConnected ? (
                    <div className="flex items-center gap-2">
                        <CopyableAddress
                            address={address!}
                            variant="inline"
                            size="sm"
                            className="text-muted-foreground hidden md:block"
                        />
                        <Button variant="outline" size="lg" onClick={() => disconnect()}>
                            Disconnect
                        </Button>
                    </div>
                ) : (
                    <Button onClick={() => connect({ connector: connectors[0] })} size="lg">
                        Connect Wallet
                    </Button>
                )}
            </div>
        </header>
    )
}
