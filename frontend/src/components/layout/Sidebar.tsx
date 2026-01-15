import { NavLink } from "react-router-dom"
import { cn } from "@/lib/utils"
import {
  FileText,
  Settings,
  Wallet,
  Plus,
  Sun,
  Moon,
  Monitor,
} from "lucide-react"
import { useTheme } from "@/hooks/use-theme"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { Separator } from "@/components/ui/separator"

const navItems = [
  {
    title: "Add Contract",
    href: "/",
    icon: Plus,
  },
  {
    title: "Manage Contracts",
    href: "/contracts",
    icon: Settings,
  },
  {
    title: "Interact",
    href: "/interact",
    icon: FileText,
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
    <Select value={theme} onValueChange={(value) => setTheme(value as "light" | "dark" | "system")}>
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

export function Sidebar() {
  return (
    <aside className="flex h-screen w-64 flex-col border-r bg-sidebar-background">
      <div className="flex h-16 items-center gap-2 border-b px-6">
        <div className="flex size-8 items-center justify-center rounded-lg bg-primary text-primary-foreground">
          <Wallet className="size-4" />
        </div>
        <span className="font-semibold text-sidebar-foreground">
          Open Coverage
        </span>
      </div>

      <nav className="flex-1 space-y-1 p-4">
        {navItems.map((item) => (
          <NavLink
            key={item.href}
            to={item.href}
            className={({ isActive }) =>
              cn(
                "flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
                isActive
                  ? "bg-sidebar-accent text-sidebar-accent-foreground"
                  : "text-sidebar-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground"
              )
            }
          >
            <item.icon className="size-4" />
            {item.title}
          </NavLink>
        ))}
      </nav>

      <div className="border-t p-4 space-y-4">
        <ThemeToggle />
        <Separator />
        <div className="text-xs text-muted-foreground text-center">
          Open Coverage Frontend v0.1.0
        </div>
      </div>
    </aside>
  )
}
