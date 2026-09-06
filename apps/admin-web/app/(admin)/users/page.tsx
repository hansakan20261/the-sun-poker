"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";

export default function UsersPage() {
  const [users, setUsers] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [search, setSearch] = useState("");
  const [roleFilter, setRoleFilter] = useState("");
  const [statusFilter, setStatusFilter] = useState("");
  const [page, setPage] = useState(0);
  const [selectedUser, setSelectedUser] = useState<any>(null);
  const [message, setMessage] = useState("");
  const [showSetPassword, setShowSetPassword] = useState(false);
  const [newPassword, setNewPassword] = useState("");
  const [showCreate, setShowCreate] = useState(false);
  const [createForm, setCreateForm] = useState({ username: "", password: "", email: "", phone: "", display_name: "", role: "player", initial_balance: 0 });
  const [createLoading, setCreateLoading] = useState(false);
  const limit = 15;

  const loadUsers = async () => {
    try {
      const params = new URLSearchParams();
      if (search) params.set("search", search);
      if (roleFilter) params.set("role", roleFilter);
      if (statusFilter) params.set("status", statusFilter);
      params.set("limit", String(limit));
      params.set("offset", String(page * limit));
      const data = await api(`/api/admin/users?${params}`);
      setUsers(data.users);
      setTotal(data.total);
    } catch (err) { console.error(err); }
  };

  useEffect(() => { loadUsers(); }, [page, roleFilter, statusFilter]);

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    setPage(0);
    loadUsers();
  };

  const viewUser = async (id: string) => {
    const data = await api(`/api/admin/users/${id}`);
    setSelectedUser(data.user);
  };

  const suspendUser = async (id: string) => {
    if (!confirm("ยืนยันระงับบัญชีผู้ใช้นี้?")) return;
    await api(`/api/admin/users/${id}/suspend`, { method: "PUT", body: JSON.stringify({ reason: "Admin action" }) });
    setMessage("ระงับบัญชีสำเร็จ");
    loadUsers();
    if (selectedUser?.id === id) viewUser(id);
  };

  const unsuspendUser = async (id: string) => {
    await api(`/api/admin/users/${id}/unsuspend`, { method: "PUT" });
    setMessage("ปลดระงับสำเร็จ");
    loadUsers();
    if (selectedUser?.id === id) viewUser(id);
  };

  const resetPassword = async (id: string) => {
    if (!confirm("ยืนยันรีเซ็ตรหัสผ่าน?")) return;
    const data = await api(`/api/admin/users/${id}/reset-password`, { method: "PUT" });
    setMessage(`รีเซ็ตสำเร็จ — รหัสผ่านใหม่: ${data.new_password}`);
  };

  const setPassword = async (id: string) => {
    if (!newPassword || newPassword.length < 6) {
      setMessage("❌ รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร");
      return;
    }
    try {
      await api(`/api/admin/users/${id}/set-password`, {
        method: "PUT",
        body: JSON.stringify({ new_password: newPassword }),
      });
      setMessage(`✅ ตั้งรหัสผ่านใหม่สำเร็จสำหรับ ${selectedUser.username}`);
      setShowSetPassword(false);
      setNewPassword("");
    } catch (err: any) {
      setMessage(`❌ ${err.error || "เกิดข้อผิดพลาด"}`);
    }
  };

  const changeRole = async (id: string, role: string) => {
    await api(`/api/admin/users/${id}/role`, { method: "PUT", body: JSON.stringify({ role }) });
    setMessage(`เปลี่ยน role เป็น ${role} สำเร็จ`);
    loadUsers();
    if (selectedUser?.id === id) viewUser(id);
  };

  return (
    <div>
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 mb-6">
        <h1 className="text-2xl font-bold text-sun-gold-light">👥 จัดการผู้ใช้งาน</h1>
        <button onClick={() => { setShowCreate(true); setSelectedUser(null); }} className="btn-green">➕ สร้างบัญชีใหม่</button>
      </div>

      <details className="mb-4 text-xs text-sun-gold/50 bg-sun-black/30 rounded-lg p-3">
        <summary className="cursor-pointer text-sun-gold/70 font-bold">ℹ️ วิธีใช้งานหน้านี้</summary>
        <div className="mt-2 space-y-1">
          <p>📋 <b>หน้านี้คืออะไร:</b> จัดการบัญชีผู้เล่นทั้งหมด</p>
          <p>🔍 <b>ขั้นตอนการใช้งาน:</b></p>
          <p className="pl-4">1. ค้นหาผู้ใช้ด้วย username, email หรือ เบอร์โทร</p>
          <p className="pl-4">2. กรองตาม Role (ผู้เล่น/Agent/Admin) หรือสถานะ (ปกติ/ระงับ)</p>
          <p className="pl-4">3. คลิกที่แถวเพื่อดูรายละเอียด</p>
          <p>⚡ <b>สิ่งที่ทำได้:</b></p>
          <p className="pl-4">• ระงับบัญชี = ผู้เล่นจะเข้าเกมไม่ได้จนกว่าจะปลดระงับ</p>
          <p className="pl-4">• รีเซ็ตรหัสผ่าน = สร้างรหัสใหม่แบบสุ่มให้ผู้เล่น</p>
          <p className="pl-4">• เปลี่ยน Role = ปรับสิทธิ์ (เช่น เลื่อนเป็น Admin)</p>
          <p className="pl-4">• เติม/ถอนเหรียญ = ลิงก์ไปหน้าเติมเหรียญโดยตรง</p>
          <p>💡 <b>หมายเหตุ:</b> เหรียญที่แสดง = ยอดคงเหลือปัจจุบันของผู้เล่น</p>
        </div>
      </details>

      {message && (
        <div className="bg-green-900/50 border border-green-500 text-green-300 px-4 py-2 rounded mb-4 flex justify-between">
          <span>{message}</span>
          <button onClick={() => setMessage("")} className="text-green-400">✕</button>
        </div>
      )}

      {/* ค้นหา + กรอง */}
      <div className="card mb-6">
        <form onSubmit={handleSearch} className="flex gap-4 flex-wrap">
          <input type="text" placeholder="ค้นหา username / email / phone" value={search}
            onChange={(e) => setSearch(e.target.value)} className="input-field flex-1 min-w-[200px]" />
          <select value={roleFilter} onChange={(e) => { setRoleFilter(e.target.value); setPage(0); }}
            className="input-field w-40">
            <option value="">ทุก Role</option>
            <option value="player">Player</option>
            <option value="agent">Agent</option>
            <option value="club_owner">Club Owner</option>
            <option value="club_admin">Club Admin</option>
            <option value="admin">Admin</option>
            <option value="super_admin">Super Admin</option>
          </select>
          <select value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value); setPage(0); }}
            className="input-field w-40">
            <option value="">ทุกสถานะ</option>
            <option value="active">Active</option>
            <option value="suspended">Suspended</option>
          </select>
          <button type="submit" className="btn-primary">ค้นหา</button>
        </form>
        <p className="text-sun-gold/40 text-sm mt-2">ทั้งหมด {total} คน</p>
      </div>

      <div className="flex flex-col lg:flex-row gap-4 lg:gap-6">
        {/* ตารางผู้ใช้ */}
        <div className={`card ${selectedUser ? "flex-1" : "w-full"}`}>
          <div className="overflow-x-auto">
          <table className="w-full text-sm min-w-[600px]">
            <thead>
              <tr className="text-sun-gold/60 border-b border-sun-gold/20">
                <th className="text-left py-2">Username</th>
                <th className="text-left py-2">ชื่อ</th>
                <th className="text-left py-2">Role</th>
                <th className="text-right py-2">เหรียญ</th>
                <th className="text-left py-2">สถานะ</th>
                <th className="text-left py-2">เข้าล่าสุด</th>
                <th className="text-left py-2">จัดการ</th>
              </tr>
            </thead>
            <tbody>
              {users.map((u) => (
                <tr key={u.id} className="table-row cursor-pointer" onClick={() => viewUser(u.id)}>
                  <td className="py-2">{u.username}</td>
                  <td className="py-2">{u.display_name || "-"}</td>
                  <td className="py-2">
                    <span className={`text-xs px-2 py-1 rounded ${
                      u.role === "super_admin" ? "bg-purple-900 text-purple-300" :
                      u.role === "admin" ? "bg-blue-900 text-blue-300" :
                      u.role === "agent" ? "bg-yellow-900 text-yellow-300" : "bg-sun-black text-sun-gold/60"
                    }`}>{u.role}</span>
                  </td>
                  <td className="py-2 text-right">{Number(u.balance || 0).toLocaleString()} 🪙</td>
                  <td className="py-2">
                    {u.is_suspended
                      ? <span className="text-red-400 text-xs">🔴 ระงับ</span>
                      : <span className="text-green-400 text-xs">🟢 ปกติ</span>}
                  </td>
                  <td className="py-2 text-xs text-sun-gold/40">
                    {u.last_login_at ? new Date(u.last_login_at).toLocaleString("th") : "-"}
                  </td>
                  <td className="py-2" onClick={(e) => e.stopPropagation()}>
                    {u.is_suspended
                      ? <button onClick={() => unsuspendUser(u.id)} className="text-green-400 hover:text-green-300 text-xs">ปลดระงับ</button>
                      : <button onClick={() => suspendUser(u.id)} className="text-red-400 hover:text-red-300 text-xs">ระงับ</button>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>

          </div>
          {/* Pagination */}
          <div className="flex justify-between items-center mt-4 text-sm">
            <button onClick={() => setPage(Math.max(0, page - 1))} disabled={page === 0}
              className="text-sun-gold/60 hover:text-sun-gold disabled:opacity-30">◀ ก่อนหน้า</button>
            <span className="text-sun-gold/40">หน้า {page + 1} / {Math.ceil(total / limit) || 1}</span>
            <button onClick={() => setPage(page + 1)} disabled={(page + 1) * limit >= total}
              className="text-sun-gold/60 hover:text-sun-gold disabled:opacity-30">ถัดไป ▶</button>
          </div>
        </div>

        {/* Panel สร้างบัญชีใหม่ */}
        {showCreate && (
          <div className="card w-full lg:w-96">
            <div className="flex justify-between items-start mb-4">
              <h2 className="text-lg font-bold text-sun-gold-light">➕ สร้างบัญชีใหม่</h2>
              <button onClick={() => setShowCreate(false)} className="text-sun-gold/40 hover:text-sun-gold">✕</button>
            </div>
            <form onSubmit={async (e) => {
              e.preventDefault();
              setCreateLoading(true);
              try {
                const data = await api("/api/admin/users", { method: "POST", body: JSON.stringify(createForm) });
                setMessage(`✅ สร้างบัญชี ${data.user.username} สำเร็จ`);
                setShowCreate(false);
                setCreateForm({ username: "", password: "", email: "", phone: "", display_name: "", role: "player", initial_balance: 0 });
                loadUsers();
              } catch (err: any) { setMessage(`❌ ${err.error || "สร้างไม่สำเร็จ"}`); }
              finally { setCreateLoading(false); }
            }} className="space-y-3">
              <input placeholder="Username *" value={createForm.username} onChange={(e) => setCreateForm({...createForm, username: e.target.value})} className="input-field" required />
              <input placeholder="Password *" value={createForm.password} onChange={(e) => setCreateForm({...createForm, password: e.target.value})} className="input-field" required />
              <input placeholder="ชื่อที่แสดง" value={createForm.display_name} onChange={(e) => setCreateForm({...createForm, display_name: e.target.value})} className="input-field" />
              <input placeholder="Email" value={createForm.email} onChange={(e) => setCreateForm({...createForm, email: e.target.value})} className="input-field" />
              <input placeholder="เบอร์โทร" value={createForm.phone} onChange={(e) => setCreateForm({...createForm, phone: e.target.value})} className="input-field" />
              <div>
                <label className="text-sun-gold/60 text-xs">Role</label>
                <select value={createForm.role} onChange={(e) => setCreateForm({...createForm, role: e.target.value})} className="input-field">
                  <option value="player">Player</option>
                  <option value="agent">Agent</option>
                  <option value="club_owner">Club Owner</option>
                  <option value="club_admin">Club Admin</option>
                  <option value="admin">Admin</option>
                  <option value="super_admin">Super Admin</option>
                </select>
              </div>
              <div>
                <label className="text-sun-gold/60 text-xs">เหรียญเริ่มต้น</label>
                <input type="number" min="0" value={createForm.initial_balance} onChange={(e) => setCreateForm({...createForm, initial_balance: Number(e.target.value)})} className="input-field" />
              </div>
              <button type="submit" disabled={createLoading} className="btn-green w-full">
                {createLoading ? "กำลังสร้าง..." : "✅ สร้างบัญชี"}
              </button>
            </form>
          </div>
        )}

        {/* Panel รายละเอียดผู้ใช้ */}
        {selectedUser && (
          <div className="card w-full lg:w-96">
            <div className="flex justify-between items-start mb-4">
              <h2 className="text-lg font-bold text-sun-gold-light">👤 รายละเอียด</h2>
              <button onClick={() => setSelectedUser(null)} className="text-sun-gold/40 hover:text-sun-gold">✕</button>
            </div>

            <div className="space-y-3 text-sm">
              <div>
                <span className="text-sun-gold/60">Username:</span>
                <span className="ml-2 text-white">{selectedUser.username}</span>
              </div>
              <div>
                <span className="text-sun-gold/60">ชื่อ:</span>
                <span className="ml-2 text-white">{selectedUser.display_name || "-"}</span>
              </div>
              <div>
                <span className="text-sun-gold/60">Email:</span>
                <span className="ml-2 text-white">{selectedUser.email || "-"}</span>
              </div>
              <div>
                <span className="text-sun-gold/60">เบอร์โทร:</span>
                <span className="ml-2 text-white">{selectedUser.phone || "-"}</span>
              </div>
              <div>
                <span className="text-sun-gold/60">เหรียญ:</span>
                <span className="ml-2 text-sun-gold-light font-bold">{Number(selectedUser.balance || 0).toLocaleString()} 🪙</span>
              </div>
              <div>
                <span className="text-sun-gold/60">Role:</span>
                <span className={`ml-2 text-xs px-2 py-1 rounded ${
                  selectedUser.role === "super_admin" ? "bg-purple-900 text-purple-300" :
                  selectedUser.role === "admin" ? "bg-blue-900 text-blue-300" :
                  selectedUser.role === "agent" ? "bg-yellow-900 text-yellow-300" : "bg-sun-black text-sun-gold/60"
                }`}>{selectedUser.role}</span>
                <button onClick={() => {
                  const roles = ["player", "agent", "club_owner", "club_admin", "admin", "super_admin"];
                  const current = roles.indexOf(selectedUser.role);
                  const newRole = prompt(`เปลี่ยน Role เป็น:\n${roles.map((r, i) => `${i + 1}. ${r}${r === selectedUser.role ? " (ปัจจุบัน)" : ""}`).join("\n")}\n\nพิมพ์ชื่อ role:`);
                  if (newRole && roles.includes(newRole)) changeRole(selectedUser.id, newRole);
                }} className="ml-2 text-sun-gold/40 hover:text-sun-gold-light text-xs">✏️ แก้ไข</button>
              </div>
              <div>
                <span className="text-sun-gold/60">สถานะ:</span>
                {selectedUser.is_suspended
                  ? <span className="ml-2 text-red-400">🔴 ระงับ</span>
                  : <span className="ml-2 text-green-400">🟢 ปกติ</span>}
              </div>
              <div>
                <span className="text-sun-gold/60">VIP Level:</span>
                <span className="ml-2 text-white">{selectedUser.vip_level || 0}</span>
              </div>
              <div>
                <span className="text-sun-gold/60">เกมที่เล่น:</span>
                <span className="ml-2 text-white">{selectedUser.total_games || 0} เกม</span>
              </div>
              <div>
                <span className="text-sun-gold/60">ชนะ:</span>
                <span className="ml-2 text-white">{selectedUser.total_wins || 0} ({selectedUser.win_rate || 0}%)</span>
              </div>
              <div>
                <span className="text-sun-gold/60">สมัครเมื่อ:</span>
                <span className="ml-2 text-white text-xs">{new Date(selectedUser.created_at).toLocaleString("th")}</span>
              </div>

              {/* ข้อมูล Agent ที่ผูก */}
              <div className="border-t border-sun-gold/20 pt-3 mt-3">
                <p className="text-sun-gold/60 text-xs mb-2">🤝 สมาชิกของ Agent</p>
                {selectedUser.agent_code ? (
                  <div className="bg-sun-black/50 rounded-lg p-3 space-y-1">
                    <div>
                      <span className="text-sun-gold/60">Agent:</span>
                      <span className="ml-2 text-sun-gold-light font-bold">{selectedUser.agent_name} ({selectedUser.agent_code})</span>
                    </div>
                    <div>
                      <span className="text-sun-gold/60">ช่องทาง:</span>
                      <span className="ml-2 text-white">{selectedUser.channel_name}</span>
                    </div>
                    <div>
                      <span className="text-sun-gold/60">Ref Code:</span>
                      <span className="ml-2 text-white text-xs">{selectedUser.referral_code}</span>
                    </div>
                    <div>
                      <span className="text-sun-gold/60">สมัครผ่าน Agent เมื่อ:</span>
                      <span className="ml-2 text-white text-xs">{new Date(selectedUser.referred_at).toLocaleString("th")}</span>
                    </div>
                  </div>
                ) : (
                  <p className="text-sun-gold/30 text-xs">ไม่ได้มาจาก Agent (สมัครตรง)</p>
                )}
              </div>
            </div>

            <div className="mt-6 space-y-2">
              <button onClick={() => resetPassword(selectedUser.id)} className="btn-primary w-full text-sm py-2">
                🔑 รีเซ็ตรหัสผ่าน (สุ่ม)
              </button>
              <button onClick={() => setShowSetPassword(!showSetPassword)} className="btn-primary w-full text-sm py-2" style={{ background: '#1e40af' }}>
                🔐 ตั้งรหัสผ่านใหม่
              </button>
              {showSetPassword && (
                <div className="bg-sun-black/50 rounded-lg p-3 space-y-2">
                  <input
                    type="text"
                    placeholder="พิมพ์รหัสผ่านใหม่ (อย่างน้อย 6 ตัว)"
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    className="input-field w-full text-sm"
                  />
                  <button onClick={() => setPassword(selectedUser.id)} className="btn-primary w-full text-sm py-2">
                    ✅ ยืนยันตั้งรหัสผ่าน
                  </button>
                </div>
              )}
              {selectedUser.is_suspended
                ? <button onClick={() => unsuspendUser(selectedUser.id)} className="btn-green w-full text-sm py-2">
                    ✅ ปลดระงับ
                  </button>
                : <button onClick={() => suspendUser(selectedUser.id)} className="btn-danger w-full text-sm py-2">
                    🚫 ระงับบัญชี
                  </button>}
              <a href={`/coins?user=${selectedUser.username}`} className="btn-black w-full text-sm py-2 block text-center">
                💰 เติม/ถอนเหรียญ
              </a>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
