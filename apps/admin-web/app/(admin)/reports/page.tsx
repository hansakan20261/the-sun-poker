"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";

export default function ReportsPage() {
  const [summary, setSummary] = useState<any>(null);
  const [daily, setDaily] = useState<any[]>([]);
  const [topPlayers, setTopPlayers] = useState<any[]>([]);

  useEffect(() => {
    Promise.all([
      api("/api/admin/reports/summary"),
      api("/api/admin/reports/daily-coins"),
      api("/api/admin/reports/top-players"),
    ]).then(([s, d, t]) => {
      setSummary(s); setDaily(d.daily); setTopPlayers(t.players);
    }).catch(console.error);
  }, []);

  if (!summary) return <div className="text-sun-gold/40">Loading...</div>;

  return (
    <div>
      <h1 className="text-2xl font-bold text-sun-gold-light mb-6">📈 รายงาน</h1>

      <details className="mb-4 text-xs text-sun-gold/50 bg-sun-black/30 rounded-lg p-3">
        <summary className="cursor-pointer text-sun-gold/70 font-bold">ℹ️ วิธีใช้งานหน้านี้</summary>
        <div className="mt-2 space-y-1">
          <p>📋 <b>หน้านี้คืออะไร:</b> รายงานภาพรวมการเงินและผู้เล่น</p>
          <p>👁 <b>ข้อมูลที่แสดง:</b></p>
          <p className="pl-4">• สรุปยอด = จำนวนผู้ใช้, Agent, เงินเติม/ถอนทั้งหมด</p>
          <p className="pl-4">• เติม/ถอนรายวัน = ดูแนวโน้ม 30 วันย้อนหลัง ว่าเงินเข้า-ออกเท่าไรต่อวัน</p>
          <p className="pl-4">• ผู้เล่นเหรียญมากสุด = Top players ที่มียอดคงเหลือสูง</p>
          <p>💡 <b>ใช้ทำอะไร:</b></p>
          <p className="pl-4">• ดูว่าเงินเข้าระบบเยอะกว่าออกไหม (ควรเป็นบวก)</p>
          <p className="pl-4">• ตรวจสอบผู้เล่นที่มีเหรียญมากผิดปกติ</p>
        </div>
      </details>

      {/* สรุปภาพรวม */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        <div className="stat-card">
          <p className="text-sun-gold/60 text-sm">ผู้ใช้ทั้งหมด</p>
          <p className="text-3xl font-bold text-sun-gold-light">{Number(summary.users.total).toLocaleString()}</p>
          <p className="text-xs text-sun-gold/40">ระงับ: {summary.users.suspended}</p>
        </div>
        <div className="stat-card">
          <p className="text-sun-gold/60 text-sm">Agent</p>
          <p className="text-3xl font-bold text-sun-gold-light">{summary.agents.total}</p>
        </div>
        <div className="stat-card">
          <p className="text-sun-gold/60 text-sm">เติมเหรียญรวม</p>
          <p className="text-3xl font-bold text-green-400">{Number(summary.coins.total_credit).toLocaleString()} 🪙</p>
        </div>
        <div className="stat-card">
          <p className="text-sun-gold/60 text-sm">ถอนเหรียญรวม</p>
          <p className="text-3xl font-bold text-red-400">{Number(summary.coins.total_debit).toLocaleString()} 🪙</p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* เติม/ถอนรายวัน */}
        <div className="card">
          <h2 className="text-lg font-bold text-sun-gold-light mb-4">💰 เติม/ถอนรายวัน (30 วัน)</h2>
          {daily.length > 0 ? (
            <div className="overflow-x-auto">
            <table className="w-full text-sm min-w-[400px]">
              <thead>
                <tr className="text-sun-gold/60 border-b border-sun-gold/20">
                  <th className="text-left py-2">วันที่</th>
                  <th className="text-right py-2">เติม</th>
                  <th className="text-right py-2">ถอน</th>
                  <th className="text-right py-2">รายการ</th>
                </tr>
              </thead>
              <tbody>
                {daily.map((d) => (
                  <tr key={d.date} className="table-row">
                    <td className="py-2">{new Date(d.date).toLocaleDateString("th")}</td>
                    <td className="py-2 text-right text-green-400">+{Number(d.credit).toLocaleString()}</td>
                    <td className="py-2 text-right text-red-400">-{Number(d.debit).toLocaleString()}</td>
                    <td className="py-2 text-right text-sun-gold/40">{d.tx_count}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            </div>
          ) : <p className="text-sun-gold/30">ยังไม่มีข้อมูล</p>}
        </div>

        {/* Top Players */}
        <div className="card">
          <h2 className="text-lg font-bold text-sun-gold-light mb-4">🏆 ผู้เล่นเหรียญมากสุด</h2>
          {topPlayers.length > 0 ? (
            <div className="overflow-x-auto">
            <table className="w-full text-sm min-w-[350px]">
              <thead>
                <tr className="text-sun-gold/60 border-b border-sun-gold/20">
                  <th className="text-left py-2">#</th>
                  <th className="text-left py-2">ผู้เล่น</th>
                  <th className="text-right py-2">เหรียญ</th>
                  <th className="text-right py-2">เกม</th>
                </tr>
              </thead>
              <tbody>
                {topPlayers.map((p, i) => (
                  <tr key={p.username} className="table-row">
                    <td className="py-2">{i + 1}</td>
                    <td className="py-2">{p.display_name || p.username}</td>
                    <td className="py-2 text-right text-sun-gold-light">{Number(p.balance).toLocaleString()} 🪙</td>
                    <td className="py-2 text-right text-sun-gold/40">{p.total_games || 0}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            </div>
          ) : <p className="text-sun-gold/30">ยังไม่มีข้อมูล</p>}
        </div>
      </div>
    </div>
  );
}
