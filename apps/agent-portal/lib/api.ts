const API_BASE = "";

export function getToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem("agent_token");
}

export function setToken(token: string) {
  localStorage.setItem("agent_token", token);
}

export function clearToken() {
  localStorage.removeItem("agent_token");
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

export const agentApi = {
  dashboard: () => api("/api/agent-portal/dashboard"),
  customers: () => api("/api/agent-portal/customers"),
  earnings: () => api("/api/agent-portal/earnings"),
  withdrawals: () => api("/api/agent-portal/withdrawals"),
  requestWithdrawal: (amount: number) =>
    api("/api/agent-portal/withdrawals", { method: "POST", body: JSON.stringify({ amount }) }),
};
