"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";

export default function DashboardPage() {
  const [stats, setStats] = useState<any>(null);
  const [recentTx, setRecentTx] = useState<any[]>([]);

  useEffect(() => {
    Promise.all([
      api("/api/admin/reports/summary"),
      api("/api/admin/coin-transactions?limit=5"),
    ]).then(([summary, txData]) => {
      setStats(summary);
      setRecentTx(txData.transactions || []);
    }).catch(console.error);
  }, []);

  return (
    <div>
      <h1 className="text-2xl font-bold text-sun-gold-light mb-6">📊 Dashboard</h1>

      <details className="mb-4 text-xs text-sun-gold/50 bg-sun-black/30 rounded-lg p-3">
        <summary className="cursor-pointer text-sun-gold/70 font-bold">ℹ️ วิธีใช้งานหน้านี้</summary>
        <div className="mt-2 space-y-1">
          <p>📋 <b>หน้านี้คืออะไร:</b> หน้าภาพรวมระบบ แสดงสถิติสำคัญทั้งหมดในที่เดียว</p>
          <p>👁 <b>ข้อมูลที่แสดง:</b></p>
          <p className="pl-4">• ผู้ใช้ทั้งหมด = จำนวนบัญชีในระบบ (รวมที่ถูกระงับ)</p>
          <p className="pl-4">• Agent = ตัวแทนที่ช่วยหาลูกค้า</p>
          <p className="pl-4">• เติมเหรียญรวม = เงินทั้งหมดที่ Admin เคยเติมให้ผู้เล่น</p>
          <p className="pl-4">• ห้องเล่นเปิดอยู่ = ห้องที่มีคนกำลังเล่นอยู่ตอนนี้ / ห้องทั้งหมดในระบบ</p>
          <p>📊 <b>ธุรกรรมล่าสุด:</b> แสดง 5 รายการเติม/ถอนเหรียญล่าสุดที่ Admin ทำ</p>
          <p>💡 <b>ใช้ทำอะไร:</b> ดูภาพรวมเร็วๆ ว่าระบบมีสถานะอย่างไร มีปัญหาอะไรไหม</p>
        </div>
      </details>

      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
        <div className="stat-card">
          <p className="text-sun-gold/60 text-sm">ผู้ใช้ทั้งหมด</p>
          <p className="text-3xl font-bold text-sun-gold-light mt-2">
            {stats ? Number(stats.users.total).toLocaleString() : "..."}
          </p>
          {stats && <p className="text-xs text-sun-gold/40 mt-1">ระงับ: {stats.users.suspended}</p>}
        </div>
        <div className="stat-card">
          <p className="text-sun-gold/60 text-sm">Agent</p>
          <p className="text-3xl font-bold text-green-400 mt-2">
            {stats ? Number(stats.agents.total).toLocaleString() : "..."}
          </p>
        </div>
        <div className="stat-card">
          <p className="text-sun-gold/60 text-sm">เติมเหรียญรวม</p>
          <p className="text-3xl font-bold text-sun-gold-light mt-2">
            {stats ? Number(stats.coins.total_credit).toLocaleString() : "..."} 🪙
          </p>
        </div>
        <div className="stat-card">
          <p className="text-sun-gold/60 text-sm">ห้องเล่นเปิดอยู่</p>
          <p className="text-3xl font-bold text-sun-gold-light mt-2">
            {stats ? `${stats.tables.playing} / ${stats.tables.total}` : "..."}
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
        <div className="stat-card">
          <p className="text-sun-gold/60 text-sm">คลับ</p>
          <p className="text-2xl font-bold text-sun-gold-light mt-2">
            {stats ? `${stats.clubs.active} เปิด / ${stats.clubs.total} ทั้งหมด` : "..."}
          </p>
        </div>
        <div className="stat-card">
          <p className="text-sun-gold/60 text-sm">ถอนเหรียญรวม</p>
          <p className="text-2xl font-bold text-red-400 mt-2">
            {stats ? Number(stats.coins.total_debit).toLocaleString() : "..."} 🪙
          </p>
        </div>
      </div>

      <div className="card">
        <h2 className="text-lg font-bold text-sun-gold-light mb-4">💰 ธุรกรรมเติม/ถอนล่าสุด</h2>
        {recentTx.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full text-sm min-w-[500px]">
              <thead>
                <tr className="text-sun-gold/60 border-b border-sun-gold/20">
                  <th className="text-left py-2">วันที่</th>
                  <th className="text-left py-2">ผู้ใช้</th>
                  <th className="text-left py-2">ประเภท</th>
                  <th className="text-right py-2">จำนวน</th>
                  <th className="text-left py-2">Admin</th>
                </tr>
              </thead>
              <tbody>
                {recentTx.map((tx: any) => (
                  <tr key={tx.id} className="table-row">
                    <td className="py-2 whitespace-nowrap">{new Date(tx.created_at).toLocaleString("th")}</td>
                    <td className="py-2">{tx.user_username}</td>
                    <td className="py-2">
                      <span className={tx.type === "credit" ? "text-green-400" : "text-red-400"}>
                        {tx.type === "credit" ? "เติม" : "ถอน"}
                      </span>
                    </td>
                    <td className="py-2 text-right whitespace-nowrap">{Number(tx.coin_amount).toLocaleString()} 🪙</td>
                    <td className="py-2">{tx.admin_username}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="text-sun-gold/40">ยังไม่มีธุรกรรม</p>
        )}
      </div>
    </div>
  );
}