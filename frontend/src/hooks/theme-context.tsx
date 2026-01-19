import * as React from "react"

export type Theme = "dark" | "light" | "system"

export type ThemeProviderState = {
    theme: Theme
    setTheme: (theme: Theme) => void
    resolvedTheme: "dark" | "light"
}

const initialState: ThemeProviderState = {
    theme: "system",
    setTheme: () => null,
    resolvedTheme: "light",
}

export const ThemeProviderContext = React.createContext<ThemeProviderState>(initialState)
