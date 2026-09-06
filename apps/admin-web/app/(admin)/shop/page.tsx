"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";

export default function ShopPage() {
  const [items, setItems] = useState<any[]>([]);
  const [categories, setCategories] = useState<any[]>([]);
  const [showCreate, setShowCreate] = useState(false);
  const [message, setMessage] = useState("");
  const [form, setForm] = useState({ category_id: "", name: "", price: 100, description: "", is_consumable: true });

  const load = async () => {
    const data = await api("/api/admin/shop/items");
    setItems(data.items); setCategories(data.categories);
  };
  useEffect(() => { load(); }, []);

  const createItem = async (e: React.FormEvent) => {
    e.preventDefault();
    await api("/api/admin/shop/items", { method: "POST", body: JSON.stringify(form) });
    setMessage("เพิ่มสินค้าสำเร็จ"); setShowCreate(false); load();
  };

  const toggleItem = async (id: string) => {
    await api(`/api/admin/shop/items/${id}/toggle`, { method: "PUT" }); load();
  };

  return (
    <div>
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 mb-6">
        <h1 className="text-2xl font-bold text-sun-gold-light">🛍️ จัดการร้านค้า</h1>
        <button onClick={() => setShowCreate(!showCreate)} className="btn-green text-sm py-2">➕ เพิ่มสินค้า</button>
      </div>

      <details className="mb-4 text-xs text-sun-gold/50 bg-sun-black/30 rounded-lg p-3">
        <summary className="cursor-pointer text-sun-gold/70 font-bold">ℹ️ วิธีใช้งานหน้านี้</summary>
        <div className="mt-2 space-y-1">
          <p>📋 <b>หน้านี้คืออะไร:</b> จัดการสินค้าในร้านค้าภายในเกม</p>
          <p>🛍️ <b>สินค้าคืออะไร:</b> ไอเทมที่ผู้เล่นซื้อด้วยเหรียญ เช่น กรอบโปรไฟล์, อิโมจิพิเศษ, VIP</p>
          <p>⚡ <b>สิ่งที่ทำได้:</b></p>
          <p className="pl-4">• เพิ่มสินค้าใหม่ → เลือกหมวด, ตั้งชื่อ, ตั้งราคา</p>
          <p className="pl-4">• เปิด/ปิดสินค้า → ปิดแล้วผู้เล่นจะไม่เห็นในร้าน</p>
          <p>📦 <b>ประเภท:</b></p>
          <p className="pl-4">• "ใช้แล้วหมด" = ซื้อแล้วใช้ได้ครั้งเดียว (เช่น กล่องสุ่ม)</p>
          <p className="pl-4">• "ถาวร" = ซื้อแล้วได้ไปตลอด (เช่น กรอบ VIP)</p>
        </div>
      </details>
      {message && <div className="bg-green-900/50 border border-green-500 text-green-300 px-4 py-2 rounded mb-4 flex justify-between"><span>{message}</span><button onClick={() => setMessage("")}>✕</button></div>}

      {showCreate && (
        <form onSubmit={createItem} className="card mb-6 grid grid-cols-1 md:grid-cols-2 gap-3">
          <select value={form.category_id} onChange={(e) => setForm({...form, category_id: e.target.value})} className="input-field" required>
            <option value="">เลือกหมวดหมู่</option>
            {categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
          <input placeholder="ชื่อสินค้า" value={form.name} onChange={(e) => setForm({...form, name: e.target.value})} className="input-field" required />
          <input type="number" placeholder="ราคา (เหรียญ)" value={form.price} onChange={(e) => setForm({...form, price: Number(e.target.value)})} className="input-field" required />
          <input placeholder="คำอธิบาย" value={form.description} onChange={(e) => setForm({...form, description: e.target.value})} className="input-field" />
          <label className="flex items-center gap-2 text-sm text-sun-gold/60">
            <input type="checkbox" checked={form.is_consumable} onChange={(e) => setForm({...form, is_consumable: e.target.checked})} /> ใช้แล้วหมด (consumable)
          </label>
          <div className="flex gap-2">
            <button type="submit" className="btn-green text-sm py-2 flex-1">✅ เพิ่ม</button>
            <button type="button" onClick={() => setShowCreate(false)} className="btn-black text-sm py-2 flex-1">ยกเลิก</button>
          </div>
        </form>
      )}

      <div className="card">
        <div className="overflow-x-auto">
        <table className="w-full text-sm min-w-[500px]">
          <thead>
            <tr className="text-sun-gold/60 border-b border-sun-gold/20">
              <th className="text-left py-2">สินค้า</th>
              <th className="text-left py-2">หมวด</th>
              <th className="text-right py-2">ราคา</th>
              <th className="text-center py-2">ประเภท</th>
              <th className="text-center py-2">สถานะ</th>
              <th className="text-left py-2">จัดการ</th>
            </tr>
          </thead>
          <tbody>
            {items.map((i) => (
              <tr key={i.id} className="table-row">
                <td className="py-2">{i.name}</td>
                <td className="py-2 text-xs text-sun-gold/60">{i.category_name}</td>
                <td className="py-2 text-right">{Number(i.price).toLocaleString()} 🪙</td>
                <td className="py-2 text-center text-xs">{i.is_consumable ? "ใช้แล้วหมด" : "ถาวร"}</td>
                <td className="py-2 text-center">
                  {i.is_active ? <span className="text-green-400 text-xs">🟢</span> : <span className="text-red-400 text-xs">🔴</span>}
                </td>
                <td className="py-2">
                  <button onClick={() => toggleItem(i.id)} className={`text-xs ${i.is_active ? "text-red-400" : "text-green-400"}`}>
                    {i.is_active ? "ปิด" : "เปิด"}
                  </button>
                </td>
              </tr>
            ))}
            {items.length === 0 && <tr><td colSpan={6} className="py-8 text-center text-sun-gold/30">ยังไม่มีสินค้า</td></tr>}
          </tbody>
        </table>
        </div>
      </div>
    </div>
  );
}
