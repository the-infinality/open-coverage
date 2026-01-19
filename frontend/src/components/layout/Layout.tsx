import { Outlet } from "react-router-dom"
import { AppSidebar } from "./Sidebar"
import { Header } from "./Header"
import { Toaster } from "@/components/ui/sonner"
import { SidebarInset } from "@/components/ui/sidebar"

export function Layout() {
    return (
        <>
            <AppSidebar />
            <SidebarInset>
                <Header />
                <main className="flex-1 overflow-auto p-6">
                    <Outlet />
                </main>
            </SidebarInset>
            <Toaster />
        </>
    )
}
