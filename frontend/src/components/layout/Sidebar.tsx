import { NavLink, useLocation } from "react-router-dom"
import { FileText, Plus, Sun, Moon, Monitor, Zap, List } from "lucide-react"
import { useTheme } from "@/hooks/use-theme"
import {
    Select,
    SelectContent,
    SelectItem,
    SelectTrigger,
    SelectValue,
} from "@/components/ui/select"
import {
    Sidebar,
    SidebarContent,
    SidebarFooter,
    SidebarGroup,
    SidebarGroupContent,
    SidebarHeader,
    SidebarMenu,
    SidebarMenuButton,
    SidebarMenuItem,
} from "@/components/ui/sidebar"

const navItems = [
    {
        title: "Contracts",
        href: "/",
        icon: List,
    },
    {
        title: "Add Contract",
        href: "/add-contract",
        icon: Plus,
    },
    {
        title: "Interact",
        href: "/interact",
        icon: Zap,
    },
    {
        title: "Logs",
        href: "/logs",
        icon: FileText,
    },
]

function ThemeToggle() {
    const { theme, setTheme } = useTheme()

    return (
        <Select
            value={theme}
            onValueChange={(value) => setTheme(value as "light" | "dark" | "system")}
        >
            <SelectTrigger className="w-full">
                <SelectValue placeholder="Theme" />
            </SelectTrigger>
            <SelectContent>
                <SelectItem value="light">
                    <div className="flex items-center gap-2">
                        <Sun className="size-4" />
                        Light
                    </div>
                </SelectItem>
                <SelectItem value="dark">
                    <div className="flex items-center gap-2">
                        <Moon className="size-4" />
                        Dark
                    </div>
                </SelectItem>
                <SelectItem value="system">
                    <div className="flex items-center gap-2">
                        <Monitor className="size-4" />
                        System
                    </div>
                </SelectItem>
            </SelectContent>
        </Select>
    )
}

export function AppSidebar() {
    const location = useLocation()

    return (
        <Sidebar>
            <SidebarHeader>
                <span className="font-semibold text-sidebar-foreground">Open Coverage</span>
            </SidebarHeader>
            <SidebarContent>
                <SidebarGroup>
                    <SidebarGroupContent>
                        <SidebarMenu className="space-y-1">
                            {navItems.map((item) => {
                                const isActive =
                                    location.pathname === item.href ||
                                    (item.href !== "/" && location.pathname.startsWith(item.href))
                                return (
                                    <SidebarMenuItem key={item.href}>
                                        <SidebarMenuButton
                                            asChild
                                            isActive={isActive}
                                            className="h-12 hover:bg-sidebar-accent/60"
                                        >
                                            <NavLink to={item.href}>
                                                <item.icon className="size-4" />
                                                <span>{item.title}</span>
                                            </NavLink>
                                        </SidebarMenuButton>
                                    </SidebarMenuItem>
                                )
                            })}
                        </SidebarMenu>
                    </SidebarGroupContent>
                </SidebarGroup>
            </SidebarContent>
            <SidebarFooter>
                <ThemeToggle />
                <div className="text-sm text-muted-foreground text-center px-2 mt-4">
                    <p>Open Coverage Frontend v0.1.0</p>
                    <p className="text-xs mt-2">
                        Built with ❤️ by Infinality. The creators of SPICE Protocol.
                    </p>
                </div>
            </SidebarFooter>
        </Sidebar>
    )
}
