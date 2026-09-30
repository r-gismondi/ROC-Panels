export const C_CONNECT_ID = "c-connect"
export const C_CONNECT_NAME = "C-Connect"
export const C_CONNECT_URL = "https://ccv2.mtllc.us"

export function programIconSrc(id: string) {
  if (id === C_CONNECT_ID) return "/c-connect.png"
  return `/api/apps/icon?id=${encodeURIComponent(id)}`
}

export function programIconClass(id: string) {
  return id === C_CONNECT_ID ? "h-6 w-6 shrink-0 rounded-full object-cover" : "h-6 w-6 shrink-0 object-contain"
}
