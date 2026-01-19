import {
    useChainFilteredContracts,
    useAvailableCoverageProviders,
} from "@/hooks/use-chain-filtered-contracts"
import { Label } from "@/components/ui/label"
import {
    Select,
    SelectContent,
    SelectItem,
    SelectTrigger,
    SelectValue,
} from "@/components/ui/select"

export interface OperatorProxySelectProps {
    /** The selected contract ID */
    value: string
    /** Called with the contract ID when selection changes */
    onValueChange: (contractId: string) => void
    chainId: number
    label?: string
    placeholder?: string
    description?: string
    disabled?: boolean
}

/**
 * Dropdown select for choosing an EigenOperatorProxy from saved contracts
 * Returns the contract ID as the value (use getSelectedOperatorProxy to get the full contract)
 */
export function OperatorProxySelect({
    value,
    onValueChange,
    chainId,
    label = "Operator Agent",
    placeholder = "Select operator agent...",
    description,
    disabled,
}: OperatorProxySelectProps) {
    const { operatorProxies } = useChainFilteredContracts(chainId)

    return (
        <div className="space-y-2">
            <Label>{label}</Label>
            <Select value={value} onValueChange={onValueChange} disabled={disabled}>
                <SelectTrigger className="font-mono">
                    <SelectValue placeholder={placeholder} />
                </SelectTrigger>
                <SelectContent>
                    {operatorProxies.length === 0 ? (
                        <div className="px-2 py-4 text-center text-sm text-muted-foreground">
                            No operator agents saved on this chain.
                            <br />
                            Add an EigenOperatorProxy contract first.
                        </div>
                    ) : (
                        operatorProxies.map((op) => (
                            <SelectItem key={op.id} value={op.id} className="font-mono">
                                <span className="flex flex-col gap-0.5">
                                    <span className="font-sans font-medium">{op.name}</span>
                                    <span className="text-xs text-muted-foreground">
                                        {op.address.slice(0, 10)}...{op.address.slice(-8)}
                                    </span>
                                </span>
                            </SelectItem>
                        ))
                    )}
                </SelectContent>
            </Select>
            {description && <p className="text-xs text-muted-foreground">{description}</p>}
        </div>
    )
}

export interface CoverageAgentSelectProps {
    /** The selected contract ID */
    value: string
    /** Called with the contract ID when selection changes */
    onValueChange: (contractId: string) => void
    chainId: number
    description?: string
    disabled?: boolean
}

/**
 * Dropdown select for choosing a CoverageAgent from saved contracts
 * Returns the contract ID as the value (use getSelectedCoverageAgent to get the full contract)
 */
export function CoverageAgentSelect({
    value,
    onValueChange,
    chainId,
    description,
    disabled,
}: CoverageAgentSelectProps) {
    const { coverageAgents } = useChainFilteredContracts(chainId)

    return (
        <div className="space-y-2">
            <Label>Coverage Agent</Label>
            <Select value={value} onValueChange={onValueChange} disabled={disabled}>
                <SelectTrigger className="font-mono">
                    <SelectValue placeholder="Select coverage agent..." />
                </SelectTrigger>
                <SelectContent>
                    {coverageAgents.length === 0 ? (
                        <div className="px-2 py-4 text-center text-sm text-muted-foreground">
                            No coverage agents saved on this chain
                        </div>
                    ) : (
                        coverageAgents.map((ca) => (
                            <SelectItem key={ca.id} value={ca.id} className="font-mono">
                                <span className="flex flex-col gap-0.5">
                                    <span className="font-sans font-medium">{ca.name}</span>
                                    <span className="text-xs text-muted-foreground">
                                        {ca.address.slice(0, 10)}...{ca.address.slice(-8)}
                                    </span>
                                </span>
                            </SelectItem>
                        ))
                    )}
                </SelectContent>
            </Select>
            {description && <p className="text-xs text-muted-foreground">{description}</p>}
        </div>
    )
}

export interface CoverageProviderSelectProps {
    /** The selected contract ID */
    value: string
    /** Called with the contract ID when selection changes */
    onValueChange: (contractId: string) => void
    chainId: number
    /** Contract IDs to exclude from the list (e.g., already registered providers) */
    excludeIds?: string[]
    label?: string
    placeholder?: string
    description?: string
    disabled?: boolean
}

/**
 * Dropdown select for choosing a CoverageProvider from saved contracts
 * Optionally filters out specified contract IDs (e.g., already registered providers)
 * Returns the contract ID as the value (use getSelectedProvider to get the full contract)
 */
export function CoverageProviderSelect({
    value,
    onValueChange,
    chainId,
    excludeIds = [],
    label = "Coverage Provider",
    placeholder = "Select coverage provider...",
    description,
    disabled,
}: CoverageProviderSelectProps) {
    const { availableProviders } = useAvailableCoverageProviders(chainId, excludeIds)

    return (
        <div className="space-y-2">
            <Label>{label}</Label>
            <Select value={value} onValueChange={onValueChange} disabled={disabled}>
                <SelectTrigger className="font-mono">
                    <SelectValue placeholder={placeholder} />
                </SelectTrigger>
                <SelectContent>
                    {availableProviders.length === 0 ? (
                        <div className="px-2 py-4 text-center text-sm text-muted-foreground">
                            No coverage providers available.
                            <br />
                            Add a CoverageProvider contract on the same chain first.
                        </div>
                    ) : (
                        availableProviders.map((provider) => (
                            <SelectItem key={provider.id} value={provider.id} className="font-mono">
                                <span className="flex flex-col gap-0.5">
                                    <span className="font-sans font-medium">{provider.name}</span>
                                    <span className="text-xs text-muted-foreground">
                                        {provider.address.slice(0, 10)}...
                                        {provider.address.slice(-8)}
                                    </span>
                                </span>
                            </SelectItem>
                        ))
                    )}
                </SelectContent>
            </Select>
            {description && <p className="text-xs text-muted-foreground">{description}</p>}
        </div>
    )
}
