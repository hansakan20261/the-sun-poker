"use client";

import { useEffect, useMemo, useState } from "react";
import { api } from "@/lib/api";

type RoomTemplate = {
  id: string;
  game_type_id: string;
  name: string;
  mode: string;
  revision: number;
  status: string;
  config: Record<string, any>;
  game_type_name_th?: string;
  game_type_name?: string;
  active_room_count?: number;
};

const POLICY_SECTIONS = [
  { key: "texas_holdem", configKey: "texas_holdem_policy", title: "Texas Hold'em Policy" },
  { key: "chinese_poker", configKey: "chinese_poker_policy", title: "Chinese Poker Policy" },
  { key: "tournament", configKey: "tournament_policy", title: "Tournament Policy" },
] as const;

const ROOM_FIELDS = [
  "small_blind",
  "big_blind",
  "ante",
  "min_buy_in",
  "max_buy_in",
  "max_players",
  "turn_time_sec",
  "auto_start_at",
  "auto_start_delay_sec",
  "minimum_play_minutes",
  "rake_percent",
  "rake_cap",
] as const;

export default function RoomTemplateManager({ gameTypes, onMessage }: {
  gameTypes: any[];
  onMessage: (message: string) => void;
}) {
  const [templates, setTemplates] = useState<RoomTemplate[]>([]);
  const [definitions, setDefinitions] = useState<Record<string, any>>({});
  const [editing, setEditing] = useState<RoomTemplate | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [preview, setPreview] = useState<any>(null);
  const [form, setForm] = useState<any>({
    game_type_id: "",
    name: "",
    mode: "cash",
    config: {},
  });
  const [reason, setReason] = useState("");

  const activeTemplates = useMemo(
    () => templates.filter(template => template.status !== "archived"),
    [templates],
  );

  const load = async () => {
    try {
      const [data, defs] = await Promise.all([
        api("/api/admin/config/templates"),
        api("/api/admin/config/definitions"),
      ]);
      setTemplates(data.templates || []);
      setDefinitions(Object.fromEntries((defs.definitions || []).map((item: any) => [item.key, item])));
    } catch (err: any) {
      onMessage(err.error || "โหลด room templates ไม่สำเร็จ");
    }
  };

  const loadPreview = async (gameTypeId: string, templateId?: string) => {
    if (!gameTypeId) return;
    const params = new URLSearchParams({ gameTypeId });
    if (templateId) params.set("templateId", templateId);
    try {
      setPreview(await api(`/api/admin/config/effective?${params.toString()}`));
    } catch {
      setPreview(null);
    }
  };

  useEffect(() => { load(); }, []);

  const resetForm = () => {
    setEditing(null);
    setForm({ game_type_id: "", name: "", mode: "cash", config: {} });
    setReason("");
    setPreview(null);
  };

  const save = async () => {
    if (!form.game_type_id || !form.name) {
      onMessage("กรุณาเลือกเกมและตั้งชื่อ template");
      return;
    }
    try {
      if (editing) {
        await api(`/api/admin/config/templates/${editing.id}`, {
          method: "PUT",
          body: JSON.stringify({
            name: form.name,
            mode: form.mode,
            config: form.config,
            expected_revision: editing.revision,
            reason,
          }),
        });
        onMessage("✅ อัปเดต template สำเร็จ");
      } else {
        await api("/api/admin/config/templates", {
          method: "POST",
          body: JSON.stringify(form),
        });
        onMessage("✅ สร้าง template สำเร็จ");
      }
      setShowForm(false);
      resetForm();
      load();
    } catch (err: any) {
      onMessage(err.error || "บันทึก template ไม่สำเร็จ");
    }
  };

  const clone = async (template: RoomTemplate) => {
    try {
      const name = prompt("ชื่อ template ใหม่:", `${template.name} Copy`);
      if (!name) return;
      await api(`/api/admin/config/templates/${template.id}/clone`, {
        method: "POST",
        body: JSON.stringify({ name }),
      });
      onMessage("✅ Clone template สำเร็จ");
      load();
    } catch (err: any) {
      onMessage(err.error || "Clone template ไม่สำเร็จ");
    }
  };

  const archive = async (template: RoomTemplate) => {
    if (!confirm(`Archive template "${template.name}"?`)) return;
    try {
      await api(`/api/admin/config/templates/${template.id}/archive`, { method: "POST" });
      onMessage("✅ Archive template สำเร็จ");
      load();
    } catch (err: any) {
      onMessage(err.error || "Archive template ไม่สำเร็จ");
    }
  };

  return (
    <div className="card mb-6">
      <div className="flex flex-col sm:flex-row justify-between gap-3 mb-4">
        <div>
          <h2 className="text-lg font-bold text-sun-gold-light">🧩 Room Templates</h2>
          <p className="text-sun-gold/40 text-xs">
            สร้าง template ต่อประเภทเกม แล้วใช้เป็นชั้น config ก่อน room snapshot
          </p>
        </div>
        <button
          type="button"
          onClick={() => { resetForm(); setShowForm(!showForm); }}
          className="btn-green text-sm py-2"
        >
          ➕ สร้าง Template
        </button>
      </div>

      {showForm && (
        <div className="bg-sun-black/40 rounded-lg p-4 mb-4 space-y-3">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <select
              value={form.game_type_id}
              onChange={event => {
                setForm({ ...form, game_type_id: event.target.value });
                loadPreview(event.target.value, editing?.id);
              }}
              className="input-field"
            >
              <option value="">เลือกเกม</option>
              {gameTypes.filter(game => game.is_active).map(game => (
                <option key={game.id} value={game.id}>{game.name_th || game.name}</option>
              ))}
            </select>
            <input
              value={form.name}
              onChange={event => setForm({ ...form, name: event.target.value })}
              placeholder="ชื่อ template"
              className="input-field"
            />
            <select
              value={form.mode}
              onChange={event => setForm({ ...form, mode: event.target.value })}
              className="input-field"
            >
              <option value="cash">cash</option>
              <option value="private">private</option>
              <option value="practice">practice</option>
              <option value="tournament">tournament</option>
            </select>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            {ROOM_FIELDS.map(field => (
              <div key={field}>
                <label className="text-sun-gold/50 text-[11px] block mb-1">{field}</label>
                <input
                  type="number"
                  value={form.config.room_defaults?.[field] ?? ""}
                  onChange={event => setForm({
                    ...form,
                    config: {
                      ...form.config,
                      room_defaults: {
                        ...(form.config.room_defaults || {}),
                        [field]: event.target.value === "" ? undefined : Number(event.target.value),
                      },
                    },
                  })}
                  className="input-field text-sm"
                />
              </div>
            ))}
          </div>

          {POLICY_SECTIONS.map(section => {
            const fields = Object.entries(definitions[section.configKey]?.fields || {})
              .filter(([, field]: [string, any]) => field.scopes?.includes('template'));
            if (fields.length === 0) return null;
            return (
              <div key={section.key} className="border border-sun-gold/10 rounded-lg p-3">
                <h3 className="text-sun-gold-light text-sm font-bold mb-3">{section.title}</h3>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                  {fields.map(([fieldName, field]: [string, any]) => (
                    <div key={fieldName}>
                      <label className="text-sun-gold/50 text-[11px] block mb-1">
                        {field.description?.th || fieldName}
                        <span className="block font-mono text-sun-gold/30">{fieldName} • {field.type}{field.unit ? ` • ${field.unit}` : ''}</span>
                      </label>
                      {field.type === 'boolean' ? (
                        <input
                          type="checkbox"
                          checked={Boolean(form.config.policies?.[section.key]?.[fieldName])}
                          onChange={event => setForm({
                            ...form,
                            config: {
                              ...form.config,
                              policies: {
                                ...(form.config.policies || {}),
                                [section.key]: {
                                  ...(form.config.policies?.[section.key] || {}),
                                  [fieldName]: event.target.checked,
                                },
                              },
                            },
                          })}
                          className="accent-yellow-500"
                        />
                      ) : field.enum ? (
                        <select
                          value={form.config.policies?.[section.key]?.[fieldName] ?? ""}
                          onChange={event => setForm({
                            ...form,
                            config: {
                              ...form.config,
                              policies: {
                                ...(form.config.policies || {}),
                                [section.key]: {
                                  ...(form.config.policies?.[section.key] || {}),
                                  [fieldName]: event.target.value || undefined,
                                },
                              },
                            },
                          })}
                          className="input-field text-sm"
                        >
                          <option value="">—</option>
                          {field.enum.map((option: any) => <option key={String(option)} value={option}>{String(option)}</option>)}
                        </select>
                      ) : (
                        <input
                          type={field.type === 'integer' || field.type === 'number' ? 'number' : 'text'}
                          value={form.config.policies?.[section.key]?.[fieldName] ?? ""}
                          onChange={event => setForm({
                            ...form,
                            config: {
                              ...form.config,
                              policies: {
                                ...(form.config.policies || {}),
                                [section.key]: {
                                  ...(form.config.policies?.[section.key] || {}),
                                  [fieldName]: event.target.value === ""
                                    ? undefined
                                    : field.type === 'integer' || field.type === 'number'
                                      ? Number(event.target.value)
                                      : event.target.value,
                                },
                              },
                            },
                          })}
                          className="input-field text-sm"
                        />
                      )}
                    </div>
                  ))}
                </div>
              </div>
            );
          })}

          <input
            value={reason}
            onChange={event => setReason(event.target.value)}
            placeholder="เหตุผลการแก้ไข"
            className="input-field text-sm"
          />

          {preview && (
            <pre className="text-[10px] text-sun-gold/60 bg-sun-black/30 rounded p-3 max-h-40 overflow-auto">
              {JSON.stringify(preview, null, 2)}
            </pre>
          )}

          <div className="flex gap-2">
            <button type="button" onClick={save} className="btn-green text-sm py-2">
              {editing ? "บันทึก Template" : "สร้าง Template"}
            </button>
            <button type="button" onClick={() => { setShowForm(false); resetForm(); }} className="btn-black text-sm py-2">
              ยกเลิก
            </button>
          </div>
        </div>
      )}

      <div className="overflow-x-auto">
        <table className="w-full text-sm min-w-[700px]">
          <thead>
            <tr className="text-sun-gold/60 border-b border-sun-gold/20">
              <th className="text-left py-2">Template</th>
              <th className="text-left py-2">เกม</th>
              <th className="text-center py-2">Mode</th>
              <th className="text-center py-2">Revision</th>
              <th className="text-center py-2">ห้องที่ใช้</th>
              <th className="text-center py-2">สถานะ</th>
              <th className="text-left py-2">จัดการ</th>
            </tr>
          </thead>
          <tbody>
            {activeTemplates.map(template => (
              <tr key={template.id} className="table-row">
                <td className="py-2">{template.name}</td>
                <td className="py-2 text-xs">{template.game_type_name_th || template.game_type_name}</td>
                <td className="py-2 text-center">{template.mode}</td>
                <td className="py-2 text-center">{template.revision}</td>
                <td className="py-2 text-center">{template.active_room_count ?? 0}</td>
                <td className="py-2 text-center">{template.status}</td>
                <td className="py-2 space-x-2">
                  <button
                    type="button"
                    onClick={() => {
                      setEditing(template);
                      setForm({
                        game_type_id: template.game_type_id,
                        name: template.name,
                        mode: template.mode,
                        config: template.config || {},
                      });
                      setShowForm(true);
                      loadPreview(template.game_type_id, template.id);
                    }}
                    className="text-sun-gold-light text-xs"
                  >
                    แก้ไข
                  </button>
                  <button type="button" onClick={() => clone(template)} className="text-blue-300 text-xs">clone</button>
                  <button type="button" onClick={() => archive(template)} className="text-red-300 text-xs">archive</button>
                </td>
              </tr>
            ))}
            {activeTemplates.length === 0 && (
              <tr><td colSpan={7} className="py-6 text-center text-sun-gold/30">ยังไม่มี template</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
