"use client";

import { useEffect, useMemo, useState, type ReactNode } from "react";
import { api } from "@/lib/api";

type FieldDef = {
  type: string;
  default?: any;
  min?: number;
  max?: number;
  enum?: any[];
  unit?: string;
  scopes?: string[];
  applyMode?: string;
  required?: boolean;
  sensitive?: boolean;
  description?: { th?: string; en?: string };
};

type CategoryDef = {
  key: string;
  owner?: string;
  classification?: string;
  applyMode?: string;
  fields: Record<string, FieldDef>;
};

type ConfigValue = {
  key: string;
  value: Record<string, any>;
  revision: number;
  status?: string;
  updated_at?: string;
  change_reason?: string | null;
};

type HistoryRow = {
  id: string;
  revision: number;
  before_value: Record<string, any> | null;
  after_value: Record<string, any>;
  change_reason?: string;
  updated_by_name?: string;
  created_at: string;
};

function displayValue(value: any) {
  if (value === null || value === undefined || value === "") return "—";
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}

function normalizeInput(field: FieldDef, raw: any) {
  if (field.type === "boolean") return raw === true || raw === "true";
  if (field.type === "integer" || field.type === "number") {
    if (raw === "" || raw === null || raw === undefined) return undefined;
    return Number(raw);
  }
  if (field.type === "array") {
    if (Array.isArray(raw)) return raw;
    const text = String(raw ?? "").trim();
    if (!text) return [];
    if (text.startsWith("[")) return JSON.parse(text);
    return text.split(",").map(item => item.trim()).filter(Boolean);
  }
  if (field.type === "object") {
    if (typeof raw === "object" && raw !== null) return raw;
    return JSON.parse(String(raw || "{}"));
  }
  if (raw === "" && !field.required) return null;
  return raw;
}

export default function ConfigStudio({ onMessage }: { onMessage: (message: string) => void }) {
  const [definitions, setDefinitions] = useState<CategoryDef[]>([]);
  const [values, setValues] = useState<Record<string, ConfigValue>>({});
  const [selectedKey, setSelectedKey] = useState("");
  const [draft, setDraft] = useState<Record<string, any>>({});
  const [reason, setReason] = useState("");
  const [history, setHistory] = useState<HistoryRow[]>([]);
  const [preview, setPreview] = useState<any>(null);
  const [propagation, setPropagation] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  const category = useMemo(
    () => definitions.find(item => item.key === selectedKey),
    [definitions, selectedKey],
  );

  const load = async () => {
    setLoading(true);
    setError("");
    try {
      const [defs, vals] = await Promise.all([
        api("/api/admin/config/definitions"),
        api("/api/admin/config/values?scope=system"),
      ]);
      const definitionList = defs.definitions || [];
      const valueMap = Object.fromEntries((vals.values || []).map((row: ConfigValue) => [row.key, row]));
      setDefinitions(definitionList);
      setValues(valueMap);
      if (!selectedKey && definitionList.length) {
        setSelectedKey(definitionList[0].key);
        setDraft(valueMap[definitionList[0].key]?.value || {});
      }
    } catch (err: any) {
      setError(err.error || "โหลด config ไม่สำเร็จ");
    } finally {
      setLoading(false);
    }
  };

  const loadHistory = async (key: string) => {
    if (!key) return;
    try {
      const data = await api(`/api/admin/config/history?key=${encodeURIComponent(key)}&limit=20`);
      setHistory(data.history || []);
    } catch {
      setHistory([]);
    }
  };

  const loadPropagation = async () => {
    try {
      const data = await api('/api/admin/config/propagation');
      setPropagation(data.propagation || null);
    } catch {
      setPropagation(null);
    }
  };

  useEffect(() => { load(); }, []);

  useEffect(() => {
    loadPropagation();
    const interval = setInterval(loadPropagation, 5000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    if (!selectedKey) return;
    setDraft(values[selectedKey]?.value || {});
    setPreview(null);
    loadHistory(selectedKey);
  }, [selectedKey, values]);

  const changedFields = useMemo(() => {
    const current = values[selectedKey]?.value || {};
    return Object.keys(draft).filter(field => JSON.stringify(draft[field]) !== JSON.stringify(current[field]));
  }, [draft, selectedKey, values]);

  const setField = (field: string, value: any) => {
    setDraft(current => ({ ...current, [field]: value }));
  };

  const validateDraft = async (): Promise<Record<string, any> | null> => {
    if (!category) return null;
    try {
      const payload: Record<string, any> = {};
      for (const field of Object.keys(category.fields)) {
        if (draft[field] !== undefined) payload[field] = normalizeInput(category.fields[field], draft[field]);
      }
      const result = await api("/api/admin/config/validate", {
        method: "POST",
        body: JSON.stringify({ key: selectedKey, value: payload }),
      });
      setPreview(result);
      setError("");
      return result.normalized || payload;
    } catch (err: any) {
      setError(err.error || "Config ไม่ผ่าน validation");
      return null;
    }
  };

  const publish = async () => {
    if (!category || !reason.trim()) {
      setError("กรุณาระบุเหตุผลการเปลี่ยนแปลง");
      return;
    }
    const normalized = await validateDraft();
    if (!normalized) return;
    setSaving(true);
    try {
      const currentRevision = values[selectedKey]?.revision || 0;
      await api("/api/admin/config/publish", {
        method: "POST",
        body: JSON.stringify({
          values: { [selectedKey]: normalized },
          expected_revisions: { [selectedKey]: currentRevision },
          reason,
        }),
      });
      onMessage(`✅ Publish ${selectedKey} สำเร็จ`);
      setReason("");
      await load();
    } catch (err: any) {
      setError(err.error || "Publish ไม่สำเร็จ");
    } finally {
      setSaving(false);
    }
  };

  const rollback = async (row: HistoryRow) => {
    if (!confirm(`Rollback ${selectedKey} ไป revision ${row.revision}?`)) return;
    try {
      await api(`/api/admin/config/rollback/${row.revision}`, {
        method: "POST",
        body: JSON.stringify({ key: selectedKey, reason: `Rollback to revision ${row.revision}` }),
      });
      onMessage(`✅ Rollback ${selectedKey} สำเร็จ`);
      await load();
    } catch (err: any) {
      setError(err.error || "Rollback ไม่สำเร็จ");
    }
  };

  const applyExistingRooms = async () => {
    if (selectedKey !== "room_defaults") return;
    if (!reason.trim()) {
      setError("กรุณาระบุเหตุผลก่อน apply existing rooms");
      return;
    }
    try {
      const dryRun = await api("/api/admin/config/apply-existing", {
        method: "POST",
        body: JSON.stringify({ key: selectedKey, dry_run: true, reason }),
      });
      if (!confirm(`Apply config นี้กับห้องที่เปิดอยู่ ${dryRun.affected_rooms || 0} ห้อง?`)) return;
      const applied = await api("/api/admin/config/apply-existing", {
        method: "POST",
        body: JSON.stringify({ key: selectedKey, dry_run: false, reason }),
      });
      onMessage(`✅ Apply existing rooms สำเร็จ (${applied.affected_rooms || 0} ห้อง)`);
      setReason("");
    } catch (err: any) {
      setError(err.error || "Apply existing rooms ไม่สำเร็จ");
    }
  };

  if (loading) return <div className="card text-sun-gold/60">กำลังโหลด Config Studio...</div>;

  return (
    <div className="card mb-6">
      <div className="flex flex-col lg:flex-row justify-between gap-4 mb-4">
        <div>
          <h2 className="text-lg font-bold text-sun-gold-light">🧩 Config Studio</h2>
          <p className="text-sun-gold/40 text-xs">
            แก้ config ด้วย typed form, preview diff, history และ rollback โดยใช้ definitions จาก backend
          </p>
        </div>
        <select
          value={selectedKey}
          onChange={event => setSelectedKey(event.target.value)}
          className="input-field text-sm"
        >
          {definitions.map(item => (
            <option key={item.key} value={item.key}>{item.key}</option>
          ))}
        </select>
      </div>

      {error && (
        <div className="bg-red-900/40 border border-red-700 text-red-200 px-3 py-2 rounded text-xs mb-4">
          {error}
        </div>
      )}

      {category && (
        <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
          <div className="xl:col-span-2 space-y-3">
            <div className="bg-sun-black/30 rounded-lg p-3 text-xs text-sun-gold/60">
              <div>Owner: {category.owner || "—"}</div>
              <div>Classification: {category.classification || "—"}</div>
              <div>Apply mode: {category.applyMode || "—"}</div>
              <div>Revision: {values[selectedKey]?.revision ?? "—"}</div>
            </div>

            {Object.entries(category.fields).map(([fieldName, field]) => (
              <ConfigField
                key={fieldName}
                name={fieldName}
                field={field}
                value={draft[fieldName] ?? field.default}
                currentValue={values[selectedKey]?.value?.[fieldName]}
                onChange={value => setField(fieldName, value)}
              />
            ))}
          </div>

          <div className="space-y-4">
            <div className="bg-sun-black/30 rounded-lg p-3">
              <h3 className="text-sun-gold-light font-bold text-sm mb-2">Preview changes</h3>
              {changedFields.length === 0 ? (
                <p className="text-xs text-sun-gold/40">ยังไม่มีการเปลี่ยนแปลง</p>
              ) : (
                <div className="space-y-2 text-xs">
                  {changedFields.map(field => (
                    <div key={field} className="border border-sun-gold/10 rounded p-2">
                      <div className="font-bold text-white">{field}</div>
                      <div className="text-red-300/80">− {displayValue(values[selectedKey]?.value?.[field])}</div>
                      <div className="text-green-300/80">+ {displayValue(draft[field])}</div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div className="bg-sun-black/30 rounded-lg p-3 space-y-2">
              <label className="text-sun-gold/60 text-xs block">เหตุผลการแก้ไข</label>
              <input
                value={reason}
                onChange={event => setReason(event.target.value)}
                className="input-field text-sm"
                placeholder="เช่น ปรับเวลาเกมสำหรับ event"
              />
              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={validateDraft}
                  className="bg-blue-800 hover:bg-blue-700 text-white px-3 py-2 rounded text-xs font-bold"
                >
                  Validate
                </button>
                <button
                  type="button"
                  onClick={publish}
                  disabled={saving || changedFields.length === 0}
                  className="bg-green-800 hover:bg-green-700 text-white px-3 py-2 rounded text-xs font-bold disabled:opacity-50"
                >
                  {saving ? "Publishing..." : "Publish"}
                </button>
                {selectedKey === "room_defaults" && (
                  <button
                    type="button"
                    onClick={applyExistingRooms}
                    className="bg-purple-800 hover:bg-purple-700 text-white px-3 py-2 rounded text-xs font-bold"
                  >
                    Apply Existing
                  </button>
                )}
              </div>
              {preview && (
                <pre className="text-[10px] text-green-300/80 overflow-auto max-h-48">
                  {JSON.stringify(preview, null, 2)}
                </pre>
              )}
            </div>

            <div className="bg-sun-black/30 rounded-lg p-3">
              <h3 className="text-sun-gold-light font-bold text-sm mb-2">Propagation Status</h3>
              <div className="space-y-1 max-h-40 overflow-auto text-xs">
                {propagation ? (
                  <>
                    <div className="text-green-300">ready: {propagation.ready ? 'Yes' : 'No'}</div>
                    <div className="text-sun-gold/70">missing: {(propagation.missing || []).join(', ') || '—'}</div>
                    <div className="text-sun-gold/70">stale: {(propagation.stale || []).join(', ') || '—'}</div>
                    <div className="text-sun-gold/70">lastError: {propagation.lastError || '—'}</div>
                  </>
                ) : (
                  <p className="text-sun-gold/40">loading...</p>
                )}
              </div>
            </div>

            <div className="bg-sun-black/30 rounded-lg p-3">
              <h3 className="text-sun-gold-light font-bold text-sm mb-2">History</h3>
              <div className="space-y-2 max-h-80 overflow-auto">
                {history.length === 0 && <p className="text-xs text-sun-gold/40">ยังไม่มี history</p>}
                {history.map(row => (
                  <div key={row.id} className="border border-sun-gold/10 rounded p-2 text-xs">
                    <div className="flex justify-between gap-2">
                      <span className="text-white">rev {row.revision}</span>
                      <button type="button" onClick={() => rollback(row)} className="text-yellow-300">
                        rollback
                      </button>
                    </div>
                    <div className="text-sun-gold/40">{new Date(row.created_at).toLocaleString()}</div>
                    <div className="text-sun-gold/60">{row.change_reason || "—"}</div>
                    <div className="text-sun-gold/30">{row.updated_by_name || "system"}</div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function ConfigField({ name, field, value, currentValue, onChange }: {
  name: string;
  field: FieldDef;
  value: any;
  currentValue: any;
  onChange: (value: any) => void;
}) {
  const label = field.description?.th || field.description?.en || name;
  const common = "input-field w-full text-sm";

  let input: ReactNode;
  if (field.type === "boolean") {
    input = (
      <input
        type="checkbox"
        checked={Boolean(value)}
        onChange={event => onChange(event.target.checked)}
        className="accent-yellow-500"
      />
    );
  } else if (field.enum && field.type !== "array") {
    input = (
      <select value={value ?? ""} onChange={event => onChange(event.target.value)} className={common}>
        {!field.required && <option value="">—</option>}
        {field.enum.map(option => <option key={String(option)} value={option}>{String(option)}</option>)}
      </select>
    );
  } else if (field.type === "integer" || field.type === "number") {
    input = (
      <input
        type="number"
        value={value ?? ""}
        min={field.min}
        max={field.max}
        step={field.type === "integer" ? 1 : "any"}
        onChange={event => onChange(event.target.value === "" ? undefined : Number(event.target.value))}
        className={common}
      />
    );
  } else if (field.type === "array" || field.type === "object") {
    input = (
      <textarea
        value={Array.isArray(value) && !field.enum ? value.join(", ") : JSON.stringify(value ?? (field.type === "array" ? [] : {}), null, 2)}
        onChange={event => {
          const text = event.target.value;
          if (field.type === "array" && !text.trim().startsWith("[")) {
            onChange(text.split(",").map(item => item.trim()).filter(Boolean));
          } else {
            try { onChange(JSON.parse(text)); } catch { onChange(text); }
          }
        }}
        className={`${common} font-mono h-24`}
      />
    );
  } else {
    input = (
      <input
        type="text"
        value={value ?? ""}
        onChange={event => onChange(event.target.value)}
        className={common}
      />
    );
  }

  return (
    <div className="bg-sun-black/40 rounded-lg p-3">
      <div className="flex flex-col md:flex-row md:items-center gap-2">
        <div className="md:w-80">
          <label className="text-white text-sm font-bold block">{label}</label>
          <div className="text-sun-gold/40 text-[11px] font-mono">{name}</div>
          <div className="text-sun-gold/30 text-[11px]">
            {field.type}{field.unit ? ` • ${field.unit}` : ""}{field.applyMode ? ` • ${field.applyMode}` : ""}
            {field.min !== undefined || field.max !== undefined ? ` • ${field.min ?? "-"}~${field.max ?? "-"}` : ""}
          </div>
          <div className="text-sun-gold/30 text-[11px] mt-1">
            Default: {displayValue(field.default)} • Current: {displayValue(currentValue)} • Source: system_default
          </div>
        </div>
        <div className="flex-1">{input}</div>
      </div>
      {field.description?.en && field.description?.th && (
        <p className="text-sun-gold/30 text-[11px] mt-2">{field.description.en}</p>
      )}
    </div>
  );
}
