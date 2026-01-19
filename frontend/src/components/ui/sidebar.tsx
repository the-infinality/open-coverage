import * as React from "react"
import { Slot } from "@radix-ui/react-slot"
import { cva, type VariantProps } from "class-variance-authority"
import { cn } from "@/lib/utils"

type SidebarContext = {
    state: "expanded" | "collapsed"
    open: boolean
    setOpen: (open: boolean) => void
    openMobile: boolean
    setOpenMobile: (open: boolean) => void
    isMobile: boolean
    toggleSidebar: () => void
}

const SidebarContext = React.createContext<SidebarContext | null>(null)

function useSidebar() {
    const context = React.useContext(SidebarContext)
    if (!context) {
        throw new Error("useSidebar must be used within a SidebarProvider.")
    }

    return context
}

const SidebarProvider = React.forwardRef<
    HTMLDivElement,
    React.ComponentProps<"div"> & {
        defaultOpen?: boolean
        open?: boolean
        onOpenChange?: (open: boolean) => void
    }
>(({ defaultOpen = true, open: openProp, onOpenChange, className, ...props }, ref) => {
    const [openMobile, setOpenMobile] = React.useState(false)
    const [openDesktop, setOpenDesktop] = React.useState(defaultOpen)

    const open = openProp ?? openDesktop
    const setOpen = React.useCallback(
        (value: boolean | ((value: boolean) => boolean)) => {
            const openState = typeof value === "function" ? value(open) : value
            if (onOpenChange) {
                onOpenChange(openState)
            } else {
                setOpenDesktop(openState)
            }
        },
        [open, onOpenChange]
    )

    // Mobile sidebar state
    const isMobile = React.useMemo(() => {
        return window.innerWidth < 768
    }, [])

    React.useEffect(() => {
        const handleResize = () => {
            if (window.innerWidth >= 768) {
                setOpenMobile(false)
            }
        }
        window.addEventListener("resize", handleResize)
        return () => window.removeEventListener("resize", handleResize)
    }, [])

    const toggleSidebar = React.useCallback(() => {
        return isMobile ? setOpenMobile((open) => !open) : setOpen((open) => !open)
    }, [isMobile, setOpen])

    const state = open ? "expanded" : "collapsed"

    const contextValue = React.useMemo<SidebarContext>(
        () => ({
            state,
            open,
            setOpen,
            isMobile,
            openMobile,
            setOpenMobile,
            toggleSidebar,
        }),
        [state, open, setOpen, isMobile, openMobile, setOpenMobile, toggleSidebar]
    )

    return (
        <SidebarContext.Provider value={contextValue}>
            <div
                ref={ref}
                className={cn(
                    "group/sidebar-wrapper flex min-h-svh w-full has-data-[sidebar=sidebar]:bg-sidebar",
                    className
                )}
                {...props}
            />
        </SidebarContext.Provider>
    )
})
SidebarProvider.displayName = "SidebarProvider"

const Sidebar = React.forwardRef<
    HTMLDivElement,
    React.ComponentProps<"div"> & {
        side?: "left" | "right"
        variant?: "sidebar" | "floating" | "inset"
        collapsible?: "offcanvas" | "icon" | "none"
    }
>(({ side = "left", variant = "sidebar", collapsible = "offcanvas", className, ...props }, ref) => {
    const { isMobile, openMobile, setOpenMobile, state } = useSidebar()

    if (collapsible === "none") {
        return (
            <div
                ref={ref}
                data-sidebar={variant}
                data-mobile={isMobile}
                className={cn(
                    "group peer hidden md:flex h-screen flex-col text-sidebar-foreground",
                    className
                )}
                {...props}
            />
        )
    }

    if (isMobile) {
        return (
            <>
                <div
                    data-sidebar="trigger"
                    data-state={openMobile ? "open" : "closed"}
                    className="peer hidden"
                    aria-hidden="true"
                />
                <div
                    ref={ref}
                    data-sidebar={variant}
                    data-state={openMobile ? "open" : "closed"}
                    data-side={side}
                    data-mobile={isMobile}
                    className={cn(
                        "group peer fixed inset-y-0 z-50 hidden w-full -translate-x-full border-r duration-200 data-[state=open]:translate-x-0 md:hidden",
                        className
                    )}
                    {...props}
                />
                <div
                    data-sidebar="backdrop"
                    data-state={openMobile ? "open" : "closed"}
                    className="peer peer-data-[state=open]:bg-sidebar-backdrop peer-data-[state=open]:backdrop-blur-sm fixed inset-0 z-40 hidden bg-transparent transition-colors duration-200 peer-data-[state=open]:block md:hidden"
                    onClick={() => setOpenMobile(false)}
                />
            </>
        )
    }

    return (
        <>
            <div
                ref={ref}
                data-sidebar={variant}
                data-state={state}
                data-collapsible={state === "collapsed" ? collapsible : ""}
                data-side={side}
                data-mobile={isMobile}
                className={cn(
                    "group peer hidden md:flex h-screen flex-col text-sidebar-foreground",
                    className
                )}
                {...props}
            />
        </>
    )
})
Sidebar.displayName = "Sidebar"

const SidebarTrigger = React.forwardRef<HTMLButtonElement, React.ComponentProps<"button">>(
    ({ className, onClick, ...props }, ref) => {
        const { toggleSidebar } = useSidebar()

        return (
            <button
                ref={ref}
                data-sidebar="trigger"
                type="button"
                className={cn("inline-flex items-center justify-center", className)}
                onClick={(event) => {
                    onClick?.(event)
                    toggleSidebar()
                }}
                {...props}
            />
        )
    }
)
SidebarTrigger.displayName = "SidebarTrigger"

const SidebarRail = React.forwardRef<HTMLButtonElement, React.ComponentProps<"button">>(
    ({ className, ...props }, ref) => {
        const { toggleSidebar } = useSidebar()

        return (
            <button
                ref={ref}
                data-sidebar="rail"
                aria-label="Toggle Sidebar"
                type="button"
                tabIndex={-1}
                onClick={toggleSidebar}
                title="Toggle Sidebar"
                className={cn(
                    "absolute inset-y-0 z-20 hidden w-4 -translate-x-1/2 transition-all ease-linear after:absolute after:inset-y-0 after:left-1/2 after:w-[2px] after:-translate-x-1/2 after:bg-sidebar-border after:opacity-0 after:transition-opacity after:duration-200 hover:after:opacity-100 group-data-[collapsible=icon]:flex group-data-[collapsible=offcanvas]:flex group-data-[side=left]:-right-4 group-data-[side=right]:left-0",
                    className
                )}
                {...props}
            />
        )
    }
)
SidebarRail.displayName = "SidebarRail"

const SidebarInset = React.forwardRef<HTMLDivElement, React.ComponentProps<"div">>(
    ({ className, ...props }, ref) => {
        return (
            <main
                ref={ref}
                className={cn(
                    "relative flex min-h-svh flex-1 flex-col bg-background",
                    "peer-data-[variant=inset]:min-w-0",
                    className
                )}
                {...props}
            />
        )
    }
)
SidebarInset.displayName = "SidebarInset"

const SidebarInput = React.forwardRef<HTMLInputElement, React.ComponentProps<"input">>(
    ({ className, ...props }, ref) => {
        return (
            <input
                ref={ref}
                data-sidebar="input"
                className={cn(
                    "flex h-8 w-full rounded-md border border-sidebar-border bg-sidebar-accent px-3 py-1 text-sm text-sidebar-foreground ring-offset-sidebar transition-colors file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-sidebar-foreground/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sidebar-ring focus-visible:ring-offset-2 focus-visible:ring-offset-sidebar disabled:cursor-not-allowed disabled:opacity-50",
                    className
                )}
                {...props}
            />
        )
    }
)
SidebarInput.displayName = "SidebarInput"

const SidebarHeader = React.forwardRef<HTMLDivElement, React.ComponentProps<"div">>(
    ({ className, ...props }, ref) => {
        return (
            <div
                ref={ref}
                data-sidebar="header"
                className={cn("flex h-16 shrink-0 items-center gap-2 px-6", className)}
                {...props}
            />
        )
    }
)
SidebarHeader.displayName = "SidebarHeader"

const SidebarFooter = React.forwardRef<HTMLDivElement, React.ComponentProps<"div">>(
    ({ className, ...props }, ref) => {
        return (
            <div
                ref={ref}
                data-sidebar="footer"
                className={cn("flex shrink-0 flex-col gap-2 border-sidebar-border p-2", className)}
                {...props}
            />
        )
    }
)
SidebarFooter.displayName = "SidebarFooter"

const SidebarSeparator = React.forwardRef<HTMLHRElement, React.ComponentProps<"hr">>(
    ({ className, ...props }, ref) => {
        return (
            <hr
                ref={ref}
                data-sidebar="separator"
                className={cn("mx-2 my-2 border-sidebar-border", className)}
                {...props}
            />
        )
    }
)
SidebarSeparator.displayName = "SidebarSeparator"

const SidebarContent = React.forwardRef<HTMLDivElement, React.ComponentProps<"div">>(
    ({ className, ...props }, ref) => {
        return (
            <div
                ref={ref}
                data-sidebar="content"
                className={cn(
                    "flex min-h-0 flex-1 flex-col gap-2 overflow-auto group-data-[collapsible=icon]:overflow-hidden",
                    className
                )}
                {...props}
            />
        )
    }
)
SidebarContent.displayName = "SidebarContent"

const SidebarGroup = React.forwardRef<HTMLDivElement, React.ComponentProps<"div">>(
    ({ className, ...props }, ref) => {
        return (
            <div
                ref={ref}
                data-sidebar="group"
                className={cn("relative flex w-full min-w-0 flex-col p-2", className)}
                {...props}
            />
        )
    }
)
SidebarGroup.displayName = "SidebarGroup"

const SidebarGroupLabel = React.forwardRef<HTMLDivElement, React.ComponentProps<"div">>(
    ({ className, ...props }, ref) => {
        return (
            <div
                ref={ref}
                data-sidebar="group-label"
                className={cn(
                    "duration-200 flex h-8 shrink-0 items-center rounded-md px-2 text-xs font-medium text-sidebar-foreground/70 outline-none ring-sidebar-ring transition-[margin,opa] ease-linear focus-visible:ring-2 [&>svg]:size-4 [&>svg]:shrink-0",
                    "group-data-[collapsible=icon]:-mt-8 group-data-[collapsible=icon]:opacity-0",
                    className
                )}
                {...props}
            />
        )
    }
)
SidebarGroupLabel.displayName = "SidebarGroupLabel"

const SidebarGroupAction = React.forwardRef<HTMLButtonElement, React.ComponentProps<"button">>(
    ({ className, ...props }, ref) => {
        return (
            <button
                ref={ref}
                data-sidebar="group-action"
                className={cn(
                    "absolute right-3 top-3.5 flex aspect-square w-5 items-center justify-center rounded-md p-0 text-sidebar-foreground outline-none ring-sidebar-ring transition-transform hover:bg-sidebar-accent hover:text-sidebar-accent-foreground focus-visible:ring-2 [&>svg]:size-4 [&>svg]:shrink-0",
                    "group-data-[collapsible=icon]:hidden",
                    className
                )}
                {...props}
            />
        )
    }
)
SidebarGroupAction.displayName = "SidebarGroupAction"

const SidebarGroupContent = React.forwardRef<HTMLDivElement, React.ComponentProps<"div">>(
    ({ className, ...props }, ref) => {
        return (
            <div
                ref={ref}
                data-sidebar="group-content"
                className={cn("w-full text-sm", className)}
                {...props}
            />
        )
    }
)
SidebarGroupContent.displayName = "SidebarGroupContent"

const SidebarMenu = React.forwardRef<HTMLUListElement, React.ComponentProps<"ul">>(
    ({ className, ...props }, ref) => {
        return (
            <ul
                ref={ref}
                data-sidebar="menu"
                className={cn("flex w-full min-w-0 flex-col gap-1", className)}
                {...props}
            />
        )
    }
)
SidebarMenu.displayName = "SidebarMenu"

const SidebarMenuItem = React.forwardRef<HTMLLIElement, React.ComponentProps<"li">>(
    ({ className, ...props }, ref) => {
        return (
            <li
                ref={ref}
                data-sidebar="menu-item"
                className={cn("group/menu-item relative", className)}
                {...props}
            />
        )
    }
)
SidebarMenuItem.displayName = "SidebarMenuItem"

const sidebarMenuButtonVariants = cva(
    "peer/menu-button flex w-full items-center gap-2 overflow-hidden rounded-md p-2 text-left text-sm outline-none ring-sidebar-ring transition-[width,height,padding] hover:bg-sidebar-accent hover:text-sidebar-accent-foreground focus-visible:ring-2 active:bg-sidebar-accent active:text-sidebar-accent-foreground disabled:pointer-events-none disabled:opacity-50 group-has-[[data-sidebar=menu-action]]/menu-item:pr-8 aria-disabled:pointer-events-none aria-disabled:opacity-50 data-[active=true]:bg-sidebar-accent data-[active=true]:font-medium data-[active=true]:text-sidebar-accent-foreground data-[state=open]:hover:bg-sidebar-accent data-[state=open]:hover:text-sidebar-accent-foreground group-data-[collapsible=icon]:!size-8 group-data-[collapsible=icon]:!p-2 [&>span:last-child]:truncate [&>svg]:size-4 [&>svg]:shrink-0",
    {
        variants: {
            variant: {
                default: "hover:bg-sidebar-accent hover:text-sidebar-accent-foreground",
                outline:
                    "bg-sidebar-background shadow-[0_0_0_1px_hsl(var(--sidebar-border))] hover:bg-sidebar-accent hover:text-sidebar-accent-foreground hover:shadow-[0_0_0_1px_hsl(var(--sidebar-accent))]",
            },
            size: {
                default: "h-[55px] text-sm",
                sm: "h-7 text-xs",
                lg: "h-12 text-base group-data-[collapsible=icon]:!size-12",
            },
        },
        defaultVariants: {
            variant: "default",
            size: "default",
        },
    }
)

const SidebarMenuButton = React.forwardRef<
    HTMLButtonElement,
    React.ComponentProps<"button"> &
        VariantProps<typeof sidebarMenuButtonVariants> & {
            asChild?: boolean
            isActive?: boolean
            tooltip?: string | React.ComponentProps<typeof Slot>
        }
>(
    (
        {
            asChild = false,
            isActive = false,
            variant = "default",
            size = "default",
            className,
            ...props
        },
        ref
    ) => {
        const Comp = asChild ? Slot : "button"
        return (
            <Comp
                ref={ref}
                data-sidebar="menu-button"
                data-size={size}
                data-active={isActive}
                className={cn(sidebarMenuButtonVariants({ variant, size }), className)}
                {...props}
            />
        )
    }
)
SidebarMenuButton.displayName = "SidebarMenuButton"

const SidebarMenuAction = React.forwardRef<
    HTMLButtonElement,
    React.ComponentProps<"button"> & {
        asChild?: boolean
        showOnHover?: boolean
    }
>(({ className, asChild = false, showOnHover = false, ...props }, ref) => {
    const Comp = asChild ? Slot : "button"

    return (
        <Comp
            ref={ref}
            data-sidebar="menu-action"
            className={cn(
                "absolute right-1 top-1.5 flex aspect-square w-5 items-center justify-center rounded-md p-0 text-sidebar-foreground outline-none ring-sidebar-ring transition-transform hover:bg-sidebar-accent hover:text-sidebar-accent-foreground focus-visible:ring-2 peer-hover/menu-button:text-sidebar-accent-foreground [&>svg]:size-4 [&>svg]:shrink-0",
                "peer-data-[size=sm]/menu-button:top-1",
                "peer-data-[size=default]/menu-button:top-1.5",
                "peer-data-[size=lg]/menu-button:top-2.5",
                showOnHover &&
                    "group-focus-within/menu-item:opacity-100 group-hover/menu-item:opacity-100 data-[state=open]:opacity-100 peer-data-[active=true]/menu-button:text-sidebar-accent-foreground md:opacity-0",
                className
            )}
            {...props}
        />
    )
})
SidebarMenuAction.displayName = "SidebarMenuAction"

const SidebarMenuBadge = React.forwardRef<HTMLDivElement, React.ComponentProps<"div">>(
    ({ className, ...props }, ref) => {
        return (
            <div
                ref={ref}
                data-sidebar="menu-badge"
                className={cn(
                    "absolute right-1 flex h-5 min-w-5 items-center justify-center rounded-md px-1 text-xs font-medium tabular-nums text-sidebar-foreground select-none pointer-events-none",
                    "peer-hover/menu-button:text-sidebar-accent-foreground peer-data-[active=true]/menu-button:text-sidebar-accent-foreground",
                    "peer-data-[size=sm]/menu-button:text-xs",
                    "peer-data-[size=default]/menu-button:text-xs",
                    "peer-data-[size=lg]/menu-button:text-sm",
                    className
                )}
                {...props}
            />
        )
    }
)
SidebarMenuBadge.displayName = "SidebarMenuBadge"

const SidebarMenuSkeleton = React.forwardRef<
    HTMLDivElement,
    React.ComponentProps<"div"> & {
        showIcon?: boolean
    }
>(({ className, showIcon = false, ...props }, ref) => {
    return (
        <div
            ref={ref}
            data-sidebar="menu-skeleton"
            className={cn("rounded-md h-8 flex gap-2 px-2 items-center", className)}
            {...props}
        >
            {showIcon && (
                <div className="flex h-4 w-4 shrink-0 animate-pulse rounded-md bg-sidebar-primary/10" />
            )}
            <div className="h-4 flex-1 animate-pulse rounded-md bg-sidebar-primary/10" />
        </div>
    )
})
SidebarMenuSkeleton.displayName = "SidebarMenuSkeleton"

const SidebarMenuSub = React.forwardRef<HTMLUListElement, React.ComponentProps<"ul">>(
    ({ className, ...props }, ref) => {
        return (
            <ul
                ref={ref}
                data-sidebar="menu-sub"
                className={cn(
                    "mx-3.5 flex min-w-0 translate-x-px flex-col gap-1 border-l border-sidebar-border px-2.5 py-0.5",
                    "group-data-[collapsible=icon]:hidden",
                    className
                )}
                {...props}
            />
        )
    }
)
SidebarMenuSub.displayName = "SidebarMenuSub"

const SidebarMenuSubItem = React.forwardRef<HTMLLIElement, React.ComponentProps<"li">>(
    ({ ...props }, ref) => {
        return <li ref={ref} {...props} />
    }
)
SidebarMenuSubItem.displayName = "SidebarMenuSubItem"

const SidebarMenuSubButton = React.forwardRef<
    HTMLAnchorElement,
    React.ComponentProps<"a"> & {
        asChild?: boolean
        size?: "sm" | "md" | "lg"
        isActive?: boolean
    }
>(({ asChild = false, size = "md", isActive, className, ...props }, ref) => {
    const Comp = asChild ? Slot : "a"

    return (
        <Comp
            ref={ref}
            data-sidebar="menu-sub-button"
            data-size={size}
            data-active={isActive}
            className={cn(
                "flex h-7 min-w-0 -translate-x-px items-center gap-2 overflow-hidden rounded-md px-2 text-sidebar-foreground outline-none ring-sidebar-ring hover:bg-sidebar-accent hover:text-sidebar-accent-foreground focus-visible:ring-2 active:bg-sidebar-accent active:text-sidebar-accent-foreground disabled:pointer-events-none disabled:opacity-50 aria-disabled:pointer-events-none aria-disabled:opacity-50 [&>span:last-child]:truncate [&>svg]:size-4 [&>svg]:shrink-0",
                "data-[active=true]:bg-sidebar-accent data-[active=true]:text-sidebar-accent-foreground",
                size === "sm" && "text-xs",
                size === "md" && "text-sm",
                size === "lg" && "text-base",
                "group-data-[collapsible=icon]:hidden",
                className
            )}
            {...props}
        />
    )
})
SidebarMenuSubButton.displayName = "SidebarMenuSubButton"

export {
    Sidebar,
    SidebarContent,
    SidebarFooter,
    SidebarGroup,
    SidebarGroupAction,
    SidebarGroupContent,
    SidebarGroupLabel,
    SidebarHeader,
    SidebarInput,
    SidebarInset,
    SidebarMenu,
    SidebarMenuAction,
    SidebarMenuBadge,
    SidebarMenuButton,
    SidebarMenuItem,
    SidebarMenuSkeleton,
    SidebarMenuSub,
    SidebarMenuSubButton,
    SidebarMenuSubItem,
    SidebarProvider,
    SidebarRail,
    SidebarSeparator,
    SidebarTrigger,
    // eslint-disable-next-line react-refresh/only-export-components
    useSidebar,
}
