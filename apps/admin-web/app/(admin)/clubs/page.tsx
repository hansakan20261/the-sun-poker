"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";

export default function ClubsPage() {
  const [clubs, setClubs] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [search, setSearch] = useState("");
  const [selectedClub, setSelectedClub] = useState<any>(null);
  const [members, setMembers] = useState<any[]>([]);
  const [clubTables, setClubTables] = useState<any[]>([]);
  const [clubTournaments, setClubTournaments] = useState<any[]>([]);
  const [message, setMessage] = useState("");

  const loadClubs = async () => {
    const params = search ? `?search=${search}` : "";
    const data = await api(`/api/admin/clubs${params}`);
    setClubs(data.clubs); setTotal(data.total);
  };

  useEffect(() => { loadClubs(); }, []);

  const viewClub = async (id: string) => {
    const data = await api(`/api/admin/clubs/${id}`);
    setSelectedClub(data.club);
    setMembers(data.members || []);
    setClubTables(data.tables || []);
    setClubTournaments(data.tournaments || []);
  };

  const toggleClub = async (id: string) => {
    await api(`/api/admin/clubs/${id}/toggle`, { method: "PUT" });
    setMessage("เปลี่ยนสถานะคลับสำเร็จ"); loadClubs();
    if (selectedClub?.id === id) viewClub(id);
  };

  const removeMember = async (clubId: string, userId: string) => {
    if (!confirm("ยืนยันลบสมาชิกออกจากคลับ?")) return;
    await api(`/api/admin/clubs/${clubId}/members/${userId}`, { method: "DELETE" });
    setMessage("ลบสมาชิกสำเร็จ"); viewClub(clubId);
  };

  return (
    <div>
      <h1 className="text-2xl font-bold text-sun-gold-light mb-6">🏠 จัดการคลับ</h1>

      <details className="mb-4 text-xs text-sun-gold/50 bg-sun-black/30 rounded-lg p-3">
        <summary className="cursor-pointer text-sun-gold/70 font-bold">ℹ️ วิธีใช้งานหน้านี้</summary>
        <div className="mt-2 space-y-1">
          <p>📋 <b>หน้านี้คืออะไร:</b> จัดการคลับ (กลุ่มผู้เล่นที่เล่นด้วยกัน)</p>
          <p>👁 <b>ข้อมูลที่แสดง:</b></p>
          <p className="pl-4">• ชื่อคลับ + เจ้าของ = ใครเป็นคนสร้าง</p>
          <p className="pl-4">• สมาชิก/สูงสุด = จำนวนคนในคลับ vs จำนวนที่รับได้</p>
          <p className="pl-4">• สถานะ = 🟢เปิด (ใช้งานได้) หรือ 🔴ปิด (ถูกระงับ)</p>
          <p>⚡ <b>สิ่งที่ทำได้:</b></p>
          <p className="pl-4">• คลิกที่คลับ = ดูสมาชิก, ห้องเล่น, ทัวร์นาเมนต์ภายในคลับ</p>
          <p className="pl-4">• ปิดคลับ = ห้ามสมาชิกเข้าเล่นในคลับชั่วคราว</p>
          <p className="pl-4">• ลบสมาชิก = ถอดคนออกจากคลับ</p>
        </div>
      </details>
      {message && (
        <div className="bg-green-900/50 border border-green-500 text-green-300 px-4 py-2 rounded mb-4 flex justify-between">
          <span>{message}</span><button onClick={() => setMessage("")}>✕</button>
        </div>
      )}

      <div className="card mb-6">
        <form onSubmit={(e) => { e.preventDefault(); loadClubs(); }} className="flex gap-4">
          <input placeholder="ค้นหาชื่อคลับ / เจ้าของ" value={search}
            onChange={(e) => setSearch(e.target.value)} className="input-field flex-1" />
          <button type="submit" className="btn-primary">ค้นหา</button>
        </form>
        <p className="text-sun-gold/40 text-sm mt-2">ทั้งหมด {total} คลับ</p>
      </div>

      <div className="flex flex-col lg:flex-row gap-4 lg:gap-6">
        <div className={`card ${selectedClub ? "flex-1" : "w-full"}`}>
          <div className="overflow-x-auto">
          <table className="w-full text-sm min-w-[600px]">
            <thead>
              <tr className="text-sun-gold/60 border-b border-sun-gold/20">
                <th className="text-left py-2">ชื่อคลับ</th>
                <th className="text-left py-2">เจ้าของ</th>
                <th className="text-center py-2">สมาชิก</th>
                <th className="text-center py-2">สูงสุด</th>
                <th className="text-center py-2">สถานะ</th>
                <th className="text-left py-2">สร้างเมื่อ</th>
                <th className="text-left py-2">จัดการ</th>
              </tr>
            </thead>
            <tbody>
              {clubs.map((c) => (
                <tr key={c.id} className="table-row cursor-pointer" onClick={() => viewClub(c.id)}>
                  <td className="py-2 font-bold">{c.name}</td>
                  <td className="py-2 text-sun-gold/60">{c.owner_name || c.owner_username}</td>
                  <td className="py-2 text-center">{c.member_count}</td>
                  <td className="py-2 text-center">{c.max_members}</td>
                  <td className="py-2 text-center">
                    {c.is_active ? <span className="text-green-400 text-xs">🟢 เปิด</span> : <span className="text-red-400 text-xs">🔴 ปิด</span>}
                  </td>
                  <td className="py-2 text-xs text-sun-gold/40">{new Date(c.created_at).toLocaleDateString("th")}</td>
                  <td className="py-2" onClick={(e) => e.stopPropagation()}>
                    <button onClick={() => toggleClub(c.id)} className={`text-xs ${c.is_active ? "text-red-400" : "text-green-400"}`}>
                      {c.is_active ? "ปิด" : "เปิด"}
                    </button>
                  </td>
                </tr>
              ))}
              {clubs.length === 0 && (
                <tr><td colSpan={7} className="py-8 text-center text-sun-gold/30">ยังไม่มีคลับ</td></tr>
              )}
            </tbody>
          </table>
          </div>
        </div>

        {selectedClub && (
          <div className="card w-full lg:w-96">
            <div className="flex justify-between items-start mb-4">
              <h2 className="text-lg font-bold text-sun-gold-light">🏠 {selectedClub.name}</h2>
              <button onClick={() => setSelectedClub(null)} className="text-sun-gold/40">✕</button>
            </div>
            <div className="space-y-2 text-sm mb-4">
              <p><span className="text-sun-gold/60">เจ้าของ:</span> <span className="text-white">{selectedClub.owner_name || selectedClub.owner_username}</span></p>
              <p><span className="text-sun-gold/60">คำอธิบาย:</span> <span className="text-white">{selectedClub.description || "-"}</span></p>
              <p><span className="text-sun-gold/60">สถานะ:</span> {selectedClub.is_active ? <span className="text-green-400">🟢 เปิด</span> : <span className="text-red-400">🔴 ปิด</span>}</p>
              <p><span className="text-sun-gold/60">สร้างเมื่อ:</span> <span className="text-white text-xs">{new Date(selectedClub.created_at).toLocaleString("th")}</span></p>
            </div>

            <div className="border-t border-sun-gold/20 pt-4">
              <p className="text-sun-gold/60 text-sm font-bold mb-3">👥 สมาชิก ({members.length})</p>
              <div className="max-h-60 overflow-auto space-y-1">
                {members.map((m) => (
                  <div key={m.id} className="flex justify-between items-center bg-sun-black/50 rounded px-3 py-2 text-xs">
                    <div>
                      <span className="text-white">{m.display_name || m.username}</span>
                      <span className={`ml-2 px-1 rounded ${m.role === "owner" ? "bg-yellow-900 text-yellow-300" : m.role === "moderator" ? "bg-blue-900 text-blue-300" : "bg-sun-black text-sun-gold/40"}`}>{m.role}</span>
                    </div>
                    {m.role !== "owner" && (
                      <button onClick={() => removeMember(selectedClub.id, m.user_id)} className="text-red-400/50 hover:text-red-400">✕</button>
                    )}
                  </div>
                ))}
                {members.length === 0 && <p className="text-sun-gold/30 text-xs">ยังไม่มีสมาชิก</p>}
              </div>
            </div>

            {/* ห้องเล่น (Cash Game) */}
            <div className="border-t border-sun-gold/20 pt-4 mt-4">
              <p className="text-sun-gold/60 text-sm font-bold mb-3">🎮 ห้องเล่น ({clubTables.length})</p>
              <div className="max-h-40 overflow-auto space-y-1">
                {clubTables.map((t: any) => (
                  <div key={t.id} className="flex justify-between items-center bg-sun-black/50 rounded px-3 py-2 text-xs">
                    <div>
                      <span className="text-white font-bold">{t.name || `Room #${t.room_code}`}</span>
                      <span className="text-sun-gold/40 ml-2">{t.name_th || t.game_type_name}</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="text-sun-gold/40">{t.small_blind}/{t.big_blind}</span>
                      <span className="text-sun-gold/40">{t.player_count}/{t.max_players}</span>
                      <span className={`px-1 rounded ${t.status === "playing" ? "bg-green-900 text-green-300" : t.status === "closed" ? "bg-red-900 text-red-300" : "bg-yellow-900 text-yellow-300"}`}>
                        {t.status === "playing" ? "🟢" : t.status === "closed" ? "🔴" : "🟡"}
                      </span>
                    </div>
                  </div>
                ))}
                {clubTables.length === 0 && <p className="text-sun-gold/30 text-xs">ยังไม่มีห้องเล่น</p>}
              </div>
            </div>

            {/* ทัวร์นาเมนต์ */}
            <div className="border-t border-sun-gold/20 pt-4 mt-4">
              <p className="text-sun-gold/60 text-sm font-bold mb-3">🏆 ทัวร์นาเมนต์ ({clubTournaments.length})</p>
              <div className="max-h-40 overflow-auto space-y-1">
                {clubTournaments.map((t: any) => (
                  <div key={t.id} className="flex justify-between items-center bg-sun-black/50 rounded px-3 py-2 text-xs">
                    <div>
                      <span className="text-white font-bold">{t.name}</span>
                      <span className="text-sun-gold/40 ml-2">{t.tournament_format}</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="text-sun-gold/40">{t.player_count}/{t.max_players}</span>
                      <span className={`px-1 rounded ${
                        t.status === "running" ? "bg-green-900 text-green-300" :
                        t.status === "finished" ? "bg-gray-700 text-gray-300" :
                        t.status === "registration" ? "bg-blue-900 text-blue-300" :
                        "bg-yellow-900 text-yellow-300"
                      }`}>{t.status}</span>
                    </div>
                  </div>
                ))}
                {clubTournaments.length === 0 && <p className="text-sun-gold/30 text-xs">ยังไม่มีทัวร์นาเมนต์</p>}
              </div>
            </div>

            <div className="mt-4">
              <button onClick={() => toggleClub(selectedClub.id)}
                className={`w-full text-sm py-2 ${selectedClub.is_active ? "btn-danger" : "btn-green"}`}>
                {selectedClub.is_active ? "🔴 ปิดคลับ" : "🟢 เปิดคลับ"}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
