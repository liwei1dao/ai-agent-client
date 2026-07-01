import { create } from 'zustand'
import { getToken, setToken, clearToken } from '@/api/request'

interface AuthState {
  token: string
  account: string
  identity: number
  login: (token: string, account: string, identity: number) => void
  logout: () => void
}

export const useAuth = create<AuthState>((set) => ({
  token: getToken(),
  account: localStorage.getItem('admin_account') || '',
  identity: Number(localStorage.getItem('admin_identity') || 0),
  login: (token, account, identity) => {
    setToken(token)
    localStorage.setItem('admin_account', account)
    localStorage.setItem('admin_identity', String(identity))
    set({ token, account, identity })
  },
  logout: () => {
    clearToken()
    localStorage.removeItem('admin_account')
    localStorage.removeItem('admin_identity')
    set({ token: '', account: '', identity: 0 })
  },
}))
