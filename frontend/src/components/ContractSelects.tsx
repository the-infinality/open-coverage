import { useMemo } from "react"
import { useAccount } from "wagmi"
import {
    Select,
    SelectContent,
    SelectItem,
    SelectTrigger,
    SelectValue,
} from "@/components/ui/select"
import type { CoverageContract } from "@/types/contracts"

/** Special ID for the "Connected Wallet" option in operator select */
export const CONNECTED_WALLET_OPERATOR_ID = "connected-wallet"

/**
 * Props for the base ContractSelect component
 */
export interface ContractSelectProps {
    /** The selected contract ID */
    selectedContractId?: string
    /** Called with the contract ID when selection changes */
    onSelectedContractIdChange: (contractId: string) => void
    /** The contracts to display in the select */
    contracts: CoverageContract[]
    /** The placeholder to display for the select */
    placeholder?: string
    /** Message to display when no contracts are available */
    emptyMessage?: React.ReactNode
    /** Whether the select is disabled */
    disabled?: boolean
}

/**
 * Base component for selecting a contract from a list
 * Renders just the select dropdown with contract name and truncated address
 */
export function ContractSelect({
    selectedContractId,
    onSelectedContractIdChange,
    contracts,
    placeholder = "Select contract...",
    emptyMessage = "No contracts available",
    disabled,
}: ContractSelectProps) {
    return (
        <Select
            value={selectedContractId}
            onValueChange={onSelectedContractIdChange}
            disabled={disabled}
        >
            <SelectTrigger className="font-mono">
                <SelectValue placeholder={placeholder} />
            </SelectTrigger>
            <SelectContent>
                {contracts.length === 0 ? (
                    <div className="px-2 py-4 text-center text-sm text-muted-foreground">
                        {emptyMessage}
                    </div>
                ) : (
                    contracts.map((c) => (
                        <SelectItem key={c.id} value={c.id} className="font-mono">
                            <div className="flex flex-col gap-0.5 items-start">
                                <div className="font-sans font-medium">{c.name}</div>
                                <div className="text-xs text-muted-foreground">
                                    {c.address.slice(0, 10)}...{c.address.slice(-8)}
                                </div>
                            </div>
                        </SelectItem>
                    ))
                )}
            </SelectContent>
        </Select>
    )
}

/**
 * Props for specialized select components
 */
type SpecializedSelectProps = Omit<ContractSelectProps, "placeholder" | "emptyMessage"> & {
    placeholder?: string
    emptyMessage?: React.ReactNode
}

/**
 * Dropdown select for choosing an EigenOperatorProxy from a list of contracts.
 * When the wallet is connected, prepends a "Connected Wallet" option with the truncated address.
 */
export function OperatorProxySelect({
    placeholder = "Select operator",
    emptyMessage = (
        <>
            No operator agents saved on this chain.
            <br />
            Add an EigenOperatorProxy contract first.
        </>
    ),
    contracts,
    ...props
}: SpecializedSelectProps) {
    const { address: connectedAddress } = useAccount()

    const contractsWithConnectedWallet = useMemo(() => {
        if (!connectedAddress) return contracts
        const youContract: CoverageContract = {
            id: CONNECTED_WALLET_OPERATOR_ID,
            name: "Connected Wallet",
            address: connectedAddress,
            type: "EigenOperatorProxy",
            chainId: 0,
            createdAt: 0,
        }
        return [youContract, ...contracts]
    }, [connectedAddress, contracts])

    return (
        <ContractSelect
            placeholder={placeholder}
            emptyMessage={emptyMessage}
            contracts={contractsWithConnectedWallet}
            {...props}
        />
    )
}

/**
 * Dropdown select for choosing a CoverageAgent from a list of contracts
 * Provides sensible defaults for placeholder and empty message
 */
export function CoverageAgentSelect({
    placeholder = "Select coverage agent...",
    emptyMessage = "No coverage agents saved on this chain",
    ...props
}: SpecializedSelectProps) {
    return <ContractSelect placeholder={placeholder} emptyMessage={emptyMessage} {...props} />
}

/**
 * Dropdown select for choosing a CoverageProvider from a list of contracts
 * Provides sensible defaults for placeholder and empty message
 */
export function CoverageProviderSelect({
    placeholder = "Select coverage provider...",
    emptyMessage = (
        <>
            No coverage providers available.
            <br />
            Add a CoverageProvider contract on the same chain first.
        </>
    ),
    ...props
}: SpecializedSelectProps) {
    return <ContractSelect placeholder={placeholder} emptyMessage={emptyMessage} {...props} />
}
