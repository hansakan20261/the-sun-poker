"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api";

const OVERRIDE_KEYS = [
  "turn_time_sec", "auto_start_at", "auto_start_delay_sec", "minimum_play_minutes",
  "small_blind", "big_blind", "ante", "min_buy_in", "max_buy_in", "max_players",
  "rake_percent", "rake_cap",
];

export default function RuntimeOverrideManager({ gameTypes, tables, onMessage }: {
  gameTypes: any[];
  tables: any[];
  onMessage: (message: string) => void;
}) {
  const [overrides, setOverrides] = useState<any[]>([]);
  const [targetType, setTargetType] = useState<"room" | "game">("room");
  const [targetId, setTargetId] = useState("");
  const [key, setKey] = useState("turn_time_sec");
  const [value, setValue] = useState("");
  const [applyMode, setApplyMode] = useState("immediate");
  const [expiresAt, setExpiresAt] = useState("");
  const [reason, setReason] = useState("");

  const load = async () => {
    try {
      const data = await api("/api/admin/config/overrides");
      setOverrides(data.overrides || []);
    } catch (err: any) {
      onMessage(err.error || "โหลด runtime overrides ไม่สำเร็จ");
    }
  };

  useEffect(() => { load(); }, []);

  const create = async () => {
    if (!targetId || !key || value === "" || !reason.trim()) {
      onMessage("กรุณากรอก target, key, value และเหตุผล");
      return;
    }
    const numeric = Number(value);
    if (!Number.isFinite(numeric)) {
      onMessage("Runtime override value ต้องเป็นตัวเลข");
      return;
    }
    try {
      await api("/api/admin/config/overrides", {
        method: "POST",
        body: JSON.stringify({
          [targetType === "room" ? "table_id" : "game_type_id"]: targetId,
          key,
          value: numeric,
          apply_mode: applyMode,
          expires_at: expiresAt ? new Date(expiresAt).toISOString() : null,
          reason,
        }),
      });
      onMessage("✅ สร้าง runtime override สำเร็จ");
      setReason("");
      await load();
    } catch (err: any) {
      onMessage(err.error || "สร้าง runtime override ไม่สำเร็จ");
    }
  };

  const cancel = async (id: string) => {
    if (!confirm("ยืนยันยกเลิก runtime override?")) return;
    try {
      await api(`/api/admin/config/overrides/${id}`, { method: "DELETE" });
      onMessage("✅ ยกเลิก runtime override สำเร็จ");
      await load();
    } catch (err: any) {
      onMessage(err.error || "ยกเลิก runtime override ไม่สำเร็จ");
    }
  };

  return (
    <div className="card mb-6">
      <h2 className="text-lg font-bold text-sun-gold-light">⚡ Runtime Overrides</h2>
      <p className="text-sun-gold/40 text-xs mb-4">
        Override config เฉพาะห้องหรือเฉพาะเกม โดยรองรับ immediate, next_hand และ new_room
      </p>

      <div className="grid grid-cols-1 md:grid-cols-6 gap-3 mb-4">
        <select value={targetType} onChange={event => { setTargetType(event.target.value as "room" | "game"); setTargetId(""); }} className="input-field text-sm">
          <option value="room">Room</option>
          <option value="game">Game Type</option>
        </select>
        <select value={targetId} onChange={event => setTargetId(event.target.value)} className="input-field text-sm">
          <option value="">เลือก target</option>
          {targetType === "room"
            ? tables.filter(table => table.status !== "closed").map(table => <option key={table.id} value={table.id}>{table.name}</option>)
            : gameTypes.filter(type => type.is_active).map(type => <option key={type.id} value={type.id}>{type.name_th || type.name}</option>)}
        </select>
        <select value={key} onChange={event => setKey(event.target.value)} className="input-field text-sm">
          {OVERRIDE_KEYS.map(item => <option key={item} value={item}>{item}</option>)}
        </select>
        <input value={value} onChange={event => setValue(event.target.value)} placeholder="value" type="number" className="input-field text-sm" />
        <select value={applyMode} onChange={event => setApplyMode(event.target.value)} className="input-field text-sm">
          <option value="immediate">immediate</option>
          <option value="next_hand">next_hand</option>
          <option value="new_room">new_room</option>
        </select>
        <input value={expiresAt} onChange={event => setExpiresAt(event.target.value)} type="datetime-local" className="input-field text-sm" />
      </div>
      <div className="flex gap-2 mb-4">
        <input value={reason} onChange={event => setReason(event.target.value)} placeholder="เหตุผล" className="input-field text-sm flex-1" />
        <button type="button" onClick={create} className="btn-green text-sm py-2">สร้าง Override</button>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead><tr className="text-left text-sun-gold/60"><th className="pb-2">Target</th><th className="pb-2">Key</th><th className="pb-2">Value</th><th className="pb-2">Mode</th><th className="pb-2">Expires</th><th className="pb-2">Status</th><th className="pb-2 text-right">Action</th></tr></thead>
          <tbody>
            {overrides.map(item => (
              <tr key={item.id} className="border-t border-sun-gold/10">
                <td className="py-2 font-mono text-xs">{item.table_id || item.game_type_id}</td>
                <td className="py-2">{item.key}</td>
                <td className="py-2">{JSON.stringify(item.value?.[item.key] ?? item.value)}</td>
                <td className="py-2">{item.apply_mode}</td>
                <td className="py-2 text-xs">{item.expires_at ? new Date(item.expires_at).toLocaleString() : "—"}</td>
                <td className="py-2">{item.status}</td>
                <td className="py-2 text-right">
                  {item.status === "active" && <button onClick={() => cancel(item.id)} className="text-red-400 text-xs">Cancel</button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
