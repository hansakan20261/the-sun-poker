"use client";
import { Fragment, useEffect, useState } from "react";
import { api } from "@/lib/api";

export default function AgentCommissionPage() {
  const [agents, setAgents] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [expandedSA, setExpandedSA] = useState<Set<string>>(new Set());
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editForm, setEditForm] = useState({ agent_level: "", hand_commission_rate: 0, parent_agent_id: "" });
  const [message, setMessage] = useState("");

  useEffect(() => { loadData(); }, []);

  const loadData = async () => {
    try {
      const data = await api("/api/admin/agents");
      setAgents(data.agents || []);
      setLoading(false);
    } catch (err) { console.error(err); setLoading(false); }
  };

  const superAgents = agents.filter(a => a.agent_level === "super_agent");
  const regularAgents = agents.filter(a => a.agent_level !== "super_agent");

  const getChildAgents = (saId: string) => regularAgents.filter(a => a.parent_agent_id === saId);
  const getOrphanAgents = () => regularAgents.filter(a => !a.parent_agent_id);

  const totalHands = agents.reduce((s, a) => s + Number(a.total_hands || 0), 0);
  const totalCustomers = agents.reduce((s, a) => s + Number(a.customer_count || 0), 0);

  const toggleExpand = (id: string) => {
    const next = new Set(expandedSA);
    if (next.has(id)) next.delete(id); else next.add(id);
    setExpandedSA(next);
  };

  const startEdit = (agent: any) => {
    setEditingId(agent.id);
    setEditForm({
      agent_level: agent.agent_level || "agent",
      hand_commission_rate: agent.hand_commission_rate || agent.default_commission_rate || 0.3,
      parent_agent_id: agent.parent_agent_id || "",
    });
  };

  const saveEdit = async () => {
    if (!editingId) return;
    try {
      await api(`/api/admin/agents/${editingId}`, {
        method: "PUT",
        body: JSON.stringify({
          agent_level: editForm.agent_level,
          hand_commission_rate: editForm.hand_commission_rate,
          parent_agent_id: editForm.parent_agent_id || null,
        }),
      });
      setMessage("บันทึกสำเร็จ");
      setEditingId(null);
      loadData();
    } catch (err: any) {
      setMessage(err.error || "บันทึกไม่สำเร็จ");
    }
  };

  const calcCommission = (hands: number, rate: number) => {
    return (hands * rate / 100).toFixed(1);
  };

  if (loading) return <p className="text-sun-gold text-center py-10">กำลังโหลด...</p>;

  return (
    <div>
      <h1 className="text-2xl font-bold text-sun-gold-light mb-2">💰 Commission แฮนด์ (3 ชั้น)</h1>
      <p className="text-sun-gold/50 text-sm mb-6">จัดการลำดับชั้น &amp; คำนวณ commission อัตโนมัติจากจำนวนแฮนด์</p>

      <details className="mb-4 text-xs text-sun-gold/50 bg-sun-black/30 rounded-lg p-3">
        <summary className="cursor-pointer text-sun-gold/70 font-bold">ℹ️ วิธีใช้งานหน้านี้</summary>
        <div className="mt-2 space-y-1">
          <p>📋 <b>หน้านี้คืออะไร:</b> ตั้งค่าและดู Commission ของ Agent แบบ 3 ชั้น</p>
          <p>🏗️ <b>โครงสร้าง 3 ชั้น:</b></p>
          <p className="pl-4">• 👑 Master (เจ้าของระบบ) → เห็นทั้งหมด</p>
          <p className="pl-4">• 🟢 Super Agent → ดูแล Agent หลายคน ได้ % สูงกว่า</p>
          <p className="pl-4">• 🔵 Agent → หาลูกค้าโดยตรง ได้ % ต่ำกว่า</p>
          <p>💰 <b>การคำนวณ:</b> Commission = จำนวนมือที่ลูกค้าเล่น × อัตรา% ที่ตั้งไว้</p>
          <p className="pl-4">ตัวอย่าง: ลูกค้าเล่น 10,000 มือ × 0.3% = Agent ได้ 30 เหรียญ</p>
          <p>✏️ <b>วิธีใช้:</b> กด ✏️ ที่แถว Agent → ตั้งค่าระดับ (Super Agent/Agent) + อัตรา% + สังกัด</p>
        </div>
      </details>

      {message && (
        <div className="bg-green-900/50 border border-green-500 text-green-300 px-4 py-2 rounded mb-4 flex justify-between">
          <span>{message}</span><button onClick={() => setMessage("")}>✕</button>
        </div>
      )}

      {/* Summary Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
        <div className="stat-card">
          <p className="text-sun-gold/60 text-sm">👑 Master</p>
          <p className="text-xl font-bold text-sun-gold-light mt-1">เจ้าของระบบ</p>
          <p className="text-xs text-sun-gold/40">เห็นทั้งหมด</p>
        </div>
        <div className="stat-card">
          <p className="text-sun-gold/60 text-sm">🟢 Super Agent</p>
          <p className="text-2xl font-bold text-green-400 mt-1">{superAgents.length}</p>
          <p className="text-xs text-sun-gold/40">ลูกค้า: {superAgents.reduce((s, a) => s + Number(a.customer_count || 0), 0)}</p>
        </div>
        <div className="stat-card">
          <p className="text-sun-gold/60 text-sm">🔵 Agent</p>
          <p className="text-2xl font-bold text-blue-400 mt-1">{regularAgents.length}</p>
          <p className="text-xs text-sun-gold/40">ลูกค้า: {regularAgents.reduce((s, a) => s + Number(a.customer_count || 0), 0)}</p>
        </div>
        <div className="stat-card">
          <p className="text-sun-gold/60 text-sm">🎰 แฮนด์รวมทั้งระบบ</p>
          <p className="text-2xl font-bold text-sun-gold-light mt-1">{totalHands.toLocaleString()}</p>
          <p className="text-xs text-sun-gold/40">ลูกค้า {totalCustomers} คน</p>
        </div>
      </div>

      {/* Hierarchy Table */}
      <div className="card">
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 mb-4">
          <h2 className="text-lg font-bold text-sun-gold-light">📊 ตาราง Commission</h2>
          <p className="text-xs text-sun-gold/40">คลิกแถวเพื่อแก้ไข | Commission = แฮนด์ × อัตรา%</p>
        </div>

        <div className="overflow-x-auto">
        <table className="w-full text-sm min-w-[700px]">
          <thead>
            <tr className="text-sun-gold/60 border-b border-sun-gold/20">
              <th className="text-left py-2 w-8"></th>
              <th className="text-left py-2">ระดับ</th>
              <th className="text-left py-2">ชื่อ / Code</th>
              <th className="text-right py-2">อัตรา %</th>
              <th className="text-right py-2">ลูกค้า</th>
              <th className="text-right py-2">แฮนด์</th>
              <th className="text-right py-2">Commission</th>
              <th className="text-left py-2">สังกัด</th>
              <th className="text-left py-2">จัดการ</th>
            </tr>
          </thead>
          <tbody>
            {/* Super Agents */}
            {superAgents.map((sa) => {
              const children = getChildAgents(sa.id);
              const isExpanded = expandedSA.has(sa.id);
              const saHands = Number(sa.total_hands || 0) + children.reduce((s, c) => s + Number(c.total_hands || 0), 0);
              const saRate = Number(sa.hand_commission_rate || sa.default_commission_rate || 1);
              return (
                <Fragment key={sa.id}>
                  <tr className="border-b border-sun-gold/10 hover:bg-green-900/10">
                    <td className="py-2">
                      {children.length > 0 && (
                        <button onClick={() => toggleExpand(sa.id)} className="text-sun-gold/60">{isExpanded ? "▼" : "▶"}</button>
                      )}
                    </td>
                    <td className="py-2"><span className="bg-green-800 text-green-200 text-xs px-2 py-0.5 rounded">Super Agent</span></td>
                    <td className="py-2">
                      <span className="text-white font-bold">{sa.display_name}</span>
                      <span className="text-sun-gold/40 text-xs ml-2">{sa.agent_code}</span>
                    </td>
                    <td className="py-2 text-right text-green-400 font-bold">{saRate}%</td>
                    <td className="py-2 text-right">{Number(sa.customer_count || 0) + children.reduce((s, c) => s + Number(c.customer_count || 0), 0)}</td>
                    <td className="py-2 text-right font-bold">{saHands.toLocaleString()}</td>
                    <td className="py-2 text-right text-green-400 font-bold">{calcCommission(saHands, saRate)}</td>
                    <td className="py-2 text-sun-gold/40 text-xs">Master</td>
                    <td className="py-2">
                      <button onClick={() => startEdit(sa)} className="text-sun-gold-light text-xs hover:underline">✏️</button>
                    </td>
                  </tr>
                  {/* Children agents */}
                  {isExpanded && children.map((ag) => {
                    const agRate = Number(ag.hand_commission_rate || ag.default_commission_rate || 0.3);
                    const agHands = Number(ag.total_hands || 0);
                    return (
                      <tr key={ag.id} className="border-b border-sun-gold/5 hover:bg-blue-900/10">
                        <td className="py-2"></td>
                        <td className="py-2 pl-4"><span className="bg-blue-800 text-blue-200 text-xs px-2 py-0.5 rounded">Agent</span></td>
                        <td className="py-2 pl-4">
                          <span className="text-white">{ag.display_name}</span>
                          <span className="text-sun-gold/40 text-xs ml-2">{ag.agent_code}</span>
                        </td>
                        <td className="py-2 text-right text-blue-400">{agRate}%</td>
                        <td className="py-2 text-right">{ag.customer_count}</td>
                        <td className="py-2 text-right">{agHands.toLocaleString()}</td>
                        <td className="py-2 text-right text-blue-400">{calcCommission(agHands, agRate)}</td>
                        <td className="py-2 text-sun-gold/40 text-xs">{sa.display_name}</td>
                        <td className="py-2">
                          <button onClick={() => startEdit(ag)} className="text-sun-gold-light text-xs hover:underline">✏️</button>
                        </td>
                      </tr>
                    );
                  })}
                </Fragment>
              );
            })}

            {/* Orphan Agents (directly under Master) */}
            {getOrphanAgents().map((ag) => {
              const agRate = Number(ag.hand_commission_rate || ag.default_commission_rate || 0.3);
              const agHands = Number(ag.total_hands || 0);
              return (
                <tr key={ag.id} className="border-b border-sun-gold/10 hover:bg-blue-900/10">
                  <td className="py-2"></td>
                  <td className="py-2"><span className="bg-blue-800 text-blue-200 text-xs px-2 py-0.5 rounded">Agent</span></td>
                  <td className="py-2">
                    <span className="text-white">{ag.display_name}</span>
                    <span className="text-sun-gold/40 text-xs ml-2">{ag.agent_code}</span>
                  </td>
                  <td className="py-2 text-right text-blue-400">{agRate}%</td>
                  <td className="py-2 text-right">{ag.customer_count}</td>
                  <td className="py-2 text-right">{agHands.toLocaleString()}</td>
                  <td className="py-2 text-right text-blue-400">{calcCommission(agHands, agRate)}</td>
                  <td className="py-2 text-sun-gold/40 text-xs">Master (ตรง)</td>
                  <td className="py-2">
                    <button onClick={() => startEdit(ag)} className="text-sun-gold-light text-xs hover:underline">✏️</button>
                  </td>
                </tr>
              );
            })}

            {agents.length === 0 && (
              <tr><td colSpan={9} className="py-8 text-center text-sun-gold/30">ยังไม่มี Agent — สร้างที่หน้า Agent ก่อน</td></tr>
            )}
          </tbody>
        </table>
        </div>
      </div>

      {/* Edit Modal */}
      {editingId && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50">
          <div className="card w-full max-w-md">
            <h3 className="text-lg font-bold text-sun-gold-light mb-4">✏️ แก้ไขข้อมูล Agent</h3>
            <div className="space-y-4">
              <div>
                <label className="text-sun-gold/60 text-xs">ระดับ</label>
                <select value={editForm.agent_level} onChange={(e) => setEditForm({...editForm, agent_level: e.target.value})} className="input-field">
                  <option value="agent">Agent</option>
                  <option value="super_agent">Super Agent</option>
                </select>
              </div>
              <div>
                <label className="text-sun-gold/60 text-xs">อัตรา Commission (%)</label>
                <input type="number" step="0.1" min="0" max="100" value={editForm.hand_commission_rate}
                  onChange={(e) => setEditForm({...editForm, hand_commission_rate: Number(e.target.value)})} className="input-field" />
                <p className="text-sun-gold/30 text-xs mt-1">เช่น Master ให้ Super Agent 1%, Super Agent ให้ Agent 0.3%</p>
              </div>
              {editForm.agent_level === "agent" && (
                <div>
                  <label className="text-sun-gold/60 text-xs">สังกัด Super Agent</label>
                  <select value={editForm.parent_agent_id} onChange={(e) => setEditForm({...editForm, parent_agent_id: e.target.value})} className="input-field">
                    <option value="">ไม่มี (ขึ้นตรง Master)</option>
                    {superAgents.map(sa => (
                      <option key={sa.id} value={sa.id}>{sa.display_name} ({sa.agent_code})</option>
                    ))}
                  </select>
                </div>
              )}
              <div className="flex gap-3 pt-2">
                <button onClick={saveEdit} className="btn-green flex-1">💾 บันทึก</button>
                <button onClick={() => setEditingId(null)} className="btn-black flex-1">ยกเลิก</button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* How it works */}
      <div className="card mt-6">
        <h2 className="text-lg font-bold text-sun-gold-light mb-3">📋 วิธีใช้งาน</h2>
        <div className="text-sm text-sun-gold/70 space-y-2">
          <p>1. สร้าง Agent ที่หน้า <a href="/agents" className="text-sun-gold-light underline">🤝 Agent</a></p>
          <p>2. กลับมาหน้านี้ → กด ✏️ เพื่อตั้งค่า <strong className="text-white">ระดับ</strong> (Super Agent / Agent) และ <strong className="text-white">อัตรา %</strong></p>
          <p>3. ถ้าเป็น Agent → เลือก <strong className="text-white">สังกัด Super Agent</strong> ที่ต้องการ</p>
          <p>4. ระบบคำนวณ Commission อัตโนมัติจาก <strong className="text-white">จำนวนแฮนด์ × อัตรา%</strong></p>
          <p className="text-sun-gold/40 mt-3 border-t border-sun-gold/10 pt-3">
            ตัวอย่าง: ลูกค้าเล่น 10,000 แฮนด์ → Super Agent (1%) ได้ 100 | Agent (0.3%) ได้ 30 — เบิกกับหัวตามลำดับ
          </p>
        </div>
      </div>
    </div>
  );
}
