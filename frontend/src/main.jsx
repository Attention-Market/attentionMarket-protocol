import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { createNetworkConfig, SuiClientProvider, WalletProvider } from '@mysten/dapp-kit'
import { getJsonRpcFullnodeUrl } from '@mysten/sui/jsonRpc'
import '@mysten/dapp-kit/dist/index.css'
import Market from './pages/Market.jsx'
import Profile from './pages/Profile.jsx'
import Register from './pages/Register.jsx'
import Dashboard from './pages/Dashboard.jsx'
import Receipts from './pages/Receipts.jsx'
import Nav from './components/Nav.jsx'
import './index.css'

const queryClient = new QueryClient()
const { networkConfig } = createNetworkConfig({
  testnet: { url: getJsonRpcFullnodeUrl('testnet') },
})

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <SuiClientProvider networks={networkConfig} defaultNetwork="testnet">
        <WalletProvider>
          <BrowserRouter>
            <Nav />
            <Routes>
              <Route path="/"              element={<Market />} />
              <Route path="/profile/:vaultId" element={<Profile />} />
              <Route path="/register"      element={<Register />} />
              <Route path="/dashboard"     element={<Dashboard />} />
              <Route path="/receipts"      element={<Receipts />} />
            </Routes>
          </BrowserRouter>
        </WalletProvider>
      </SuiClientProvider>
    </QueryClientProvider>
  </React.StrictMode>
)