"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";

export default function AgentsPage() {
  const [agents, setAgents] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [showCreate, setShowCreate] = useState(false);
  const [selectedAgent, setSelectedAgent] = useState<any>(null);
  const [channels, setChannels] = useState<any[]>([]);
  const [message, setMessage] = useState("");
  const [createResult, setCreateResult] = useState<any>(null);
  const [mainTab, setMainTab] = useState<"agents" | "withdrawals">("agents");
  const [withdrawals, setWithdrawals] = useState<any[]>([]);
  const [wdFilter, setWdFilter] = useState("");

  // Form สร้าง Agent
  const [form, setForm] = useState({
    display_name: "", username: "", password: "", email: "",
    phone: "", line_id: "", commission_rate: 10,
    bank_name: "", bank_account: "", bank_holder: "",
    channel_name: "Default",
  });

  const loadAgents = async () => {
    try {
      const data = await api("/api/admin/agents");
      setAgents(data.agents);
      setTotal(data.total);
    } catch (err) { console.error(err); }
  };

  useEffect(() => { loadAgents(); }, []);

  const [recentCustomers, setRecentCustomers] = useState<any[]>([]);

  const viewAgent = async (id: string) => {
    const data = await api(`/api/admin/agents/${id}`);
    setSelectedAgent(data.agent);
    setChannels(data.channels);
    setRecentCustomers(data.recent_customers || []);
    setShowCreate(false);
  };

  const createAgent = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const data = await api("/api/admin/agents", {
        method: "POST",
        body: JSON.stringify({
          ...form,
          bank_info: { bank: form.bank_name, account: form.bank_account, name: form.bank_holder },
          channels: [{ name: form.channel_name, commission_rate: form.commission_rate }],
        }),
      });
      setCreateResult(data);
      setMessage("สร้าง Agent สำเร็จ");
      loadAgents();
    } catch (err: any) {
      setMessage(err.error || "สร้างไม่สำเร็จ");
    }
  };

  const toggleAgent = async (id: string, currentStatus: string) => {
    const action = currentStatus === "active" ? "suspend" : "activate";
    await api(`/api/admin/agents/${id}/${action}`, { method: "PUT" });
    setMessage(action === "suspend" ? "ระงับ Agent สำเร็จ" : "เปิดใช้งาน Agent สำเร็จ");
    loadAgents();
    if (selectedAgent?.id === id) viewAgent(id);
  };

  const addChannel = async () => {
    if (!selectedAgent) return;
    const name = prompt("ชื่อช่องทางใหม่ (เช่น Facebook, Line, TikTok):");
    if (!name) return;
    await api(`/api/admin/agents/${selectedAgent.id}/channels`, {
      method: "POST", body: JSON.stringify({ channel_name: name }),
    });
    setMessage(`สร้างช่องทาง "${name}" สำเร็จ`);
    viewAgent(selectedAgent.id);
  };

  const toggleChannel = async (chId: string) => {
    if (!selectedAgent) return;
    await api(`/api/admin/agents/${selectedAgent.id}/channels/${chId}/toggle`, { method: "PUT" });
    viewAgent(selectedAgent.id);
  };

  const loadWithdrawals = async (status?: string) => {
    try {
      const params = status ? `?status=${status}` : "";
      const data = await api(`/api/admin/agents/withdrawals/all${params}`);
      setWithdrawals(data.withdrawals || []);
    } catch (err) { console.error(err); }
  };

  const approveWithdrawal = async (wId: string) => {
    if (!confirm("ยืนยันอนุมัติการถอนเงิน?")) return;
    await api(`/api/admin/agents/withdrawals/${wId}/approve`, { method: "PUT" });
    setMessage("อนุมัติสำเร็จ"); loadWithdrawals(wdFilter);
  };

  const rejectWithdrawal = async (wId: string) => {
    const reason = prompt("เหตุผลที่ปฏิเสธ:");
    if (reason === null) return;
    await api(`/api/admin/agents/withdrawals/${wId}/reject`, { method: "PUT", body: JSON.stringify({ reason }) });
    setMessage("ปฏิเสธสำเร็จ"); loadWithdrawals(wdFilter);
  };

  return (
    <div>
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 mb-6">
        <div className="flex flex-wrap items-center gap-4">
          <h1 className="text-2xl font-bold text-sun-gold-light">🤝 จัดการ Agent</h1>
          <div className="flex flex-wrap gap-2">
            <button onClick={() => setMainTab("agents")}
              className={`px-4 py-2 rounded-lg text-sm font-bold ${mainTab === "agents" ? "bg-sun-red text-sun-gold-light" : "bg-sun-black/50 text-sun-gold/50"}`}>
              👥 Agent ({agents.length})
            </button>
            <button onClick={() => { setMainTab("withdrawals"); loadWithdrawals(); }}
              className={`px-4 py-2 rounded-lg text-sm font-bold ${mainTab === "withdrawals" ? "bg-sun-red text-sun-gold-light" : "bg-sun-black/50 text-sun-gold/50"}`}>
              🏦 คำขอถอนเงิน
            </button>
          </div>
        </div>
        {mainTab === "agents" && (
          <button onClick={() => { setShowCreate(true); setSelectedAgent(null); setCreateResult(null); }} className="btn-green">
            ➕ สร้าง Agent ใหม่
          </button>
        )}
      </div>

      {message && (
        <div className="bg-green-900/50 border border-green-500 text-green-300 px-4 py-2 rounded mb-4 flex justify-between">
          <span>{message}</span>
          <button onClick={() => setMessage("")}>✕</button>
        </div>
      )}

      <details className="mb-4 text-xs text-sun-gold/50 bg-sun-black/30 rounded-lg p-3">
        <summary className="cursor-pointer text-sun-gold/70 font-bold">ℹ️ วิธีใช้งานหน้านี้</summary>
        <div className="mt-2 space-y-1">
          <p>📋 <b>หน้านี้คืออะไร:</b> จัดการตัวแทน (Agent) ที่ช่วยหาผู้เล่นใหม่</p>
          <p>🤝 <b>Agent คืออะไร:</b> คนที่ได้ Link ชวนเพื่อน — ถ้ามีคนสมัครผ่าน Link จะนับเป็นลูกค้าของ Agent</p>
          <p>🔍 <b>ขั้นตอนสร้าง Agent:</b></p>
          <p className="pl-4">1. กด "สร้าง Agent ใหม่" → กรอกชื่อ, username, password, commission %</p>
          <p className="pl-4">2. ระบบจะสร้าง Link สำหรับชวนคน + บัญชีเข้า Agent Portal</p>
          <p className="pl-4">3. ส่งข้อมูลทั้งหมดให้ Agent (กดปุ่มคัดลอก)</p>
          <p>💰 <b>Commission:</b> Agent ได้ค่าคอมมิชชั่นจากการเล่นของลูกค้า (คำนวณที่หน้า Commission)</p>
          <p>🏦 <b>คำขอถอนเงิน:</b> กดแท็บ "คำขอถอนเงิน" เพื่ออนุมัติ/ปฏิเสธเมื่อ Agent ขอถอน</p>
        </div>
      </details>

      {mainTab === "agents" && <div className="flex flex-col lg:flex-row gap-4 lg:gap-6">
        {/* ตาราง Agent */}
        <div className="card flex-1">
          <div className="overflow-x-auto">
          <table className="w-full text-sm min-w-[650px]">
            <thead>
              <tr className="text-sun-gold/60 border-b border-sun-gold/20">
                <th className="text-left py-2">Code</th>
                <th className="text-left py-2">ชื่อ</th>
                <th className="text-left py-2">Username</th>
                <th className="text-right py-2">Rate</th>
                <th className="text-right py-2">ลูกค้า</th>
                <th className="text-right py-2">รายได้รวม</th>
                <th className="text-left py-2">สถานะ</th>
                <th className="text-left py-2">จัดการ</th>
              </tr>
            </thead>
            <tbody>
              {agents.map((a) => (
                <tr key={a.id} className="table-row cursor-pointer" onClick={() => viewAgent(a.id)}>
                  <td className="py-2 font-mono text-xs">{a.agent_code}</td>
                  <td className="py-2">{a.display_name}</td>
                  <td className="py-2 text-sun-gold/60">{a.username}</td>
                  <td className="py-2 text-right">{a.default_commission_rate}%</td>
                  <td className="py-2 text-right">{a.customer_count}</td>
                  <td className="py-2 text-right">{Number(a.total_earned).toLocaleString()} 🪙</td>
                  <td className="py-2">
                    {a.status === "active"
                      ? <span className="text-green-400 text-xs">🟢 Active</span>
                      : <span className="text-red-400 text-xs">🔴 ระงับ</span>}
                  </td>
                  <td className="py-2" onClick={(e) => e.stopPropagation()}>
                    <button onClick={() => toggleAgent(a.id, a.status)}
                      className={`text-xs ${a.status === "active" ? "text-red-400" : "text-green-400"}`}>
                      {a.status === "active" ? "ระงับ" : "เปิด"}
                    </button>
                  </td>
                </tr>
              ))}
              {agents.length === 0 && (
                <tr><td colSpan={8} className="py-8 text-center text-sun-gold/30">ยังไม่มี Agent</td></tr>
              )}
            </tbody>
          </table>
          </div>
        </div>

        {/* Panel ขวา: สร้าง Agent หรือ ดูรายละเอียด */}
        {showCreate && (
          <div className="card w-full lg:w-[420px]">
            <h2 className="text-lg font-bold text-sun-gold-light mb-4">➕ สร้าง Agent ใหม่</h2>

            {createResult ? (
              <div className="space-y-4">
                <div className="bg-green-900/50 border border-green-500 text-green-300 p-4 rounded">
                  <p className="font-bold mb-2">✅ สร้าง Agent สำเร็จ</p>
                  <p className="text-sm">ข้อมูลสำหรับส่งให้ Agent:</p>
                </div>
                <div className="bg-sun-black/50 p-4 rounded text-sm space-y-2">
                  <p>🤝 Agent: <span className="text-white font-bold">{createResult.agent.display_name} ({createResult.agent.agent_code})</span></p>
                  <p>🔗 Portal: <span className="text-white">{createResult.credentials.portal_url}</span></p>
                  <p>👤 Username: <span className="text-white font-mono">{createResult.credentials.username}</span></p>
                  <p>🔑 Password: <span className="text-white font-mono">{createResult.credentials.password}</span></p>
                  <p>📊 Commission: <span className="text-white">{createResult.agent.default_commission_rate}%</span></p>
                  {createResult.channels.map((ch: any) => (
                    <p key={ch.id}>🔗 Link: <span className="text-white text-xs break-all">{ch.referral_url}</span></p>
                  ))}
                </div>
                <button onClick={() => {
                  const text = `THE SUN POKER - Agent\nPortal: ${createResult.credentials.portal_url}\nUsername: ${createResult.credentials.username}\nPassword: ${createResult.credentials.password}\nLink: ${createResult.channels[0]?.referral_url}`;
                  navigator.clipboard.writeText(text);
                  setMessage("คัดลอกข้อมูลแล้ว");
                }} className="btn-primary w-full">📋 คัดลอกข้อมูลทั้งหมด</button>
                <button onClick={() => { setShowCreate(false); setCreateResult(null); }} className="btn-black w-full">ปิด</button>
              </div>
            ) : (
              <form onSubmit={createAgent} className="space-y-3">
                <input placeholder="ชื่อ-นามสกุล *" value={form.display_name} onChange={(e) => setForm({...form, display_name: e.target.value})} className="input-field" required />
                <input placeholder="Username (สำหรับ login) *" value={form.username} onChange={(e) => setForm({...form, username: e.target.value})} className="input-field" required />
                <input placeholder="Password *" value={form.password} onChange={(e) => setForm({...form, password: e.target.value})} className="input-field" required />
                <input placeholder="Email" value={form.email} onChange={(e) => setForm({...form, email: e.target.value})} className="input-field" />
                <input placeholder="เบอร์โทร" value={form.phone} onChange={(e) => setForm({...form, phone: e.target.value})} className="input-field" />
                <input placeholder="Line ID" value={form.line_id} onChange={(e) => setForm({...form, line_id: e.target.value})} className="input-field" />
                <div>
                  <label className="text-sun-gold/60 text-xs">Commission Rate (%)</label>
                  <input type="number" value={form.commission_rate} onChange={(e) => setForm({...form, commission_rate: Number(e.target.value)})} className="input-field" min="0" max="100" step="0.5" />
                </div>
                <div>
                  <label className="text-sun-gold/60 text-xs">ชื่อช่องทางแรก</label>
                  <input placeholder="เช่น Facebook, Line" value={form.channel_name} onChange={(e) => setForm({...form, channel_name: e.target.value})} className="input-field" />
                </div>
                <p className="text-sun-gold/40 text-xs">บัญชีธนาคาร (สำหรับถอนเงิน)</p>
                <input placeholder="ธนาคาร (เช่น SCB)" value={form.bank_name} onChange={(e) => setForm({...form, bank_name: e.target.value})} className="input-field" />
                <input placeholder="เลขบัญชี" value={form.bank_account} onChange={(e) => setForm({...form, bank_account: e.target.value})} className="input-field" />
                <input placeholder="ชื่อบัญชี" value={form.bank_holder} onChange={(e) => setForm({...form, bank_holder: e.target.value})} className="input-field" />
                <button type="submit" className="btn-green w-full">✅ สร้าง Agent</button>
                <button type="button" onClick={() => setShowCreate(false)} className="btn-black w-full">ยกเลิก</button>
              </form>
            )}
          </div>
        )}

        {/* Panel รายละเอียด Agent */}
        {selectedAgent && !showCreate && (
          <div className="card w-full lg:w-[420px]">
            <div className="flex justify-between items-start mb-4">
              <h2 className="text-lg font-bold text-sun-gold-light">🤝 {selectedAgent.display_name}</h2>
              <button onClick={() => setSelectedAgent(null)} className="text-sun-gold/40">✕</button>
            </div>
            <div className="space-y-2 text-sm mb-4">
              <p><span className="text-sun-gold/60">Code:</span> <span className="text-white font-mono">{selectedAgent.agent_code}</span></p>
              <p><span className="text-sun-gold/60">Username:</span> <span className="text-white">{selectedAgent.username}</span></p>
              <p><span className="text-sun-gold/60">Line:</span> <span className="text-white">{selectedAgent.line_id || "-"}</span></p>
              <p><span className="text-sun-gold/60">Commission:</span> <span className="text-sun-gold-light font-bold">{selectedAgent.default_commission_rate}%</span></p>
              <p><span className="text-sun-gold/60">รายได้รวม:</span> <span className="text-white">{Number(selectedAgent.total_earned).toLocaleString()} 🪙</span></p>
              <p><span className="text-sun-gold/60">ยอดถอนได้:</span> <span className="text-white">{Number(selectedAgent.available_balance).toLocaleString()} 🪙</span></p>
            </div>

            {/* Channels / Links */}
            <div className="border-t border-sun-gold/20 pt-4">
              <div className="flex justify-between items-center mb-3">
                <p className="text-sun-gold/60 text-sm font-bold">🔗 Referral Links</p>
                <button onClick={addChannel} className="text-sun-gold-light text-xs hover:underline">+ เพิ่ม Link</button>
              </div>
              {channels.map((ch) => (
                <div key={ch.id} className="bg-sun-black/50 rounded p-3 mb-2 text-xs">
                  <div className="flex justify-between items-center mb-1">
                    <span className="text-white font-bold">{ch.channel_name}</span>
                    <button onClick={() => toggleChannel(ch.id)}
                      className={ch.is_active ? "text-green-400" : "text-red-400"}>
                      {ch.is_active ? "🟢 เปิด" : "🔴 ปิด"}
                    </button>
                  </div>
                  <p className="text-sun-gold/40 break-all">{ch.referral_url}</p>
                  <p className="text-sun-gold/40 mt-1">Rate: {ch.commission_rate || selectedAgent.default_commission_rate}% | คลิก: {ch.click_count} | สมัคร: {ch.register_count}</p>
                  <button onClick={() => { navigator.clipboard.writeText(ch.referral_url); setMessage("คัดลอก link แล้ว"); }}
                    className="text-sun-gold-light mt-1 hover:underline">📋 คัดลอก Link</button>
                </div>
              ))}
            </div>

            {/* ลูกค้าล่าสุด */}
            <div className="border-t border-sun-gold/20 pt-4 mt-4">
              <p className="text-sun-gold/60 text-sm font-bold mb-3">👥 ลูกค้าล่าสุด ({recentCustomers.length})</p>
              <div className="max-h-48 overflow-auto space-y-1">
                {recentCustomers.map((c: any) => (
                  <div key={c.user_id || c.id} className="flex justify-between items-center bg-sun-black/50 rounded px-3 py-2 text-xs">
                    <div>
                      <span className="text-white">{c.display_name || c.username}</span>
                      <span className="text-sun-gold/40 ml-2">@{c.username}</span>
                    </div>
                    <span className="text-sun-gold/40">{new Date(c.referred_at).toLocaleDateString("th")}</span>
                  </div>
                ))}
                {recentCustomers.length === 0 && <p className="text-sun-gold/30 text-xs">ยังไม่มีลูกค้า</p>}
              </div>
            </div>
          </div>
        )}
      </div>}

      {/* ===== WITHDRAWALS TAB ===== */}
      {mainTab === "withdrawals" && (
        <div className="card">
          <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 mb-4">
            <h2 className="text-lg font-bold text-sun-gold-light">🏦 คำขอถอนเงิน Agent</h2>
            <div className="flex flex-wrap gap-2">
              {["", "pending", "approved", "rejected"].map((s) => (
                <button key={s} onClick={() => { setWdFilter(s); loadWithdrawals(s); }}
                  className={`text-xs px-3 py-1 rounded ${wdFilter === s ? "bg-sun-red text-white" : "bg-sun-black/50 text-sun-gold/50"}`}>
                  {s === "" ? "ทั้งหมด" : s === "pending" ? "⏳ รอ" : s === "approved" ? "✅ อนุมัติ" : "❌ ปฏิเสธ"}
                </button>
              ))}
            </div>
          </div>
          {withdrawals.length > 0 ? (
            <div className="overflow-x-auto">
            <table className="w-full text-sm min-w-[550px]">
              <thead>
                <tr className="text-sun-gold/60 border-b border-sun-gold/20">
                  <th className="text-left py-2">วันที่</th>
                  <th className="text-left py-2">Agent</th>
                  <th className="text-left py-2">Code</th>
                  <th className="text-right py-2">จำนวน</th>
                  <th className="text-center py-2">สถานะ</th>
                  <th className="text-left py-2">จัดการ</th>
                </tr>
              </thead>
              <tbody>
                {withdrawals.map((w: any) => (
                  <tr key={w.id} className="table-row">
                    <td className="py-2 text-xs">{new Date(w.created_at).toLocaleString("th")}</td>
                    <td className="py-2">{w.agent_name}</td>
                    <td className="py-2 font-mono text-xs">{w.agent_code}</td>
                    <td className="py-2 text-right font-bold">{Number(w.amount).toLocaleString()} 🪙</td>
                    <td className="py-2 text-center">
                      <span className={`text-xs px-2 py-1 rounded ${
                        w.status === "approved" ? "bg-green-900 text-green-300" :
                        w.status === "rejected" ? "bg-red-900 text-red-300" :
                        "bg-yellow-900 text-yellow-300"
                      }`}>
                        {w.status === "approved" ? "✅ อนุมัติ" : w.status === "rejected" ? "❌ ปฏิเสธ" : "⏳ รอ"}
                      </span>
                    </td>
                    <td className="py-2 space-x-2">
                      {w.status === "pending" && (
                        <>
                          <button onClick={() => approveWithdrawal(w.id)} className="text-green-400 text-xs hover:text-green-300">✅ อนุมัติ</button>
                          <button onClick={() => rejectWithdrawal(w.id)} className="text-red-400 text-xs hover:text-red-300">❌ ปฏิเสธ</button>
                        </>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            </div>
          ) : <p className="text-sun-gold/30">ไม่มีคำขอถอนเงิน</p>}
        </div>
      )}
    </div>
  );
}
