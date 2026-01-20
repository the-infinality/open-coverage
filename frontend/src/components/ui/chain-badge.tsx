import { getChainInfo } from "@/lib/wagmi"
import { cn } from "@/lib/utils"

interface ChainBadgeProps {
    chainId: number
    size?: "sm" | "md" | "lg"
    showIcon?: boolean
    className?: string
}

export function ChainBadge({ chainId, size = "md", showIcon = true, className }: ChainBadgeProps) {
    const chainInfo = getChainInfo(chainId)

    if (!chainInfo) {
        return null
    }

    const sizeClasses = {
        sm: {
            icon: "h-4 w-4",
            container: "px-2 py-1 gap-1.5",
            text: "text-xs",
        },
        md: {
            icon: "h-5 w-5",
            container: "px-3 py-1.5 gap-2",
            text: "text-sm",
        },
        lg: {
            icon: "h-6 w-6",
            container: "px-4 py-2.5 gap-2",
            text: "text-base",
        },
    }

    return (
        <div
            className={cn(
                "flex items-center rounded-lg border-2 transition-all",
                "border-border bg-background w-fit mt-2 mb-2 text-foreground",
                sizeClasses[size].container,
                sizeClasses[size].text,
                className
            )}
        >
            {showIcon && (
                <img
                    src={chainInfo.icon}
                    alt={chainInfo.name}
                    className={cn("rounded-full", sizeClasses[size].icon)}
                />
            )}
            <span className="font-medium">{chainInfo.name}</span>
            {chainInfo.isTestnet && (
                <span
                    className={cn(
                        "text-xs px-1.5 py-0.5 rounded-full",
                        chainInfo.colors.bg,
                        chainInfo.colors.text
                    )}
                >
                    Testnet
                </span>
            )}
        </div>
    )
}
