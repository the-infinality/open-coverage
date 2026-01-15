import * as React from "react"
import { Copy, Check } from "lucide-react"
import { toast } from "sonner"
import { cn } from "@/lib/utils"
import { truncateAddress } from "@/lib/utils"
import { Button } from "@/components/ui/button"

interface CopyableAddressProps {
  address: string
  truncateChars?: number
  className?: string
  showCopyButton?: boolean
  variant?: "default" | "code" | "inline"
  size?: "sm" | "md" | "lg"
}

export function CopyableAddress({
  address,
  truncateChars = 4,
  className,
  showCopyButton = true,
  variant = "default",
  size = "md",
}: CopyableAddressProps) {
  const [copied, setCopied] = React.useState(false)

  const handleCopy = async (e: React.MouseEvent) => {
    e.stopPropagation()
    try {
      await navigator.clipboard.writeText(address)
      setCopied(true)
      toast.success("Address copied to clipboard")
      setTimeout(() => setCopied(false), 2000)
    } catch {
      toast.error("Failed to copy address")
    }
  }

  const truncated = truncateAddress(address, truncateChars)

  if (variant === "code") {
    return (
      <div className={cn("flex items-center gap-2", className)}>
        <code className="rounded bg-muted px-2 py-1 text-xs font-mono">
          {truncated}
        </code>
        {showCopyButton && (
          <Button
            variant="ghost"
            size="icon"
            className="h-6 w-6"
            onClick={handleCopy}
            title="Copy address"
          >
            {copied ? (
              <Check className="h-3 w-3 text-green-500" />
            ) : (
              <Copy className="h-3 w-3" />
            )}
          </Button>
        )}
      </div>
    )
  }

  if (variant === "inline") {
    return (
      <span className={cn("inline-flex items-center gap-1.5", className)}>
        <span className="font-mono">{truncated}</span>
        {showCopyButton && (
          <button
            onClick={handleCopy}
            className="inline-flex items-center justify-center rounded p-0.5 hover:bg-muted transition-colors"
            title="Copy address"
            type="button"
          >
            {copied ? (
              <Check className="h-3 w-3 text-green-500" />
            ) : (
              <Copy className="h-3 w-3 text-muted-foreground" />
            )}
          </button>
        )}
      </span>
    )
  }

  // Default variant
  return (
    <div className={cn("flex items-center gap-2", className)}>
      <span className={cn(
        "font-mono",
        size === "sm" && "text-xs",
        size === "md" && "text-sm",
        size === "lg" && "text-base"
      )}>
        {truncated}
      </span>
      {showCopyButton && (
        <Button
          variant="ghost"
          size="icon"
          className={cn(
            size === "sm" && "h-6 w-6",
            size === "md" && "h-7 w-7",
            size === "lg" && "h-8 w-8"
          )}
          onClick={handleCopy}
          title="Copy address"
        >
          {copied ? (
            <Check className={cn(
              "text-green-500",
              size === "sm" && "h-3 w-3",
              size === "md" && "h-3.5 w-3.5",
              size === "lg" && "h-4 w-4"
            )} />
          ) : (
            <Copy className={cn(
              size === "sm" && "h-3 w-3",
              size === "md" && "h-3.5 w-3.5",
              size === "lg" && "h-4 w-4"
            )} />
          )}
        </Button>
      )}
    </div>
  )
}

