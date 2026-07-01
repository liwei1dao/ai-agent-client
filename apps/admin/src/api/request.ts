import axios, { type AxiosInstance } from 'axios'
import { message } from 'antd'
import type { ApiResult } from './types'

const TOKEN_KEY = 'admin_token'

export const getToken = () => localStorage.getItem(TOKEN_KEY) || ''
export const setToken = (t: string) => localStorage.setItem(TOKEN_KEY, t)
export const clearToken = () => localStorage.removeItem(TOKEN_KEY)

// console 后端：POST /console/api/<method>，JWT 放 Authorization 头，响应信封 {code,msg,data}
const http: AxiosInstance = axios.create({
  baseURL: import.meta.env.VITE_API_BASE || '/console/api',
  timeout: 20000,
})

http.interceptors.request.use((config) => {
  const token = getToken()
  if (token) config.headers.Authorization = token
  return config
})

http.interceptors.response.use(
  (resp) => resp,
  (err) => {
    if (err.response?.status === 401) {
      clearToken()
      if (location.hash.indexOf('/login') < 0) location.hash = '#/login'
      message.error('登录已过期，请重新登录')
    } else {
      message.error(err.message || '网络错误')
    }
    return Promise.reject(err)
  },
)

/** 统一调用：返回 data，code!=0 抛错并提示 */
export async function call<T = unknown>(method: string, params?: unknown): Promise<T> {
  const resp = await http.post<ApiResult<T>>(`/${method}`, params ?? {})
  const body = resp.data
  if (body.code !== 0) {
    message.error(body.msg || `请求失败 (${body.code})`)
    throw new Error(body.msg || `code=${body.code}`)
  }
  return body.data
}

export default http
