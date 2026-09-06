const API_BASE = "";

export function getToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem("admin_token");
}

export function setToken(token: string) {
  localStorage.setItem("admin_token", token);
}

export function clearToken() {
  localStorage.removeItem("admin_token");
}

export async function api(path: string, options: RequestInit = {}) {
  const token = getToken();
  const res = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...options.headers,
    },
  });
  const data = await res.json();
  if (!res.ok) throw { status: res.status, ...data };
  return data;
}

export const authApi = {
  login: (username: string, password: string) =>
    api("/api/auth/login", { method: "POST", body: JSON.stringify({ username, password }) }),
  me: () => api("/api/auth/me"),
  logout: () => api("/api/auth/logout", { method: "POST" }),
};

export const permissionsApi = {
  me: () => api("/api/permissions-menu/my"),
};

export const walletApi = {
  creditUser: (userId: string, body: any) =>
    api(`/api/admin/users/${userId}/credit`, { method: "POST", body: JSON.stringify(body) }),
  debitUser: (userId: string, body: any) =>
    api(`/api/admin/users/${userId}/debit`, { method: "POST", body: JSON.stringify(body) }),
  coinTransactions: (params?: string) =>
    api(`/api/admin/coin-transactions${params ? "?" + params : ""}`),
};
