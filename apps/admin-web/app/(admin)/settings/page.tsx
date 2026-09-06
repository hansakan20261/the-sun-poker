"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import ConfigStudio from "@/components/config-studio";

export default function SettingsPage() {
  const [features, setFeatures] = useState<any[]>([]);
  const [message, setMessage] = useState("");

  // Background settings state
  const [bgUrl, setBgUrl] = useState("");
  const [bgOpacity, setBgOpacity] = useState(0.55);
  const [bgLoading, setBgLoading] = useState(false);
  const [bgCurrent, setBgCurrent] = useState<{ background_url: string | null; overlay_opacity: number } | null>(null);

  const load = async () => {
    const data = await api("/api/admin/settings");
    setFeatures(data.features);
  };

  const loadBg = async () => {
    try {
      const data = await api("/api/settings/admin/background");
      setBgCurrent(data);
      setBgUrl(data.background_url || "");
      setBgOpacity(data.overlay_opacity ?? 0.55);
    } catch { /* ignore */ }
  };

  useEffect(() => { load(); loadBg(); }, []);

  const toggleFeature = async (key: string) => {
    await api(`/api/admin/settings/features/${key}/toggle`, { method: "PUT" });
    load();
  };

  const saveBg = async () => {
    setBgLoading(true);
    try {
      await api("/api/settings/admin/background", {
        method: "PUT",
        body: JSON.stringify({ background_url: bgUrl || null, overlay_opacity: bgOpacity }),
      });
      setMessage("✅ บันทึก Background สำเร็จ — แอปจะโหลดรูปใหม่ในครั้งถัดไป");
      loadBg();
    } catch (e: any) {
      setMessage("❌ บันทึกไม่สำเร็จ: " + (e.error || "Unknown error"));
    } finally {
      setBgLoading(false);
    }
  };

  const resetBg = async () => {
    setBgLoading(true);
    try {
      await api("/api/settings/admin/background", { method: "DELETE" });
      setMessage("✅ รีเซ็ต Background กลับเป็น Default สำเร็จ");
      setBgUrl(""); setBgOpacity(0.55);
      loadBg();
    } catch {
      setMessage("❌ รีเซ็ตไม่สำเร็จ");
    } finally {
      setBgLoading(false);
    }
  };

  return (
    <div>
      <h1 className="text-2xl font-bold text-sun-gold-light mb-6">⚙️ ตั้งค่าระบบ</h1>

      <details className="mb-4 text-xs text-sun-gold/50 bg-sun-black/30 rounded-lg p-3">
        <summary className="cursor-pointer text-sun-gold/70 font-bold">ℹ️ วิธีใช้งานหน้านี้</summary>
        <div className="mt-2 space-y-1">
          <p>📋 <b>หน้านี้คืออะไร:</b> ตั้งค่าระบบทั้งหมด</p>
          <p>🖼️ <b>พื้นหลังแอป:</b> เปลี่ยนรูป Background ของแอปทั้งหมด — ใส่ URL รูปภาพ + ปรับความเข้มของสีดำทับ</p>
          <p>📋 <b>ค่าตั้งระบบ:</b> แก้ไขผ่าน Config Studio ซึ่งโหลด field/ขอบเขต/default จาก Config Registry</p>
          <p className="pl-4">• อัตราแลกเปลี่ยนเหรียญ (กี่บาท = กี่เหรียญ)</p>
          <p className="pl-4">• ค่าธรรมเนียม Rake (%)</p>
          <p className="pl-4">• วงเงินเติม/ถอนสูงสุด</p>
          <p>🎛️ <b>Feature Flags:</b> เปิด/ปิดเมนูและฟีเจอร์ในแอป — เช่น ปิดร้านค้า, ปิดทัวร์นาเมนต์ชั่วคราว</p>
          <p>⚠️ <b>ข้อควรระวัง:</b> การแก้ไขค่าตั้งระบบมีผลทันทีกับผู้เล่นทุกคน</p>
        </div>
      </details>
      {message && (
        <div className="bg-green-900/50 border border-green-500 text-green-300 px-4 py-2 rounded mb-4 flex justify-between">
          <span>{message}</span><button onClick={() => setMessage("")}>✕</button>
        </div>
      )}

      {/* ── Background Settings ── */}
      <div className="card mb-6">
        <h2 className="text-lg font-bold text-sun-gold-light mb-1">🖼️ พื้นหลังแอป (App Background)</h2>
        <p className="text-sun-gold/40 text-xs mb-4">
          เปลี่ยนรูปพื้นหลังที่แสดงในทุกหน้าของแอป — ใส่ URL รูปภาพ (https://...) หรือเว้นว่างเพื่อใช้รูป default
        </p>

        {/* Preview */}
        <div className="mb-4">
          <p className="text-sun-gold/60 text-xs mb-2">ค่าปัจจุบัน:</p>
          <div className="bg-sun-black/50 rounded-lg p-3 text-xs font-mono">
            <span className="text-sun-gold/40">background_url: </span>
            <span className="text-white">{bgCurrent?.background_url || "(default — รูปในแอป)"}</span>
            <br />
            <span className="text-sun-gold/40">overlay_opacity: </span>
            <span className="text-white">{bgCurrent?.overlay_opacity ?? 0.55}</span>
          </div>
        </div>

        {/* URL input */}
        <div className="mb-3">
          <label className="text-sun-gold/60 text-xs block mb-1">URL รูปพื้นหลัง (เว้นว่าง = ใช้รูป default)</label>
          <input
            type="text"
            value={bgUrl}
            onChange={(e) => setBgUrl(e.target.value)}
            placeholder="https://example.com/background.jpg"
            className="input-field w-full text-sm"
          />
        </div>

        {/* Opacity slider */}
        <div className="mb-4">
          <label className="text-sun-gold/60 text-xs block mb-1">
            ความเข้มของ Overlay สีดำ: <span className="text-white font-bold">{Math.round(bgOpacity * 100)}%</span>
            <span className="text-sun-gold/30 ml-2">(0% = โปร่งใส, 100% = ดำสนิท — แนะนำ 45-65%)</span>
          </label>
          <input
            type="range"
            min={0} max={1} step={0.05}
            value={bgOpacity}
            onChange={(e) => setBgOpacity(parseFloat(e.target.value))}
            className="w-full accent-yellow-500"
          />
          <div className="flex justify-between text-sun-gold/30 text-xs mt-1">
            <span>0% (โปร่งใส)</span>
            <span>50%</span>
            <span>100% (ดำ)</span>
          </div>
        </div>

        {/* Preview box */}
        {bgUrl && (
          <div className="mb-4 relative rounded-lg overflow-hidden" style={{ height: 120 }}>
            <img src={bgUrl} alt="preview" className="w-full h-full object-cover"
              onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; }} />
            <div className="absolute inset-0" style={{ backgroundColor: `rgba(0,0,0,${bgOpacity})` }} />
            <div className="absolute inset-0 flex items-center justify-center">
              <span className="text-white text-sm font-bold opacity-70">Preview</span>
            </div>
          </div>
        )}

        {/* Buttons */}
        <div className="flex gap-3">
          <button
            onClick={saveBg}
            disabled={bgLoading}
            className="bg-yellow-700 hover:bg-yellow-600 text-white px-6 py-2 rounded-lg text-sm font-bold disabled:opacity-50 transition-all"
          >
            {bgLoading ? "⏳ กำลังบันทึก..." : "💾 บันทึก Background"}
          </button>
          <button
            onClick={resetBg}
            disabled={bgLoading}
            className="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded-lg text-sm disabled:opacity-50 transition-all"
          >
            🔄 รีเซ็ต Default
          </button>
        </div>
      </div>

      <ConfigStudio onMessage={setMessage} />

      {/* Feature Flags */}
      <div className="card">
        <h2 className="text-lg font-bold text-sun-gold-light mb-4">🎛️ Feature Flags (เปิด/ปิดเมนู & ฟีเจอร์)</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          {features.map((f) => (
            <div key={f.id} className="flex justify-between items-center bg-sun-black/50 rounded-lg px-4 py-3">
              <div>
                <p className="text-white text-sm">{f.name}</p>
                <p className="text-sun-gold/40 text-xs">{f.feature_key}</p>
              </div>
              <button onClick={() => toggleFeature(f.feature_key)}
                className={`px-4 py-1 rounded text-xs font-bold transition-all ${
                  f.is_enabled ? "bg-green-700 text-white" : "bg-red-900 text-red-300"
                }`}>
                {f.is_enabled ? "🟢 เปิด" : "🔴 ปิด"}
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
