"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";

export default function TournamentsPage() {
  const [tournaments, setTournaments] = useState<any[]>([]);
  const [gameTypes, setGameTypes] = useState<any[]>([]);
  const [showCreate, setShowCreate] = useState(false);
  const [selectedTournament, setSelectedTournament] = useState<any>(null);
  const [players, setPlayers] = useState<any[]>([]);
  const [message, setMessage] = useState("");
  const [form, setForm] = useState({
    name: "", game_type_id: "", tournament_format: "freezeout",
    entry_fee: 100, starting_chips: 10000, prize_pool: 0,
    max_players: 50, players_per_table: 9, scheduled_at: "",
  });

  const load = async () => {
    try {
      const [t, g] = await Promise.all([
        api("/api/admin/tournaments"),
        api("/api/admin/games/types"),
      ]);
      setTournaments(t.tournaments || []);
      setGameTypes(g.game_types || []);
    } catch (err) { console.error(err); }
  };

  useEffect(() => { load(); }, []);

  const createTournament = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await api("/api/admin/tournaments", { method: "POST", body: JSON.stringify(form) });
      setMessage("สร้างทัวร์นาเมนต์สำเร็จ"); setShowCreate(false); load();
    } catch (err: any) { setMessage(err.error || "สร้างไม่สำเร็จ"); }
  };

  const changeStatus = async (id: string, status: string) => {
    const labels: Record<string,string> = { registration: "เปิดรับสมัคร", running: "เริ่มแข่ง", finished: "จบการแข่ง", cancelled: "ยกเลิก" };
    if (!confirm(`ยืนยัน: ${labels[status] || status}?`)) return;
    await api(`/api/admin/tournaments/${id}/status`, { method: "PUT", body: JSON.stringify({ status }) });
    setMessage(`เปลี่ยนสถานะเป็น ${labels[status]} สำเร็จ`); load();
    if (selectedTournament?.id === id) viewTournament(id);
  };

  const viewTournament = async (id: string) => {
    try {
      const data = await api(`/api/admin/tournaments/${id}/results`);
      setSelectedTournament(data.tournament);
      setPlayers(data.players || []);
    } catch { /* use list data */ }
  };

  // เก็บ prize ที่กรอกไว้ก่อนกดแจก
  const [prizeMap, setPrizeMap] = useState<Record<string, number>>({});

  const updatePlayer = async (tournamentId: string, userId: string, updates: any) => {
    try {
      await api(`/api/admin/tournaments/${tournamentId}/players/${userId}`, {
        method: "PUT", body: JSON.stringify(updates),
      });
      setMessage("อัปเดตสำเร็จ");
      viewTournament(tournamentId);
    } catch (err: any) { setMessage(err.error || "อัปเดตไม่สำเร็จ"); }
  };

  const setPrizeForPlayer = (userId: string, amount: number) => {
    setPrizeMap(prev => ({ ...prev, [userId]: amount }));
  };

  const distributePrizes = async (tournamentId: string) => {
    // รวม prizes จาก prizeMap + ค่าที่มีอยู่แล้วใน players
    const prizes = players
      .filter((p: any) => (prizeMap[p.user_id] || p.prize_won) > 0)
      .map((p: any) => ({
        user_id: p.user_id,
        amount: prizeMap[p.user_id] ?? p.prize_won ?? 0,
        position: p.finish_position,
      }))
      .filter((p: any) => p.amount > 0);

    if (prizes.length === 0) { setMessage("กรุณากรอกเงินรางวัลก่อน"); return; }
    const total = prizes.reduce((s: number, p: any) => s + p.amount, 0);
    if (!confirm(`ยืนยันแจกเงินรางวัล ${prizes.length} คน รวม ${total.toLocaleString()} 🪙?`)) return;

    try {
      const data = await api(`/api/admin/tournaments/${tournamentId}/distribute-prizes`, {
        method: "POST", body: JSON.stringify({ prizes }),
      });
      setMessage(`แจกเงินรางวัลสำเร็จ ${data.distributed.length} คน`);
      setPrizeMap({});
      viewTournament(tournamentId);
    } catch (err: any) { setMessage(err.error || "แจกเงินไม่สำเร็จ"); }
  };

  const statusColor = (s: string) => {
    if (s === "registration") return "bg-blue-900 text-blue-300";
    if (s === "running") return "bg-green-900 text-green-300";
    if (s === "finished") return "bg-gray-700 text-gray-300";
    if (s === "cancelled") return "bg-red-900 text-red-300";
    return "bg-yellow-900 text-yellow-300";
  };
  const statusLabel = (s: string) => {
    const m: Record<string,string> = { draft: "📝 แบบร่าง", registration: "📢 รับสมัคร", running: "🟢 กำลังแข่ง", finished: "🏁 จบแล้ว", cancelled: "❌ ยกเลิก" };
    return m[s] || s;
  };

  return (
    <div>
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 mb-6">
        <h1 className="text-2xl font-bold text-sun-gold-light">🏆 ทัวร์นาเมนต์</h1>
        <button onClick={() => setShowCreate(!showCreate)} className="btn-green">➕ สร้างทัวร์นาเมนต์</button>
      </div>

      <details className="mb-4 text-xs text-sun-gold/50 bg-sun-black/30 rounded-lg p-3">
        <summary className="cursor-pointer text-sun-gold/70 font-bold">ℹ️ วิธีใช้งานหน้านี้</summary>
        <div className="mt-2 space-y-1">
          <p>📋 <b>หน้านี้คืออะไร:</b> สร้างและจัดการทัวร์นาเมนต์ (การแข่งขัน)</p>
          <p>🔍 <b>ขั้นตอนจัดทัวร์นาเมนต์:</b></p>
          <p className="pl-4">1. กด "สร้างทัวร์นาเมนต์" → กรอกชื่อ, เกม, ค่าสมัคร, เงินรางวัล</p>
          <p className="pl-4">2. เปลี่ยนสถานะเป็น "เปิดรับสมัคร" → ผู้เล่นจะเห็นในแอปและสมัครได้</p>
          <p className="pl-4">3. เมื่อพร้อม กด "เริ่มแข่ง" → ระบบจะจับคู่ผู้เล่นเข้าโต๊ะอัตโนมัติ</p>
          <p className="pl-4">4. เมื่อแข่งจบ กด "จบ" → กรอกอันดับ + เงินรางวัลแต่ละคน → กด "แจกเงินรางวัล"</p>
          <p>💰 <b>การแจกเงิน:</b> เงินรางวัลจะถูกเติมเข้าบัญชีผู้ชนะโดยอัตโนมัติ</p>
          <p>⚠️ <b>หมายเหตุ:</b> ค่าสมัครจะถูกหักจากบัญชีผู้เล่นตอนสมัคร</p>
        </div>
      </details>
      {message && <div className="bg-green-900/50 border border-green-500 text-green-300 px-4 py-2 rounded mb-4 flex justify-between"><span>{message}</span><button onClick={() => setMessage("")}>✕</button></div>}

      {showCreate && (
        <form onSubmit={createTournament} className="card mb-6 grid grid-cols-1 md:grid-cols-2 gap-3">
          <input placeholder="ชื่อทัวร์นาเมนต์ *" value={form.name} onChange={(e) => setForm({...form, name: e.target.value})} className="input-field col-span-2" required />
          <select value={form.game_type_id} onChange={(e) => setForm({...form, game_type_id: e.target.value})} className="input-field" required>
            <option value="">เลือกเกม</option>
            {gameTypes.filter(g => g.is_active).map(g => <option key={g.id} value={g.id}>{g.name_th || g.name}</option>)}
          </select>
          <select value={form.tournament_format} onChange={(e) => setForm({...form, tournament_format: e.target.value})} className="input-field">
            <option value="freezeout">Freezeout</option>
            <option value="rebuy">Rebuy</option>
            <option value="turbo">Turbo</option>
          </select>
          <input type="number" placeholder="ค่าสมัคร" value={form.entry_fee} onChange={(e) => setForm({...form, entry_fee: Number(e.target.value)})} className="input-field" />
          <input type="number" placeholder="Starting Chips" value={form.starting_chips} onChange={(e) => setForm({...form, starting_chips: Number(e.target.value)})} className="input-field" />
          <input type="number" placeholder="เงินรางวัลรวม" value={form.prize_pool} onChange={(e) => setForm({...form, prize_pool: Number(e.target.value)})} className="input-field" />
          <input type="number" placeholder="ผู้เล่นสูงสุด" value={form.max_players} onChange={(e) => setForm({...form, max_players: Number(e.target.value)})} className="input-field" />
          <input type="datetime-local" value={form.scheduled_at} onChange={(e) => setForm({...form, scheduled_at: e.target.value})} className="input-field" />
          <div className="flex gap-2">
            <button type="submit" className="btn-green flex-1">✅ สร้าง</button>
            <button type="button" onClick={() => setShowCreate(false)} className="btn-black flex-1">ยกเลิก</button>
          </div>
        </form>
      )}

      <div className="flex flex-col lg:flex-row gap-4 lg:gap-6">
        {/* Tournament list */}
        <div className={`card ${selectedTournament ? "flex-1" : "w-full"}`}>
          <div className="overflow-x-auto">
          <table className="w-full text-sm min-w-[700px]">
            <thead>
              <tr className="text-sun-gold/60 border-b border-sun-gold/20">
                <th className="text-left py-2">ชื่อ</th>
                <th className="text-left py-2">เกม</th>
                <th className="text-left py-2">รูปแบบ</th>
                <th className="text-right py-2">ค่าสมัคร</th>
                <th className="text-right py-2">รางวัล</th>
                <th className="text-center py-2">ผู้เล่น</th>
                <th className="text-center py-2">สถานะ</th>
                <th className="text-left py-2">กำหนดการ</th>
                <th className="text-left py-2">จัดการ</th>
              </tr>
            </thead>
            <tbody>
              {tournaments.map((t) => (
                <tr key={t.id} className="table-row cursor-pointer" onClick={() => viewTournament(t.id)}>
                  <td className="py-2 font-bold">{t.name}</td>
                  <td className="py-2 text-xs">{t.game_type_name_th || t.game_type_name}</td>
                  <td className="py-2 text-xs">{t.tournament_format}</td>
                  <td className="py-2 text-right">{Number(t.entry_fee).toLocaleString()} 🪙</td>
                  <td className="py-2 text-right">{Number(t.prize_pool).toLocaleString()} 🪙</td>
                  <td className="py-2 text-center">{t.player_count}/{t.max_players}</td>
                  <td className="py-2 text-center"><span className={`text-xs px-2 py-1 rounded ${statusColor(t.status)}`}>{statusLabel(t.status)}</span></td>
                  <td className="py-2 text-xs text-sun-gold/40">{t.scheduled_at ? new Date(t.scheduled_at).toLocaleString("th") : "-"}</td>
                  <td className="py-2 space-x-1" onClick={(e) => e.stopPropagation()}>
                    {t.status === "draft" && <button onClick={() => changeStatus(t.id, "registration")} className="text-blue-400 text-xs">เปิดรับสมัคร</button>}
                    {t.status === "registration" && <button onClick={() => changeStatus(t.id, "running")} className="text-green-400 text-xs">เริ่มแข่ง</button>}
                    {t.status === "running" && <button onClick={() => changeStatus(t.id, "finished")} className="text-gray-400 text-xs">จบ</button>}
                    {["draft","registration"].includes(t.status) && <button onClick={() => changeStatus(t.id, "cancelled")} className="text-red-400 text-xs">ยกเลิก</button>}
                  </td>
                </tr>
              ))}
              {tournaments.length === 0 && <tr><td colSpan={9} className="py-8 text-center text-sun-gold/30">ยังไม่มีทัวร์นาเมนต์</td></tr>}
            </tbody>
          </table>
          </div>
        </div>

        {/* Tournament detail panel */}
        {selectedTournament && (
          <div className="card w-full lg:w-[450px] max-h-[85vh] overflow-auto">
            <div className="flex justify-between items-start mb-4">
              <h2 className="text-lg font-bold text-sun-gold-light">🏆 {selectedTournament.name}</h2>
              <button onClick={() => setSelectedTournament(null)} className="text-sun-gold/40">✕</button>
            </div>
            <div className="space-y-2 text-sm mb-4">
              <p><span className="text-sun-gold/60">เกม:</span> <span className="text-white">{selectedTournament.game_type_name_th || selectedTournament.game_type_name}</span></p>
              <p><span className="text-sun-gold/60">รูปแบบ:</span> <span className="text-white">{selectedTournament.tournament_format}</span></p>
              <p><span className="text-sun-gold/60">ค่าสมัคร:</span> <span className="text-white">{Number(selectedTournament.entry_fee).toLocaleString()} 🪙</span></p>
              <p><span className="text-sun-gold/60">เงินรางวัล:</span> <span className="text-sun-gold-light font-bold">{Number(selectedTournament.prize_pool).toLocaleString()} 🪙</span></p>
              <p><span className="text-sun-gold/60">Starting Chips:</span> <span className="text-white">{Number(selectedTournament.starting_chips).toLocaleString()}</span></p>
              <p><span className="text-sun-gold/60">สถานะ:</span> <span className={`text-xs px-2 py-1 rounded ${statusColor(selectedTournament.status)}`}>{statusLabel(selectedTournament.status)}</span></p>
              {selectedTournament.scheduled_at && <p><span className="text-sun-gold/60">กำหนดการ:</span> <span className="text-white text-xs">{new Date(selectedTournament.scheduled_at).toLocaleString("th")}</span></p>}
              {selectedTournament.started_at && <p><span className="text-sun-gold/60">เริ่มเมื่อ:</span> <span className="text-white text-xs">{new Date(selectedTournament.started_at).toLocaleString("th")}</span></p>}
              {selectedTournament.finished_at && <p><span className="text-sun-gold/60">จบเมื่อ:</span> <span className="text-white text-xs">{new Date(selectedTournament.finished_at).toLocaleString("th")}</span></p>}
            </div>

            {/* Players list with editable position & prize */}
            <div className="border-t border-sun-gold/20 pt-4">
              <div className="flex justify-between items-center mb-3">
                <p className="text-sun-gold/60 text-sm font-bold">👥 ผู้เล่น ({players.length})</p>
                {selectedTournament.status === "finished" && players.length > 0 && (
                  <button onClick={() => distributePrizes(selectedTournament.id)} className="text-green-400 text-xs hover:text-green-300">💰 แจกเงินรางวัล</button>
                )}
              </div>
              <div className="space-y-2">
                {players.map((p: any, i: number) => (
                  <div key={p.user_id || i} className="bg-sun-black/50 rounded-lg p-3">
                    <div className="flex justify-between items-center mb-2">
                      <div className="flex items-center gap-2">
                        <span className={`w-6 h-6 rounded-full flex items-center justify-center text-[10px] font-bold ${
                          (p.finish_position || 99) <= 3 ? "bg-yellow-600 text-black" : "bg-sun-black text-sun-gold/40"
                        }`}>{p.finish_position || "-"}</span>
                        <span className="text-white text-sm font-bold">{p.display_name || p.username}</span>
                      </div>
                      <span className={`text-xs px-2 py-0.5 rounded ${
                        p.status === "eliminated" ? "bg-red-900 text-red-300" : "bg-blue-900 text-blue-300"
                      }`}>{p.status === "eliminated" ? "ตกรอบ" : p.status}</span>
                    </div>
                    <div className="flex gap-2 items-center text-xs">
                      <label className="text-sun-gold/40">อันดับ:</label>
                      <input type="number" min="1" className="input-field w-16 text-xs py-1" defaultValue={p.finish_position || ""}
                        onBlur={(e) => {
                          const val = Number(e.target.value);
                          if (val > 0) updatePlayer(selectedTournament.id, p.user_id, { finish_position: val });
                        }} />
                      <label className="text-sun-gold/40 ml-2">เงินรางวัล:</label>
                      <input type="number" min="0" className="input-field w-24 text-xs py-1" defaultValue={p.prize_won || ""}
                        onBlur={(e) => {
                          const val = Number(e.target.value);
                          if (val >= 0) setPrizeForPlayer(p.user_id, val);
                        }} />
                      <span className="text-sun-gold/30">🪙</span>
                      {p.status !== "eliminated" && (
                        <button onClick={() => updatePlayer(selectedTournament.id, p.user_id, { status: "eliminated" })}
                          className="text-red-400 text-xs ml-auto">ตกรอบ</button>
                      )}
                    </div>
                    {p.prize_won > 0 && <p className="text-green-400 text-xs mt-1">💰 ได้รับ {Number(p.prize_won).toLocaleString()} 🪙</p>}
                  </div>
                ))}
                {players.length === 0 && <p className="text-sun-gold/30 text-xs">ยังไม่มีผู้เล่น</p>}
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
