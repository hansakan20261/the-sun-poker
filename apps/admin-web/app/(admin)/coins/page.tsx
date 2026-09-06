"use client";
import { useState, useEffect } from "react";
import { useSearchParams } from "next/navigation";
import { api, walletApi } from "@/lib/api";

export default function CoinsPage() {
  const searchParams = useSearchParams();
  const [searchUsername, setSearchUsername] = useState("");
  const [foundUser, setFoundUser] = useState<any>(null);
  const [mode, setMode] = useState<"credit" | "debit">("credit");
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [result, setResult] = useState<any>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const userParam = searchParams.get("user");
    if (userParam) {
      setSearchUsername(userParam);
      // Auto-search after a tick
      setTimeout(() => {
        api(`/api/admin/users/search?q=${userParam}`).then(data => {
          if (data.user) setFoundUser(data.user);
        }).catch(() => {});
      }, 100);
    }
  }, [searchParams]);

  const searchUser = async () => {
    setError(""); setFoundUser(null); setResult(null);
    try {
      // ค้นหาผู้ใช้จาก DB จริง
      const data = await api(`/api/admin/users/search?q=${searchUsername}`);
      if (data.user) setFoundUser(data.user);
      else setError("ไม่พบผู้ใช้");
    } catch { setError("ไม่พบผู้ใช้"); }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!foundUser || !amount) return;
    setLoading(true); setError(""); setResult(null);
    try {
      const data = mode === "credit"
        ? await walletApi.creditUser(foundUser.id, { cash_amount: Number(amount), note })
        : await walletApi.debitUser(foundUser.id, { coin_amount: Number(amount), note });
      setResult(data);
      setAmount(""); setNote("");
    } catch (err: any) {
      setError(err.error || "ทำรายการไม่สำเร็จ");
    } finally { setLoading(false); }
  };

  return (
    <div>
      <h1 className="text-2xl font-bold text-sun-gold-light mb-6">💰 เติม / ถอนเหรียญ</h1>

      <details className="mb-4 text-xs text-sun-gold/50 bg-sun-black/30 rounded-lg p-3">
        <summary className="cursor-pointer text-sun-gold/70 font-bold">ℹ️ วิธีใช้งานหน้านี้</summary>
        <div className="mt-2 space-y-1">
          <p>📋 <b>หน้านี้คืออะไร:</b> เติมหรือถอนเหรียญให้ผู้เล่น</p>
          <p>🔍 <b>ขั้นตอน:</b></p>
          <p className="pl-4">1. พิมพ์ username หรือเบอร์โทรของผู้เล่น แล้วกดค้นหา</p>
          <p className="pl-4">2. ตรวจสอบว่าเป็นคนที่ต้องการ (ดูชื่อ + ยอดเหรียญ)</p>
          <p className="pl-4">3. เลือก "เติม" หรือ "ถอน"</p>
          <p className="pl-4">4. กรอกจำนวน + หมายเหตุ (เช่น "โอนผ่าน SCB 14:30")</p>
          <p className="pl-4">5. กดยืนยัน</p>
          <p>⚠️ <b>ข้อควรระวัง:</b></p>
          <p className="pl-4">• เติม = กรอกเป็น "บาท" ระบบจะแปลงเป็นเหรียญตามอัตราแลกเปลี่ยน</p>
          <p className="pl-4">• ถอน = กรอกเป็น "เหรียญ" ที่จะหักออกจากบัญชี</p>
          <p className="pl-4">• ทุกรายการจะถูกบันทึกไว้ ตรวจสอบย้อนหลังได้ที่หน้ารายงาน</p>
        </div>
      </details>

      {/* ค้นหาผู้ใช้ */}
      <div className="card mb-6">
        <h2 className="text-lg font-bold text-sun-gold-light mb-4">🔍 ค้นหาผู้ใช้</h2>
        <div className="flex gap-4">
          <input type="text" placeholder="Username / Email / Phone" value={searchUsername}
            onChange={(e) => setSearchUsername(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && searchUser()}
            className="input-field flex-1" />
          <button onClick={searchUser} className="btn-primary">ค้นหา</button>
        </div>
      </div>

      {error && <div className="bg-red-900/50 border border-red-500 text-red-300 px-4 py-3 rounded mb-4">{error}</div>}
      {result && (
        <div className="bg-green-900/50 border border-green-500 text-green-300 px-4 py-3 rounded mb-4">
          ✅ {mode === "credit" ? "เติม" : "ถอน"}สำเร็จ — {result.coin_amount?.toLocaleString()} 🪙
          (ยอดคงเหลือ: {result.balance_after?.toLocaleString()} 🪙)
        </div>
      )}

      {/* ข้อมูลผู้ใช้ + ฟอร์มเติม/ถอน */}
      {foundUser && (
        <div className="card">
          <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between mb-6 gap-3">
            <div>
              <h2 className="text-lg font-bold text-sun-gold-light">👤 {foundUser.display_name || foundUser.username}</h2>
              <p className="text-sun-gold/60 text-sm">@{foundUser.username} | {foundUser.email || "-"} | {foundUser.phone || "-"}</p>
            </div>
            <div className="text-right">
              <p className="text-sun-gold/60 text-sm">ยอดเหรียญ</p>
              <p className="text-2xl font-bold text-sun-gold-light">{Number(foundUser.balance).toLocaleString()} 🪙</p>
            </div>
          </div>

          <div className="flex gap-4 mb-6">
            <button onClick={() => setMode("credit")}
              className={`flex-1 py-3 rounded-lg font-bold transition-all ${mode === "credit" ? "bg-sun-green text-white" : "bg-sun-black/50 text-sun-gold/50"}`}>
              ➕ เติมเหรียญ
            </button>
            <button onClick={() => setMode("debit")}
              className={`flex-1 py-3 rounded-lg font-bold transition-all ${mode === "debit" ? "bg-red-700 text-white" : "bg-sun-black/50 text-sun-gold/50"}`}>
              ➖ ถอนเหรียญ
            </button>
          </div>

          <form onSubmit={handleSubmit}>
            <label className="text-sun-gold/60 text-sm block mb-1">
              {mode === "credit" ? "จำนวนเงิน (บาท)" : "จำนวนเหรียญ"}
            </label>
            <input type="number" placeholder={mode === "credit" ? "เช่น 5000" : "เช่น 5000"} value={amount}
              onChange={(e) => setAmount(e.target.value)} className="input-field mb-4" required min="1" />

            <label className="text-sun-gold/60 text-sm block mb-1">หมายเหตุ</label>
            <input type="text" placeholder="เช่น โอนผ่าน SCB เวลา 14:30" value={note}
              onChange={(e) => setNote(e.target.value)} className="input-field mb-6" />

            <button type="submit" disabled={loading}
              className={`w-full font-bold py-3 rounded-lg ${mode === "credit" ? "btn-green" : "btn-danger"}`}>
              {loading ? "กำลังทำรายการ..." : mode === "credit" ? "✅ ยืนยันเติมเหรียญ" : "✅ ยืนยันถอนเหรียญ"}
            </button>
          </form>
        </div>
      )}
    </div>
  );
}
