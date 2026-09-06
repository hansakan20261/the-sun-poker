"use client";
import { useEffect, useState } from "react";
import { getToken, setToken, clearToken, authApi, agentApi } from "@/lib/api";

export default function AgentPortal() {
  const [screen, setScreen] = useState<"login" | "dashboard">("login");
  const [agent, setAgent] = useState<any>(null);
  const [channels, setChannels] = useState<any[]>([]);
  const [customers, setCustomers] = useState<any[]>([]);
  const [earnings, setEarnings] = useState<any[]>([]);
  const [withdrawals, setWithdrawals] = useState<any[]>([]);
  const [recentCommissions, setRecentCommissions] = useState<any[]>([]);
  const [tab, setTab] = useState<"dashboard" | "customers" | "earnings" | "withdrawals">("dashboard");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [withdrawAmount, setWithdrawAmount] = useState("");
  const [withdrawLoading, setWithdrawLoading] = useState(false);

  useEffect(() => {
    if (getToken()) loadDashboard();
  }, []);

  const login = async (e: React.FormEvent) => {
    e.preventDefault(); setError("");
    try {
      const data = await authApi.login(username, password);
      if (data.user?.role !== "agent") { setError("ไม่มีสิทธิ์เข้าถึง Agent Portal"); return; }
      setToken(data.token);
      loadDashboard();
    } catch (err: any) { setError(err.error || "เข้าสู่ระบบไม่สำเร็จ"); }
  };

  const loadDashboard = async () => {
    try {
      const data = await agentApi.dashboard();
      setAgent(data.agent);
      setChannels(data.channels || []);
      setRecentCommissions(data.recent_commissions || []);
      setScreen("dashboard");
    } catch { clearToken(); setScreen("login"); }
  };

  const loadCustomers = async () => {
    try {
      const data = await agentApi.customers();
      setCustomers(data.customers || []);
    } catch (err) { console.error(err); }
  };

  const loadEarnings = async () => {
    try {
      const data = await agentApi.earnings();
      setEarnings(data.by_channel || []);
    } catch (err) { console.error(err); }
  };

  const loadWithdrawals = async () => {
    try {
      const data = await agentApi.withdrawals();
      setWithdrawals(data.withdrawals || []);
    } catch (err) { console.error(err); }
  };

  const switchTab = (t: typeof tab) => {
    setTab(t);
    if (t === "customers") loadCustomers();
    if (t === "earnings") loadEarnings();
    if (t === "withdrawals") loadWithdrawals();
  };

  const handleWithdraw = async (e: React.FormEvent) => {
    e.preventDefault();
    const amt = Number(withdrawAmount);
    if (!amt || amt <= 0) return;
    setWithdrawLoading(true); setMessage("");
    try {
      await agentApi.requestWithdrawal(amt);
      setMessage("ส่งคำขอถอนเงินสำเร็จ");
      setWithdrawAmount("");
      loadWithdrawals();
      loadDashboard();
    } catch (err: any) {
      setMessage(err.error || "ถอนเงินไม่สำเร็จ");
    } finally { setWithdrawLoading(false); }
  };

  if (screen === "login") return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-b from-sun-red-dark to-sun-black">
      <form onSubmit={login} className="card w-full max-w-md">
        <div className="text-center mb-8">
          <h1 className="text-4xl font-bold text-sun-gold-light">☀️</h1>
          <h2 className="text-2xl font-bold text-sun-gold-light mt-2">THE SUN POKER</h2>
          <p className="text-sun-gold/60 mt-1">Agent Portal</p>
        </div>
        {error && <div className="bg-red-900/50 border border-red-500 text-red-300 px-4 py-2 rounded mb-4 text-sm">{error}</div>}
        <input placeholder="Username" value={username} onChange={(e) => setUsername(e.target.value)} className="input-field mb-4" required />
        <input type="password" placeholder="Password" value={password} onChange={(e) => setPassword(e.target.value)} className="input-field mb-6" required />
        <button type="submit" className="btn-primary w-full">เข้าสู่ระบบ</button>
      </form>
    </div>
  );

  return (
    <div className="min-h-screen bg-gradient-to-b from-sun-red-dark to-sun-black">
      {/* Header */}
      <div className="bg-sun-black/80 border-b border-sun-gold/20 px-6 py-4 flex justify-between items-center">
        <div>
          <h1 className="text-xl font-bold text-sun-gold-light">☀️ Agent Portal</h1>
          <p className="text-sun-gold/60 text-sm">สวัสดี, {agent?.display_name} ({agent?.agent_code})</p>
        </div>
        <button onClick={async () => {
          try { await authApi.logout(); } catch {}
          clearToken(); setScreen("login");
        }} className="text-red-400 text-sm hover:text-red-300">ออกจากระบบ</button>
      </div>

      {/* Tabs */}
      <div className="flex gap-2 px-6 pt-4">
        {(["dashboard", "customers", "earnings", "withdrawals"] as const).map((t) => (
          <button key={t} onClick={() => switchTab(t)}
            className={`px-4 py-2 rounded-lg text-sm font-bold ${tab === t ? "bg-sun-red text-sun-gold-light" : "bg-sun-black/50 text-sun-gold/50 hover:text-sun-gold"}`}>
            {t === "dashboard" ? "📊 Dashboard" : t === "customers" ? "👥 ลูกค้า" : t === "earnings" ? "💰 รายได้" : "🏦 ถอนเงิน"}
          </button>
        ))}
      </div>

      {message && (
        <div className="mx-6 mt-4 bg-green-900/50 border border-green-500 text-green-300 px-4 py-2 rounded flex justify-between">
          <span>{message}</span><button onClick={() => setMessage("")}>✕</button>
        </div>
      )}

      <div className="p-6">
        {/* ===== DASHBOARD TAB ===== */}
        {tab === "dashboard" && (
          <div>
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
              <div className="stat-card">
                <p className="text-sun-gold/60 text-sm">สถานะ</p>
                <p className={`text-xl font-bold mt-2 ${agent?.status === "active" ? "text-green-400" : "text-red-400"}`}>
                  {agent?.status === "active" ? "🟢 Active" : "🔴 ระงับ"}
                </p>
              </div>
              <div className="stat-card">
                <p className="text-sun-gold/60 text-sm">Commission Rate</p>
                <p className="text-3xl font-bold text-sun-gold-light mt-2">{agent?.default_commission_rate}%</p>
              </div>
              <div className="stat-card">
                <p className="text-sun-gold/60 text-sm">รายได้รวม</p>
                <p className="text-3xl font-bold text-green-400 mt-2">{Number(agent?.total_earned || 0).toLocaleString()} 🪙</p>
              </div>
              <div className="stat-card">
                <p className="text-sun-gold/60 text-sm">ยอดถอนได้</p>
                <p className="text-3xl font-bold text-sun-gold-light mt-2">{Number(agent?.available_balance || 0).toLocaleString()} 🪙</p>
              </div>
            </div>

            {/* Channels */}
            <div className="card mb-6">
              <h2 className="text-lg font-bold text-sun-gold-light mb-4">🔗 Referral Links</h2>
              <div className="space-y-3">
                {channels.map((ch) => (
                  <div key={ch.id} className="bg-sun-black/50 rounded-lg p-4 flex justify-between items-center">
                    <div>
                      <p className="text-white font-bold text-sm">{ch.channel_name}</p>
                      <p className="text-sun-gold/40 text-xs break-all">{ch.referral_url}</p>
                      <p className="text-sun-gold/40 text-xs mt-1">
                        Rate: {ch.commission_rate || agent?.default_commission_rate}% | คลิก: {ch.click_count || 0} | สมัคร: {ch.register_count || 0}
                      </p>
                    </div>
                    <div className="flex items-center gap-3">
                      <span className={ch.is_active ? "text-green-400 text-xs" : "text-red-400 text-xs"}>
                        {ch.is_active ? "🟢 เปิด" : "🔴 ปิด"}
                      </span>
                      <button onClick={() => { navigator.clipboard.writeText(ch.referral_url); setMessage("คัดลอก link แล้ว"); }}
                        className="text-sun-gold-light text-xs hover:underline">📋 คัดลอก</button>
                    </div>
                  </div>
                ))}
                {channels.length === 0 && <p className="text-sun-gold/30 text-sm">ยังไม่มี referral link</p>}
              </div>
            </div>

            {/* Recent Commissions */}
            <div className="card">
              <h2 className="text-lg font-bold text-sun-gold-light mb-4">💰 Commission ล่าสุด</h2>
              {recentCommissions.length > 0 ? (
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-sun-gold/60 border-b border-sun-gold/20">
                      <th className="text-left py-2">วันที่</th>
                      <th className="text-left py-2">ลูกค้า</th>
                      <th className="text-right py-2">ยอดเติม</th>
                      <th className="text-right py-2">Commission</th>
                    </tr>
                  </thead>
                  <tbody>
                    {recentCommissions.map((c: any, i: number) => (
                      <tr key={i} className="table-row">
                        <td className="py-2 text-xs">{new Date(c.created_at).toLocaleString("th")}</td>
                        <td className="py-2">{c.username}</td>
                        <td className="py-2 text-right">{Number(c.topup_amount).toLocaleString()} 🪙</td>
                        <td className="py-2 text-right text-green-400">+{Number(c.commission_amount).toLocaleString()} 🪙</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              ) : <p className="text-sun-gold/30 text-sm">ยังไม่มี commission</p>}
            </div>
          </div>
        )}

        {/* ===== CUSTOMERS TAB ===== */}
        {tab === "customers" && (
          <div className="card">
            <h2 className="text-lg font-bold text-sun-gold-light mb-4">👥 ลูกค้าทั้งหมด ({customers.length})</h2>
            {customers.length > 0 ? (
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-sun-gold/60 border-b border-sun-gold/20">
                    <th className="text-left py-2">Username</th>
                    <th className="text-left py-2">ชื่อ</th>
                    <th className="text-left py-2">ช่องทาง</th>
                    <th className="text-right py-2">เหรียญ</th>
                    <th className="text-left py-2">สมัครเมื่อ</th>
                  </tr>
                </thead>
                <tbody>
                  {customers.map((c: any) => (
                    <tr key={c.id} className="table-row">
                      <td className="py-2">{c.username}</td>
                      <td className="py-2">{c.display_name || "-"}</td>
                      <td className="py-2 text-xs text-sun-gold/60">{c.channel_name || "-"}</td>
                      <td className="py-2 text-right">{Number(c.balance || 0).toLocaleString()} 🪙</td>
                      <td className="py-2 text-xs text-sun-gold/40">{new Date(c.referred_at).toLocaleDateString("th")}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            ) : <p className="text-sun-gold/30">ยังไม่มีลูกค้า</p>}
          </div>
        )}

        {/* ===== EARNINGS TAB ===== */}
        {tab === "earnings" && (
          <div className="card">
            <h2 className="text-lg font-bold text-sun-gold-light mb-4">💰 รายได้แยกตามช่องทาง</h2>
            {earnings.length > 0 ? (
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-sun-gold/60 border-b border-sun-gold/20">
                    <th className="text-left py-2">ช่องทาง</th>
                    <th className="text-right py-2">Rate</th>
                    <th className="text-right py-2">รายการ</th>
                    <th className="text-right py-2">ยอดเติมรวม</th>
                    <th className="text-right py-2">Commission รวม</th>
                  </tr>
                </thead>
                <tbody>
                  {earnings.map((e: any, i: number) => (
                    <tr key={i} className="table-row">
                      <td className="py-2 font-bold">{e.channel_name}</td>
                      <td className="py-2 text-right">{e.commission_rate || agent?.default_commission_rate}%</td>
                      <td className="py-2 text-right">{e.tx_count}</td>
                      <td className="py-2 text-right">{Number(e.total_topup).toLocaleString()} 🪙</td>
                      <td className="py-2 text-right text-green-400">{Number(e.total_commission).toLocaleString()} 🪙</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            ) : <p className="text-sun-gold/30">ยังไม่มีข้อมูลรายได้</p>}
          </div>
        )}

        {/* ===== WITHDRAWALS TAB ===== */}
        {tab === "withdrawals" && (
          <div>
            {/* Withdraw Form */}
            <div className="card mb-6">
              <h2 className="text-lg font-bold text-sun-gold-light mb-4">🏦 ขอถอนเงิน</h2>
              <div className="bg-sun-black/50 rounded-lg p-4 mb-4">
                <p className="text-sun-gold/60 text-sm">ยอดถอนได้</p>
                <p className="text-2xl font-bold text-sun-gold-light">{Number(agent?.available_balance || 0).toLocaleString()} 🪙</p>
              </div>
              <form onSubmit={handleWithdraw} className="flex gap-4">
                <input type="number" placeholder="จำนวนเงินที่ต้องการถอน" value={withdrawAmount}
                  onChange={(e) => setWithdrawAmount(e.target.value)} className="input-field flex-1" required min="1" />
                <button type="submit" disabled={withdrawLoading} className="btn-primary">
                  {withdrawLoading ? "กำลังส่ง..." : "ส่งคำขอถอน"}
                </button>
              </form>
            </div>

            {/* Withdrawal History */}
            <div className="card">
              <h2 className="text-lg font-bold text-sun-gold-light mb-4">📋 ประวัติการถอน</h2>
              {withdrawals.length > 0 ? (
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-sun-gold/60 border-b border-sun-gold/20">
                      <th className="text-left py-2">วันที่</th>
                      <th className="text-right py-2">จำนวน</th>
                      <th className="text-center py-2">สถานะ</th>
                    </tr>
                  </thead>
                  <tbody>
                    {withdrawals.map((w: any) => (
                      <tr key={w.id} className="table-row">
                        <td className="py-2 text-xs">{new Date(w.created_at).toLocaleString("th")}</td>
                        <td className="py-2 text-right">{Number(w.amount).toLocaleString()} 🪙</td>
                        <td className="py-2 text-center">
                          <span className={`text-xs px-2 py-1 rounded ${
                            w.status === "approved" ? "bg-green-900 text-green-300" :
                            w.status === "rejected" ? "bg-red-900 text-red-300" :
                            "bg-yellow-900 text-yellow-300"
                          }`}>
                            {w.status === "approved" ? "✅ อนุมัติ" : w.status === "rejected" ? "❌ ปฏิเสธ" : "⏳ รอดำเนินการ"}
                          </span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              ) : <p className="text-sun-gold/30">ยังไม่มีประวัติการถอน</p>}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}