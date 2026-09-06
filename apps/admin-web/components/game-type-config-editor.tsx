"use client";

import { useEffect, useMemo, useState } from "react";
import { api } from "@/lib/api";

const SECTIONS = [
  { key: "room_defaults", configKey: "room_defaults", title: "Room Defaults" },
  { key: "texas_holdem", configKey: "texas_holdem_policy", title: "Texas Hold'em Policy" },
  { key: "chinese_poker", configKey: "chinese_poker_policy", title: "Chinese Poker Policy" },
  { key: "tournament", configKey: "tournament_policy", title: "Tournament Policy" },
] as const;

export default function GameTypeConfigEditor({ gameTypes, onMessage }: {
  gameTypes: any[];
  onMessage: (message: string) => void;
}) {
  const [definitions, setDefinitions] = useState<Record<string, any>>({});
  const [selectedType, setSelectedType] = useState("");
  const [revision, setRevision] = useState(0);
  const [config, setConfig] = useState<any>({ room_defaults: {}, policies: {} });
  const [preview, setPreview] = useState<any>(null);
  const [reason, setReason] = useState("");
  const [loading, setLoading] = useState(false);

  const selectedGameType = useMemo(
    () => gameTypes.find(type => type.id === selectedType),
    [gameTypes, selectedType],
  );

  useEffect(() => {
    api("/api/admin/config/definitions")
      .then(data => setDefinitions(Object.fromEntries((data.definitions || []).map((item: any) => [item.key, item]))))
      .catch(() => setDefinitions({}));
  }, []);

  const load = async (gameTypeId: string) => {
    setSelectedType(gameTypeId);
    setPreview(null);
    setReason("");
    if (!gameTypeId) {
      setConfig({ room_defaults: {}, policies: {} });
      setRevision(0);
      return;
    }
    setLoading(true);
    try {
      const [current, effective] = await Promise.all([
        api(`/api/admin/config/game-types/${gameTypeId}/config`),
        api(`/api/admin/config/effective?gameTypeId=${encodeURIComponent(gameTypeId)}`),
      ]);
      setConfig(current.config?.config || { room_defaults: {}, policies: {} });
      setRevision(Number(current.config?.revision || 0));
      setPreview(effective);
    } catch (err: any) {
      onMessage(err.error || "โหลด game type config ไม่สำเร็จ");
    } finally {
      setLoading(false);
    }
  };

  const updateField = (section: string, fieldName: string, value: any) => {
    setConfig((current: any) => section === "room_defaults"
      ? {
          ...current,
          room_defaults: { ...(current.room_defaults || {}), [fieldName]: value },
        }
      : {
          ...current,
          policies: {
            ...(current.policies || {}),
            [section]: {
              ...(current.policies?.[section] || {}),
              [fieldName]: value,
            },
          },
        });
  };

  const save = async () => {
    if (!selectedType) return;
    if (!reason.trim()) {
      onMessage("กรุณาระบุเหตุผลการแก้ไข");
      return;
    }
    try {
      await api(`/api/admin/config/game-types/${selectedType}/config`, {
        method: "PUT",
        body: JSON.stringify({ config, expected_revision: revision, reason }),
      });
      onMessage(`✅ บันทึก config ของ ${selectedGameType?.name_th || selectedGameType?.name} สำเร็จ`);
      await load(selectedType);
    } catch (err: any) {
      onMessage(err.error || "บันทึก game type config ไม่สำเร็จ");
    }
  };

  return (
    <div className="card mb-6">
      <h2 className="text-lg font-bold text-sun-gold-light">🎮 Game Type Config</h2>
      <p className="text-sun-gold/40 text-xs mb-4">
        ตั้งค่าเฉพาะเกม โดยอยู่เหนือ system default และต่ำกว่า room template/snapshot/runtime override
      </p>

      <select value={selectedType} onChange={event => load(event.target.value)} className="input-field mb-4">
        <option value="">เลือกเกม</option>
        {gameTypes.filter(type => type.is_active).map(type => (
          <option key={type.id} value={type.id}>{type.name_th || type.name}</option>
        ))}
      </select>

      {loading && <p className="text-sun-gold/50 text-xs">กำลังโหลด...</p>}
      {selectedType && !loading && (
        <div className="space-y-4">
          <div className="bg-sun-black/30 rounded-lg p-3 text-xs text-sun-gold/50">
            Revision: {revision || "—"} • Apply mode: new_room
          </div>

          {SECTIONS.map(section => {
            const fields = Object.entries(definitions[section.configKey]?.fields || {})
              .filter(([, field]: [string, any]) => field.scopes?.includes('game_type'));
            if (fields.length === 0) return null;
            return (
              <div key={section.key} className="border border-sun-gold/10 rounded-lg p-3">
                <h3 className="text-sun-gold-light text-sm font-bold mb-3">{section.title}</h3>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                  {fields.map(([fieldName, field]: [string, any]) => {
                    const value = section.key === "room_defaults"
                      ? config.room_defaults?.[fieldName]
                      : config.policies?.[section.key]?.[fieldName];
                    return (
                      <div key={fieldName}>
                        <label className="text-sun-gold/50 text-[11px] block mb-1">
                          {field.description?.th || fieldName}
                          <span className="block font-mono text-sun-gold/30">
                            {fieldName} • {field.type}{field.unit ? ` • ${field.unit}` : ''}
                          </span>
                        </label>
                        {field.type === 'boolean' ? (
                          <input
                            type="checkbox"
                            checked={Boolean(value)}
                            onChange={event => updateField(section.key, fieldName, event.target.checked)}
                            className="accent-yellow-500"
                          />
                        ) : field.enum ? (
                          <select
                            value={value ?? ""}
                            onChange={event => updateField(section.key, fieldName, event.target.value || undefined)}
                            className="input-field text-sm"
                          >
                            <option value="">—</option>
                            {field.enum.map((option: any) => <option key={String(option)} value={option}>{String(option)}</option>)}
                          </select>
                        ) : (
                          <input
                            type={field.type === 'integer' || field.type === 'number' ? 'number' : 'text'}
                            value={value ?? ""}
                            onChange={event => updateField(
                              section.key,
                              fieldName,
                              event.target.value === ""
                                ? undefined
                                : field.type === 'integer' || field.type === 'number'
                                  ? Number(event.target.value)
                                  : event.target.value,
                            )}
                            className="input-field text-sm"
                          />
                        )}
                      </div>
                    );
                  })}
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
            <pre className="text-[10px] text-sun-gold/60 bg-sun-black/30 rounded p-3 max-h-48 overflow-auto">
              {JSON.stringify(preview, null, 2)}
            </pre>
          )}
          <button type="button" onClick={save} className="btn-green text-sm py-2">
            บันทึก Game Type Config
          </button>
        </div>
      )}
    </div>
  );
}
