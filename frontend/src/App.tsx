import { BrowserRouter, Routes, Route } from "react-router-dom"

import { ThemeProvider } from "@/hooks/theme-provider"
import { ContractsProvider } from "@/hooks/use-contracts"
import { Web3Provider } from "@/lib/web3-provider"
import { SidebarProvider } from "@/components/ui/sidebar"
import { Layout } from "@/components/layout/Layout"
import { AddContractPage } from "@/pages/AddContractPage"
import { ContractsPage } from "@/pages/ContractsPage"
import { InteractPage } from "@/pages/InteractPage"
import { LogsPage } from "@/pages/LogsPage"

function App() {
  return (
    <ThemeProvider defaultTheme="system" storageKey="open-coverage-theme">
      <Web3Provider>
        <ContractsProvider>
          <SidebarProvider>
            <BrowserRouter>
              <Routes>
                <Route path="/" element={<Layout />}>
                  <Route index element={<ContractsPage />} />
                  <Route path="add-contract" element={<AddContractPage />} />
                  <Route path="interact" element={<InteractPage />} />
                  <Route path="interact/:contractId" element={<InteractPage />} />
                  <Route path="logs" element={<LogsPage />} />
                  <Route path="logs/:contractId" element={<LogsPage />} />
                </Route>
              </Routes>
            </BrowserRouter>
          </SidebarProvider>
        </ContractsProvider>
      </Web3Provider>
    </ThemeProvider>
  )
}

export default App
