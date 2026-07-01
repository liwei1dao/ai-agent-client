import { HashRouter, Routes, Route, Navigate } from 'react-router-dom'
import { useAuth } from './store/auth'
import AdminLayout from './layout/AdminLayout'
import Login from './pages/Login'
import Services from './pages/Services'
import Agents from './pages/Agents'
import AgentEdit from './pages/AgentEdit'
import Mcp from './pages/Mcp'
import GlobalConfig from './pages/GlobalConfig'

function RequireAuth({ children }: { children: JSX.Element }) {
  const token = useAuth((s) => s.token)
  return token ? children : <Navigate to="/login" replace />
}

export default function App() {
  return (
    <HashRouter>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route
          path="/"
          element={
            <RequireAuth>
              <AdminLayout />
            </RequireAuth>
          }
        >
          <Route index element={<Navigate to="/services" replace />} />
          <Route path="services" element={<Services />} />
          <Route path="agents" element={<Agents />} />
          <Route path="agents/new" element={<AgentEdit />} />
          <Route path="agents/edit/:id" element={<AgentEdit />} />
          <Route path="mcp" element={<Mcp />} />
          <Route path="global" element={<GlobalConfig />} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </HashRouter>
  )
}
