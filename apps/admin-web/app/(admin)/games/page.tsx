"use client";
import { useEffect, useState, type FormEvent } from "react";
import { api } from "@/lib/api";
import RoomTemplateManager from "@/components/room-template-manager";
import GameTypeConfigEditor from "@/components/game-type-config-editor";
import RuntimeOverrideManager from "@/components/runtime-override-manager";

export default function GamesPage() {
  const [tab, setTab] = useState<"types" | "tables">("types");
  const [gameTypes, setGameTypes] = useState<any[]>([]);
  const [tables, setTables] = useState<any[]>([]);
  const [message, setMessage] = useState("");
  const [showCreateType, setShowCreateType] = useState(false);
  const [showCreateTable, setShowCreateTable] = useState(false);
  const [typeForm, setTypeForm] = useState({ slug: "", name: "", name_th: "", min_players: 2, max_players: 9 });
  const [tableForm, setTableForm] = useState<any>({
    game_type_id: "", name: "", max_players: null, small_blind: null, big_blind: null,
    min_buy_in: null, max_buy_in: null, turn_time_sec: null, auto_start_at: null,
    auto_start_delay_sec: null, minimum_play_minutes: null, is_featured: false,
  });

  // Filter state
  const [filterOccupancy, setFilterOccupancy] = useState("");
  const [filterCreatedBy, setFilterCreatedBy] = useState("");

  // Cleanup settings
  const [cleanupSettings, setCleanupSettings] = useState<any>(null);
  const [cleanupPreview, setCleanupPreview] = useState<any[]>([]);
  const [cleanupLoading, setCleanupLoading] = useState(false);
  const [templates, setTemplates] = useState<any[]>([]);
  const [effectivePreview, setEffectivePreview] = useState<any>(null);
  const [editingTable, setEditingTable] = useState<any>(null);
  const [applyMode, setApplyMode] = useState("next_hand");

  const loadTypes = async () => {
    const data = await api("/api/admin/games/types");
    setGameTypes(data.game_types);
  };
  const loadTables = async () => {
    const params = new URLSearchParams();
    if (filterOccupancy) params.set("occupancy", filterOccupancy);
    if (filterCreatedBy) params.set("created_by_type", filterCreatedBy);
    params.set("limit", "100");
    const data = await api(`/api/admin/games/tables?${params.toString()}`);
    setTables(data.tables);
  };

  const loadCleanupSettings = async () => {
    try {
      const data = await api("/api/admin/games/cleanup-settings");
      setCleanupSettings(data);
    } catch { setMessage("โหลดการตั้งค่า auto-cleanup ไม่สำเร็จ"); }
  };

  const loadRoomConfig = async () => {
    const data = await api("/api/admin/games/room-config");
    setTableForm((current: any) => ({ ...current, ...data.defaults }));
  };

  const loadTemplates = async () => {
    try {
      const data = await api("/api/admin/config/templates");
      setTemplates(data.templates || []);
    } catch {
      setTemplates([]);
    }
  };

  const loadEffectivePreview = async (gameTypeId: string, templateId?: string) => {
    if (!gameTypeId) { setEffectivePreview(null); return; }
    const params = new URLSearchParams({ gameTypeId });
    if (templateId) params.set("templateId", templateId);
    try {
      const data = await api(`/api/admin/config/effective?${params.toString()}`);
      setEffectivePreview(data);
      setTableForm((current: any) => ({ ...current, ...data.value }));
    } catch (err: any) {
      setMessage(err.error || "โหลด effective config ไม่สำเร็จ");
    }
  };

  const saveCleanupSettings = async () => {
    setCleanupLoading(true);
    try {
      await api("/api/admin/games/cleanup-settings", { method: "PUT", body: JSON.stringify(cleanupSettings) });
      setMessage("✅ บันทึกการตั้งค่า auto-cleanup สำเร็จ");
    } catch { setMessage("❌ บันทึกไม่สำเร็จ"); }
    setCleanupLoading(false);
  };

  const previewCleanup = async () => {
    setCleanupLoading(true);
    try {
      const result = await api("/api/admin/games/cleanup-preview", { method: "POST" });
      setCleanupPreview(result.rooms || []);
      setMessage(`พบห้องที่เข้าเงื่อนไข ${result.total_candidates} ห้อง`);
    } catch { setMessage("ดูตัวอย่าง Cleanup ไม่สำเร็จ"); }
    setCleanupLoading(false);
  };

  const runCleanupNow = async () => {
    if (!confirm("ยืนยัน? จะลบห้องว่างที่ผู้เล่นสร้างทั้งหมดที่เกินเวลา")) return;
    setCleanupLoading(true);
    try {
      const result = await api("/api/admin/games/cleanup-now", { method: "POST" });
      setMessage(`🗑️ ลบห้องแล้ว ${result.total_deleted} ห้อง`);
      loadTables();
    } catch { setMessage("❌ ลบไม่สำเร็จ"); }
    setCleanupLoading(false);
  };

  useEffect(() => { loadTypes(); loadTables(); loadCleanupSettings(); loadRoomConfig(); loadTemplates(); }, []);
  useEffect(() => { loadTables(); }, [filterOccupancy, filterCreatedBy]);

  const createType = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await api("/api/admin/games/types", { method: "POST", body: JSON.stringify(typeForm) });
      setMessage("เพิ่มเกมสำเร็จ"); setShowCreateType(false); loadTypes();
      setTypeForm({ slug: "", name: "", name_th: "", min_players: 2, max_players: 9 });
    } catch (err: any) { setMessage(err.error || "เพิ่มไม่สำเร็จ"); }
  };

  const toggleType = async (id: string) => {
    await api(`/api/admin/games/types/${id}/toggle`, { method: "PUT" });
    loadTypes();
  };

  const saveTable = async (e: FormEvent) => {
    e.preventDefault();
    try {
      const payload = { ...tableForm, apply_mode: applyMode };
      if (editingTable) {
        await api(`/api/admin/games/tables/${editingTable.id}`, { method: "PUT", body: JSON.stringify(payload) });
        setMessage("อัปเดตห้องสำเร็จ");
      } else {
        await api("/api/admin/games/tables", { method: "POST", body: JSON.stringify(payload) });
        setMessage("สร้างห้องสำเร็จ");
      }
      setShowCreateTable(false);
      setEditingTable(null);
      setApplyMode("next_hand");
      loadTables();
    } catch (err: any) { setMessage(err.error || (editingTable ? "อัปเดตไม่สำเร็จ" : "สร้างไม่สำเร็จ")); }
  };

  const editTable = (table: any) => {
    setEditingTable(table);
    setTableForm({
      game_type_id: table.game_type_id,
      room_template_id: table.room_template_id || "",
      name: table.name || "",
      max_players: table.max_players,
      small_blind: table.small_blind,
      big_blind: table.big_blind,
      min_buy_in: table.min_buy_in,
      max_buy_in: table.max_buy_in,
      turn_time_sec: table.turn_time_sec,
      auto_start_at: table.auto_start_at,
      auto_start_delay_sec: table.auto_start_delay_sec,
      minimum_play_minutes: table.minimum_play_minutes,
      rake_percent: table.rake_percent,
      rake_cap: table.rake_cap,
      is_featured: table.is_featured,
      mode: table.mode,
    });
    setShowCreateTable(true);
  };

  const changeTableStatus = async (id: string, status: string) => {
    await api(`/api/admin/games/tables/${id}/status`, { method: "PUT", body: JSON.stringify({ status }) });
    loadTables();
  };

  const deleteTable = async (id: string) => {
    if (!confirm("ยืนยันลบห้องนี้?")) return;
    await api(`/api/admin/games/tables/${id}`, { method: "DELETE" });
    setMessage("ลบห้องสำเร็จ"); loadTables();
  };

  return (
    <div>
      <h1 className="text-2xl font-bold text-sun-gold-light mb-6">🎮 เกม & ห้องเล่น</h1>

      <details className="mb-4 text-xs text-sun-gold/50 bg-sun-black/30 rounded-lg p-3">
        <summary className="cursor-pointer text-sun-gold/70 font-bold">ℹ️ วิธีใช้งานหน้านี้</summary>
        <div className="mt-2 space-y-1">
          <p>📋 <b>หน้านี้คืออะไร:</b> จัดการประเภทเกมและห้องเล่น</p>
          <p>🃏 <b>ประเภทเกม:</b> เช่น "No Limit Hold'em", "ไพ่สามกอง" — เปิด/ปิดจะทำให้เกมนั้นหายหรือแสดงในแอป</p>
          <p>🏠 <b>ห้องเล่น:</b> แต่ละห้องคือโต๊ะที่ผู้เล่นเข้ามานั่งเล่น</p>
          <p className="pl-4">• Blinds (SB/BB) = เงินเดิมพันขั้นต่ำ เช่น 10/20 หมายถึงต้องวาง 10-20 ต่อรอบ</p>
          <p className="pl-4">• Buy-in = เงินที่ต้องซื้อเข้าห้อง (Min-Max)</p>
          <p className="pl-4">• สถานะ: 🟢เล่น = มีคนเล่นอยู่, 🟡รอ = ว่าง, 🔴ปิด = ไม่ให้เข้า</p>
          <p>⚡ <b>สิ่งที่ทำได้:</b> สร้างห้องใหม่, ปิด/เปิดห้อง, ลบห้อง</p>
          <p>👁 <b>Live Monitor:</b> กดปุ่มสีเขียวเพื่อดูเกมที่กำลังเล่นแบบสดๆ (เห็นไพ่ทุกคน)</p>
        </div>
      </details>

      {message && (
        <div className="bg-green-900/50 border border-green-500 text-green-300 px-4 py-2 rounded mb-4 flex justify-between">
          <span>{message}</span><button onClick={() => setMessage("")}>✕</button>
        </div>
      )}

      {/* Tabs */}
      <div className="flex flex-wrap gap-2 mb-6">
        <button onClick={() => setTab("types")} className={`px-6 py-2 rounded-lg font-bold ${tab === "types" ? "bg-sun-red text-sun-gold-light" : "bg-sun-black/50 text-sun-gold/50"}`}>
          🃏 ประเภทเกม ({gameTypes.length})
        </button>
        <button onClick={() => setTab("tables")} className={`px-6 py-2 rounded-lg font-bold ${tab === "tables" ? "bg-sun-red text-sun-gold-light" : "bg-sun-black/50 text-sun-gold/50"}`}>
          🏠 ห้องเล่น ({tables.length})
        </button>
        <a href="/games/live" className="px-6 py-2 rounded-lg font-bold bg-green-800 text-white">
          👁 Live Monitor
        </a>
      </div>

      {/* ===== TAB: ประเภทเกม ===== */}
      {tab === "types" && (
        <>
        <GameTypeConfigEditor gameTypes={gameTypes} onMessage={setMessage} />
        <div className="card">
          <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 mb-4">
            <h2 className="text-lg font-bold text-sun-gold-light">🃏 ประเภทเกม</h2>
            <button onClick={() => setShowCreateType(!showCreateType)} className="btn-green text-sm py-2">➕ เพิ่มเกมใหม่</button>
          </div>

          {showCreateType && (
            <form onSubmit={createType} className="bg-sun-black/50 rounded-lg p-4 mb-4 grid grid-cols-1 md:grid-cols-2 gap-3">
              <input placeholder="Slug (เช่น short_deck)" value={typeForm.slug} onChange={(e) => setTypeForm({...typeForm, slug: e.target.value})} className="input-field" required />
              <input placeholder="Name (English)" value={typeForm.name} onChange={(e) => setTypeForm({...typeForm, name: e.target.value})} className="input-field" required />
              <input placeholder="ชื่อไทย" value={typeForm.name_th} onChange={(e) => setTypeForm({...typeForm, name_th: e.target.value})} className="input-field" />
              <div className="flex gap-2">
                <input type="number" placeholder="Min" value={typeForm.min_players} onChange={(e) => setTypeForm({...typeForm, min_players: Number(e.target.value)})} className="input-field w-20" />
                <span className="text-sun-gold/40 self-center">-</span>
                <input type="number" placeholder="Max" value={typeForm.max_players} onChange={(e) => setTypeForm({...typeForm, max_players: Number(e.target.value)})} className="input-field w-20" />
                <span className="text-sun-gold/40 self-center text-sm">คน</span>
              </div>
              <button type="submit" className="btn-green text-sm py-2">✅ เพิ่ม</button>
              <button type="button" onClick={() => setShowCreateType(false)} className="btn-black text-sm py-2">ยกเลิก</button>
            </form>
          )}

          <div className="overflow-x-auto">
          <table className="w-full text-sm min-w-[600px]">
            <thead>
              <tr className="text-sun-gold/60 border-b border-sun-gold/20">
                <th className="text-left py-2">ลำดับ</th>
                <th className="text-left py-2">Slug</th>
                <th className="text-left py-2">ชื่อ</th>
                <th className="text-left py-2">ชื่อไทย</th>
                <th className="text-center py-2">ผู้เล่น</th>
                <th className="text-center py-2">สถานะ</th>
                <th className="text-left py-2">จัดการ</th>
              </tr>
            </thead>
            <tbody>
              {gameTypes.map((g) => (
                <tr key={g.id} className="table-row">
                  <td className="py-2">{g.sort_order}</td>
                  <td className="py-2 font-mono text-xs">{g.slug}</td>
                  <td className="py-2">{g.name}</td>
                  <td className="py-2">{g.name_th || "-"}</td>
                  <td className="py-2 text-center">{g.min_players}-{g.max_players}</td>
                  <td className="py-2 text-center">
                    {g.is_active ? <span className="text-green-400">🟢 เปิด</span> : <span className="text-red-400">🔴 ปิด</span>}
                  </td>
                  <td className="py-2 space-x-2">
                    <button onClick={() => toggleType(g.id)} className={`text-xs ${g.is_active ? "text-red-400" : "text-green-400"}`}>
                      {g.is_active ? "ปิด" : "เปิด"}
                    </button>
                    <button onClick={() => {
                      const newName = prompt("ชื่อใหม่ (English):", g.name);
                      const newNameTh = prompt("ชื่อไทยใหม่:", g.name_th || "");
                      if (newName) {
                        api(`/api/admin/games/types/${g.id}`, { method: "PUT", body: JSON.stringify({ name: newName, name_th: newNameTh }) })
                          .then(() => { setMessage("อัปเดตสำเร็จ"); loadTypes(); });
                      }
                    }} className="text-sun-gold-light text-xs">✏️ แก้ไข</button>
                    <button onClick={() => {
                      if (!confirm(`ยืนยันลบเกม "${g.name}"?`)) return;
                      api(`/api/admin/games/types/${g.id}`, { method: "DELETE" })
                        .then(() => { setMessage("ลบสำเร็จ"); loadTypes(); })
                        .catch(() => setMessage("ลบไม่ได้ (อาจมีห้องเปิดอยู่)"));
                    }} className="text-red-400/50 text-xs">🗑 ลบ</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          </div>
        </div>
        </>
      )}

      {/* ===== TAB: ห้องเล่น ===== */}
      {tab === "tables" && (
        <>
        <RoomTemplateManager gameTypes={gameTypes} onMessage={setMessage} />
        <RuntimeOverrideManager gameTypes={gameTypes} tables={tables} onMessage={setMessage} />
        <div className="card">
          <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 mb-4">
            <h2 className="text-lg font-bold text-sun-gold-light">🏠 ห้องเล่น</h2>
            <button onClick={() => { setEditingTable(null); setTableForm({ game_type_id: "", room_template_id: "", name: "", max_players: null, small_blind: null, big_blind: null, min_buy_in: null, max_buy_in: null, turn_time_sec: null, auto_start_at: null, auto_start_delay_sec: null, minimum_play_minutes: null, rake_percent: null, rake_cap: null, is_featured: false }); setShowCreateTable(!showCreateTable); }} className="btn-green text-sm py-2">➕ สร้างห้อง</button>
          </div>

          {/* Filter bar */}
          <div className="flex flex-wrap gap-3 mb-4 bg-sun-black/30 rounded-lg p-3">
            <div className="flex items-center gap-2">
              <span className="text-sun-gold/60 text-xs">สถานะ:</span>
              <select value={filterOccupancy} onChange={(e) => setFilterOccupancy(e.target.value)} className="input-field text-xs py-1 px-2">
                <option value="">ทั้งหมด</option>
                <option value="playing">🟢 มีคนเล่น</option>
                <option value="empty">⚪ ห้องว่าง</option>
              </select>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-sun-gold/60 text-xs">สร้างโดย:</span>
              <select value={filterCreatedBy} onChange={(e) => setFilterCreatedBy(e.target.value)} className="input-field text-xs py-1 px-2">
                <option value="">ทั้งหมด</option>
                <option value="player">👤 ผู้เล่น</option>
                <option value="admin">🛡️ Admin</option>
              </select>
            </div>
            <span className="text-sun-gold/40 text-xs self-center">พบ {tables.length} ห้อง</span>
          </div>

          {/* Auto-Cleanup Settings */}
          {cleanupSettings && (
            <details className="mb-4 bg-sun-black/30 rounded-lg p-3">
              <summary className="cursor-pointer text-sun-gold/70 font-bold text-sm">🗑️ ตั้งเวลาลบห้องอัตโนมัติ (ห้องที่ผู้เล่นสร้าง)</summary>
              <div className="mt-3 space-y-3">
                <div className="flex items-center gap-3">
                  <input type="checkbox" id="cleanupEnabled" checked={cleanupSettings.enabled}
                    onChange={(e) => setCleanupSettings({...cleanupSettings, enabled: e.target.checked})} className="accent-yellow-500" />
                  <label htmlFor="cleanupEnabled" className="text-sun-gold/80 text-sm">เปิดใช้ Auto-Cleanup</label>
                </div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                  <div>
                    <label className="text-sun-gold/60 text-xs block mb-1">ลบห้องว่างหลังจาก (นาที)</label>
                    <input type="number" min={5} value={cleanupSettings.delete_empty_after_minutes}
                      onChange={(e) => setCleanupSettings({...cleanupSettings, delete_empty_after_minutes: Number(e.target.value)})}
                      className="input-field w-full" />
                  </div>
                  <div>
                    <label className="text-sun-gold/60 text-xs block mb-1">ลบห้องทั้งหมดหลังจาก (ชั่วโมง)</label>
                    <input type="number" min={1} value={cleanupSettings.delete_all_player_rooms_after_hours}
                      onChange={(e) => setCleanupSettings({...cleanupSettings, delete_all_player_rooms_after_hours: Number(e.target.value)})}
                      className="input-field w-full" />
                  </div>
                </div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3 text-xs text-sun-gold/70">
                  <label><input type="checkbox" checked={cleanupSettings.only_player_created} onChange={(e) => setCleanupSettings({...cleanupSettings, only_player_created: e.target.checked})} className="mr-2" />เฉพาะห้องที่ผู้เล่นสร้าง</label>
                  <label><input type="checkbox" checked={cleanupSettings.allow_close_occupied_expired} onChange={(e) => setCleanupSettings({...cleanupSettings, allow_close_occupied_expired: e.target.checked})} className="mr-2" />อนุญาตปิดห้องหมดอายุที่ยังมีผู้เล่น</label>
                  <label><input type="checkbox" checked={cleanupSettings.allow_close_playing} onChange={(e) => setCleanupSettings({...cleanupSettings, allow_close_playing: e.target.checked})} className="mr-2" />อนุญาตปิดห้องที่กำลังเล่น</label>
                  <label>รอบตรวจ (วินาที)<input type="number" min={60} value={cleanupSettings.cleanup_worker_interval_sec} onChange={(e) => setCleanupSettings({...cleanupSettings, cleanup_worker_interval_sec: Number(e.target.value)})} className="input-field w-full mt-1" /></label>
                </div>
                <div className="flex gap-3">
                  <button onClick={saveCleanupSettings} disabled={cleanupLoading} className="bg-yellow-700 hover:bg-yellow-600 text-white px-4 py-1.5 rounded text-xs font-bold disabled:opacity-50">บันทึก</button>
                  <button onClick={previewCleanup} disabled={cleanupLoading} className="bg-blue-800 hover:bg-blue-700 text-white px-4 py-1.5 rounded text-xs font-bold disabled:opacity-50">ดูตัวอย่าง</button>
                  <button onClick={runCleanupNow} disabled={cleanupLoading} className="bg-red-800 hover:bg-red-700 text-white px-4 py-1.5 rounded text-xs font-bold disabled:opacity-50">ปิดห้องตามเงื่อนไข</button>
                </div>
                {cleanupPreview.length > 0 && <div className="text-xs text-sun-gold/60">{cleanupPreview.map((room) => <div key={room.id}>{room.name || room.id} — {room.reason}</div>)}</div>}
              </div>
            </details>
          )}

          {showCreateTable && (
            <form onSubmit={saveTable} className="bg-sun-black/50 rounded-lg p-4 mb-4">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <select value={tableForm.game_type_id} onChange={(e) => { setTableForm({...tableForm, game_type_id: e.target.value}); loadEffectivePreview(e.target.value, tableForm.room_template_id); }} className="input-field" required>
                  <option value="">เลือกเกม</option>
                  {gameTypes.filter(g => g.is_active).map(g => <option key={g.id} value={g.id}>{g.name_th || g.name}</option>)}
                </select>
                <select value={tableForm.room_template_id || ""} onChange={(e) => { setTableForm({...tableForm, room_template_id: e.target.value}); loadEffectivePreview(tableForm.game_type_id, e.target.value); }} className="input-field">
                  <option value="">ไม่ใช้ template</option>
                  {templates.filter(t => t.status !== 'archived' && (!tableForm.game_type_id || t.game_type_id === tableForm.game_type_id)).map(t => <option key={t.id} value={t.id}>{t.name} (rev {t.revision})</option>)}
                </select>
                <input placeholder="ชื่อห้อง" value={tableForm.name} onChange={(e) => setTableForm({...tableForm, name: e.target.value})} className="input-field" />
                <select value={applyMode} onChange={(e) => setApplyMode(e.target.value)} className="input-field">
                  <option value="next_hand">มีผลมือถัดไป</option>
                  <option value="immediate">มีผลทันที</option>
                  <option value="new_room">มีผลเฉพาะห้องใหม่</option>
                </select>
                <input type="number" placeholder="SB" value={tableForm.small_blind ?? ""} onChange={(e) => setTableForm({...tableForm, small_blind: e.target.value === "" ? null : Number(e.target.value)})} className="input-field" />
                <input type="number" placeholder="BB" value={tableForm.big_blind ?? ""} onChange={(e) => setTableForm({...tableForm, big_blind: e.target.value === "" ? null : Number(e.target.value)})} className="input-field" />
                <input type="number" placeholder="Min Buy-in" value={tableForm.min_buy_in ?? ""} onChange={(e) => setTableForm({...tableForm, min_buy_in: e.target.value === "" ? null : Number(e.target.value)})} className="input-field" />
                <input type="number" placeholder="Max Buy-in" value={tableForm.max_buy_in ?? ""} onChange={(e) => setTableForm({...tableForm, max_buy_in: e.target.value === "" ? null : Number(e.target.value)})} className="input-field" />
                <input type="number" placeholder="ผู้เล่นสูงสุด" value={tableForm.max_players ?? ""} onChange={(e) => setTableForm({...tableForm, max_players: e.target.value === "" ? null : Number(e.target.value)})} className="input-field" />
                <input type="number" placeholder="เวลาต่อตา (วินาที)" value={tableForm.turn_time_sec ?? ""} onChange={(e) => setTableForm({...tableForm, turn_time_sec: e.target.value === "" ? null : Number(e.target.value)})} className="input-field" />
                <input type="number" placeholder="จำนวนผู้เล่นที่เริ่มอัตโนมัติ" value={tableForm.auto_start_at ?? ""} onChange={(e) => setTableForm({...tableForm, auto_start_at: e.target.value === "" ? null : Number(e.target.value)})} className="input-field" />
                <input type="number" placeholder="เวลานับถอยหลังก่อนเริ่ม (วินาที)" value={tableForm.auto_start_delay_sec ?? ""} onChange={(e) => setTableForm({...tableForm, auto_start_delay_sec: e.target.value === "" ? null : Number(e.target.value)})} className="input-field" />
                <input type="number" placeholder="เวลาเล่นขั้นต่ำ (นาที)" value={tableForm.minimum_play_minutes ?? ""} onChange={(e) => setTableForm({...tableForm, minimum_play_minutes: e.target.value === "" ? null : Number(e.target.value)})} className="input-field" />
                <input type="number" placeholder="Rake %" value={tableForm.rake_percent ?? ""} onChange={(e) => setTableForm({...tableForm, rake_percent: e.target.value === "" ? null : Number(e.target.value)})} className="input-field" />
                <input type="number" placeholder="Rake cap" value={tableForm.rake_cap ?? ""} onChange={(e) => setTableForm({...tableForm, rake_cap: e.target.value === "" ? null : Number(e.target.value)})} className="input-field" />
                <label className="text-sun-gold/60 text-xs flex items-center gap-2">
                  <input type="checkbox" checked={Boolean(tableForm.is_featured)} onChange={(e) => setTableForm({...tableForm, is_featured: e.target.checked})} className="accent-yellow-500" />
                  แสดงเป็นห้องแนะนำ
                </label>
              </div>
              {effectivePreview && (
                <pre className="mt-3 bg-sun-black/40 rounded p-3 text-[10px] text-sun-gold/60 overflow-auto max-h-40">
                  {JSON.stringify(effectivePreview, null, 2)}
                </pre>
              )}
              <div className="flex gap-2 mt-3">
                <button type="submit" className="btn-green text-sm py-2">{editingTable ? "✅ บันทึกห้อง" : "✅ สร้างห้อง"}</button>
                <button type="button" onClick={() => { setShowCreateTable(false); setEditingTable(null); }} className="btn-black text-sm py-2">ยกเลิก</button>
              </div>
            </form>
          )}

          <div className="overflow-x-auto">
          <table className="w-full text-sm min-w-[700px]">
            <thead>
              <tr className="text-sun-gold/60 border-b border-sun-gold/20">
                <th className="text-left py-2">ห้อง</th>
                <th className="text-left py-2">เกม</th>
                <th className="text-center py-2">Blinds</th>
                <th className="text-center py-2">Buy-in</th>
                <th className="text-center py-2">ผู้เล่น</th>
                <th className="text-center py-2">ขั้นต่ำ</th>
                <th className="text-center py-2">รหัส</th>
                <th className="text-center py-2">สร้างโดย</th>
                <th className="text-center py-2">สถานะ</th>
                <th className="text-left py-2">จัดการ</th>
              </tr>
            </thead>
            <tbody>
              {tables.map((t) => (
                <tr key={t.id} className="table-row">
                  <td className="py-2">{t.name || `ห้อง #${t.room_code}`}</td>
                  <td className="py-2 text-xs">{t.game_type_name_th || t.game_type_name}</td>
                  <td className="py-2 text-center">{Number(t.small_blind)}/{Number(t.big_blind)}</td>
                  <td className="py-2 text-center text-xs">{Number(t.min_buy_in).toLocaleString()}-{Number(t.max_buy_in).toLocaleString()}</td>
                  <td className="py-2 text-center">{t.player_count}/{t.max_players}</td>
                  <td className="py-2 text-center text-xs">{t.minimum_play_minutes} นาที</td>
                  <td className="py-2 text-center font-mono text-xs">{t.room_code}</td>
                  <td className="py-2 text-center text-xs">
                    {t.created_by_role === 'admin' || t.created_by_role === 'superadmin' ? '🛡️' : '👤'} {t.created_by_name || '-'}
                  </td>
                  <td className="py-2 text-center">
                    <span className={`text-xs ${t.status === "playing" ? "text-green-400" : t.status === "closed" ? "text-red-400" : "text-yellow-400"}`}>
                      {t.status === "playing" ? "🟢 เล่น" : t.status === "closed" ? "🔴 ปิด" : "🟡 รอ"}
                    </span>
                  </td>
                  <td className="py-2 space-x-2">
                    <button onClick={() => editTable(t)} className="text-sun-gold-light text-xs">✏️</button>
                    {t.status !== "closed" && (
                      <button onClick={() => changeTableStatus(t.id, "closed")} className="text-red-400 text-xs">ปิด</button>
                    )}
                    {t.status === "closed" && (
                      <button onClick={() => changeTableStatus(t.id, "waiting")} className="text-green-400 text-xs">เปิด</button>
                    )}
                    <button onClick={() => deleteTable(t.id)} className="text-red-400/50 text-xs">🗑 ลบ</button>
                  </td>
                </tr>
              ))}
              {tables.length === 0 && (
                <tr><td colSpan={10} className="py-8 text-center text-sun-gold/30">ยังไม่มีห้องเล่น</td></tr>
              )}
            </tbody>
          </table>
          </div>
        </div>
        </>
      )}
    </div>
  );
}
