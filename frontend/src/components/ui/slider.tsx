import * as React from "react"
import { cn } from "@/lib/utils"

interface SliderProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, "onChange"> {
    value: number
    onChange: (value: number) => void
    min?: number
    max?: number
    step?: number
}

const Slider = React.forwardRef<HTMLInputElement, SliderProps>(
    ({ className, value, onChange, min = 0, max = 100, step = 1, ...props }, ref) => {
        const percentage = ((value - min) / (max - min)) * 100

        return (
            <div className="relative w-full">
                <input
                    type="range"
                    ref={ref}
                    value={value}
                    min={min}
                    max={max}
                    step={step}
                    onChange={(e) => onChange(Number(e.target.value))}
                    className={cn(
                        "w-full h-2 rounded-full appearance-none cursor-pointer",
                        "bg-secondary",
                        "[&::-webkit-slider-thumb]:appearance-none",
                        "[&::-webkit-slider-thumb]:h-5",
                        "[&::-webkit-slider-thumb]:w-5",
                        "[&::-webkit-slider-thumb]:rounded-full",
                        "[&::-webkit-slider-thumb]:bg-primary",
                        "[&::-webkit-slider-thumb]:border-2",
                        "[&::-webkit-slider-thumb]:border-background",
                        "[&::-webkit-slider-thumb]:shadow-md",
                        "[&::-webkit-slider-thumb]:transition-transform",
                        "[&::-webkit-slider-thumb]:hover:scale-110",
                        "[&::-moz-range-thumb]:h-5",
                        "[&::-moz-range-thumb]:w-5",
                        "[&::-moz-range-thumb]:rounded-full",
                        "[&::-moz-range-thumb]:bg-primary",
                        "[&::-moz-range-thumb]:border-2",
                        "[&::-moz-range-thumb]:border-background",
                        "[&::-moz-range-thumb]:shadow-md",
                        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
                        className
                    )}
                    style={{
                        background: `linear-gradient(to right, hsl(var(--primary)) 0%, hsl(var(--primary)) ${percentage}%, hsl(var(--secondary)) ${percentage}%, hsl(var(--secondary)) 100%)`,
                    }}
                    {...props}
                />
            </div>
        )
    }
)

Slider.displayName = "Slider"

export { Slider }
