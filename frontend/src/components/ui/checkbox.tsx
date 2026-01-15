import * as React from "react"
import { Check } from "lucide-react"

import { cn } from "@/lib/utils"

export interface CheckboxProps
  extends Omit<React.InputHTMLAttributes<HTMLInputElement>, "type"> {}

const Checkbox = React.forwardRef<HTMLInputElement, CheckboxProps>(
  ({ className, checked, onChange, ...props }, ref) => {
    const handleClick = (e: React.MouseEvent<HTMLLabelElement>) => {
      e.preventDefault()
      if (onChange) {
        onChange({
          target: { checked: !checked },
        } as React.ChangeEvent<HTMLInputElement>)
      }
    }

    return (
      <label
        className={cn(
          "peer relative flex h-5 w-5 shrink-0 cursor-pointer items-center justify-center rounded border border-input bg-background transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 data-[state=checked]:bg-primary data-[state=checked]:text-primary-foreground data-[state=checked]:border-primary",
          className
        )}
        data-state={checked ? "checked" : "unchecked"}
        onClick={handleClick}
      >
        <input
          type="checkbox"
          className="sr-only"
          checked={checked}
          onChange={onChange}
          ref={ref}
          {...props}
        />
        {checked && (
          <Check className="size-3.5 text-current" strokeWidth={3} />
        )}
      </label>
    )
  }
)
Checkbox.displayName = "Checkbox"

export { Checkbox }

