import { useState, useMemo, useCallback } from "react"
import { isAddress } from "viem"
import { Plus, Trash2, ChevronDown } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
    Select,
    SelectContent,
    SelectItem,
    SelectTrigger,
    SelectValue,
} from "@/components/ui/select"

// Uniswap V3 fee options (in hundredths of a basis point)
const UNISWAP_V3_FEES = [
    { value: "100", label: "0.01%" },
    { value: "500", label: "0.05%" },
    { value: "3000", label: "0.3%" },
    { value: "10000", label: "1%" },
]

interface PathHop {
    token: string
    fee: string
}

interface UniswapV3PoolInputProps {
    value: string
    onChange: (encodedPath: string) => void
    disabled?: boolean
}

/**
 * Encode Uniswap V3 path from tokens and fees
 * Format: token0 (20 bytes) + fee0 (3 bytes) + token1 (20 bytes) + fee1 (3 bytes) + ... + tokenN (20 bytes)
 */
function encodeUniswapV3Path(path: PathHop[]): string {
    if (path.length < 2) return ""
    
    // Validate all tokens are valid addresses
    const validTokens = path.every((p, i) => {
        if (!isAddress(p.token)) return false
        // Fee is required for all except the last token
        if (i < path.length - 1 && (!p.fee || isNaN(Number(p.fee)))) return false
        return true
    })
    
    if (!validTokens) return ""

    let encoded = "0x"
    for (let i = 0; i < path.length; i++) {
        // Add token address (20 bytes, no 0x prefix)
        encoded += path[i].token.slice(2).toLowerCase()
        // Add fee (3 bytes) for all except last token
        if (i < path.length - 1) {
            const fee = Number(path[i].fee)
            // Fee is encoded as 3 bytes (24 bits)
            const feeHex = fee.toString(16).padStart(6, "0")
            encoded += feeHex
        }
    }
    return encoded
}

/**
 * UniswapV3PoolInput Component
 * 
 * A visual path builder for Uniswap V3 swap paths.
 * Allows users to add token addresses and pool fees to build multi-hop swap routes.
 */
export function UniswapV3PoolInput({ onChange, disabled = false }: UniswapV3PoolInputProps) {
    const [path, setPath] = useState<PathHop[]>([
        { token: "", fee: "3000" },
        { token: "", fee: "" },
    ])

    // Compute encoded path and notify parent
    const computedPath = useMemo(() => {
        return encodeUniswapV3Path(path)
    }, [path])

    // Sync with parent when path changes
    const updatePath = useCallback((newPath: PathHop[]) => {
        setPath(newPath)
        const encoded = encodeUniswapV3Path(newPath)
        onChange(encoded)
    }, [onChange])

    // Handle adding a new hop to the path
    const addPathHop = useCallback(() => {
        updatePath([
            ...path.slice(0, -1),
            { token: "", fee: "3000" },
            path[path.length - 1],
        ])
    }, [path, updatePath])

    // Handle removing a hop from the path
    const removePathHop = useCallback((index: number) => {
        if (path.length <= 2) return // Must have at least 2 tokens
        const newPath = [...path]
        newPath.splice(index, 1)
        updatePath(newPath)
    }, [path, updatePath])

    // Handle updating a token in the path
    const updatePathToken = useCallback((index: number, token: string) => {
        const newPath = [...path]
        newPath[index] = { ...newPath[index], token }
        updatePath(newPath)
    }, [path, updatePath])

    // Handle updating a fee in the path
    const updatePathFee = useCallback((index: number, fee: string) => {
        const newPath = [...path]
        newPath[index] = { ...newPath[index], fee }
        updatePath(newPath)
    }, [path, updatePath])

    return (
        <div className="space-y-3">
            <p className="text-xs text-muted-foreground">
                Build a Uniswap V3 swap path by adding token addresses and pool fees.
                The path defines the route: Token A → (fee) → Token B → (fee) → Token C...
            </p>
            
            <div className="space-y-2 rounded-lg border bg-muted/30 p-3">
                {path.map((hop, index) => (
                    <div key={index} className="space-y-2">
                        <div className="flex items-center gap-2">
                            <div className="flex-1 space-y-1">
                                <Label className="text-xs text-muted-foreground">
                                    Token {index + 1}
                                </Label>
                                <Input
                                    placeholder="0x... token address"
                                    value={hop.token}
                                    onChange={(e) => updatePathToken(index, e.target.value)}
                                    className="font-mono h-9 text-sm"
                                    disabled={disabled}
                                />
                            </div>
                            {path.length > 2 && (
                                <Button
                                    type="button"
                                    variant="ghost"
                                    size="icon"
                                    className="h-9 w-9 mt-5 text-muted-foreground hover:text-destructive"
                                    onClick={() => removePathHop(index)}
                                    disabled={disabled}
                                >
                                    <Trash2 className="size-4" />
                                </Button>
                            )}
                        </div>
                        {hop.token && !isAddress(hop.token) && (
                            <p className="text-xs text-destructive">Invalid address</p>
                        )}
                        
                        {/* Fee selector - shown for all except last token */}
                        {index < path.length - 1 && (
                            <div className="flex items-center gap-2 pl-4 border-l-2 border-muted-foreground/20 ml-2">
                                <ChevronDown className="size-4 text-muted-foreground" />
                                <Select
                                    value={hop.fee}
                                    onValueChange={(v) => updatePathFee(index, v)}
                                    disabled={disabled}
                                >
                                    <SelectTrigger className="w-[120px] h-8">
                                        <SelectValue placeholder="Fee tier" />
                                    </SelectTrigger>
                                    <SelectContent>
                                        {UNISWAP_V3_FEES.map((fee) => (
                                            <SelectItem key={fee.value} value={fee.value}>
                                                {fee.label}
                                            </SelectItem>
                                        ))}
                                    </SelectContent>
                                </Select>
                                <span className="text-xs text-muted-foreground">pool fee</span>
                            </div>
                        )}
                    </div>
                ))}

                <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    className="w-full mt-2"
                    onClick={addPathHop}
                    disabled={disabled}
                >
                    <Plus className="size-4 mr-2" />
                    Add Intermediate Token (Multi-hop)
                </Button>
            </div>

            {/* Display computed pool info */}
            {computedPath && (
                <div className="space-y-1">
                    <Label className="text-xs text-muted-foreground">
                        Computed Pool Info
                    </Label>
                    <div className="rounded-md bg-muted p-2 font-mono text-xs break-all">
                        {computedPath}
                    </div>
                </div>
            )}
            {!computedPath && path.some(p => p.token) && (
                <p className="text-xs text-amber-600">
                    Enter valid addresses for all tokens to generate pool info
                </p>
            )}
        </div>
    )
}

