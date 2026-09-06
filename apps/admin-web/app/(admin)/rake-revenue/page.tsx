"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";

export default function RakeRevenuePage() {
  const [summary, setSummary] = useState<any>(null);
  const [daily, setDaily] = useState<any[]>([]);
  const [byTable, setByTable] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => { loadData(); }, []);

  const loadData = async () => {
    try {
      const data = await api("/api/admin/reports/rake");
      setSummary(data.summary);
      setDaily(data.daily || []);
      setByTable(data.by_table || []);
      setLoading(false);
    } catch (err) { console.error(err); setLoading(false); }
  };

  if (loading) return <p className="text-sun-gold text-center py-10">กำลังโหลด...</p>;

  const totalRake = Number(summary?.total_rake || 0);
  const totalHands = Number(summary?.total_hands || 0);
  const nlhRake = Number(summary?.nlh_rake || 0);
  const ofcRake = Number(summary?.ofc_rake || 0);

  return (
    <div>
      <h1 className="text-2xl font-bold text-sun-gold-light mb-2">💸 รายได้ Rake (ค่าธรรมเนียมโต๊ะ)</h1>
      <p className="text-sun-gold/50 text-sm mb-6">เงินที่หักจากกองกลางแต่ละมือ (5.5%) — ใช้คำนวณ Commission Agent</p>

      <details className="mb-4 text-xs text-sun-gold/50 bg-sun-black/30 rounded-lg p-3">
        <summary className="cursor-pointer text-sun-gold/70 font-bold">ℹ️ วิธีใช้งานหน้านี้</summary>
        <div className="mt-2 space-y-1">
          <p>📋 <b>หน้านี้คืออะไร:</b> ดูรายได้ของระบบจาก Rake (ค่าธรรมเนียมโต๊ะ)</p>
          <p>💸 <b>Rake คืออะไร:</b> ทุกครั้งที่เล่นจบ 1 มือ ระบบหัก 5.5% จากเงินกองกลาง เป็นรายได้ของเรา</p>
          <p className="pl-4">ตัวอย่าง: เล่นจบ กองกลาง 1,000 → ระบบหัก 55 เหรียญ (คนชนะได้ 945)</p>
          <p>👁 <b>ข้อมูลที่แสดง:</b></p>
          <p className="pl-4">• Rake รวม = รายได้ทั้งหมดที่หักมาได้</p>
          <p className="pl-4">• แยกตามเกม = Poker vs ไพ่สามกอง ใครทำเงินมากกว่า</p>
          <p className="pl-4">• แยกตามห้อง = ห้องไหนทำเงินเยอะ</p>
          <p className="pl-4">• รายวัน = แนวโน้มรายได้แต่ละวัน</p>
          <p>💡 <b>ใช้ทำอะไร:</b> ดูว่าธุรกิจไปได้ดีไหม + ใช้คำนวณ Commission ให้ Agent</p>
        </div>
      </details>

      {/* Summary Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
        <div className="stat-card">
          <p className="text-sun-gold/60 text-sm">💰 Rake รวมทั้งระบบ</p>
          <p className="text-3xl font-bold text-sun-gold-light mt-2">{totalRake.toLocaleString()} 🪙</p>
          <p className="text-xs text-sun-gold/40 mt-1">{totalHands.toLocaleString()} มือ</p>
        </div>
        <div className="stat-card">
          <p className="text-sun-gold/60 text-sm">🃏 Poker (NLH)</p>
          <p className="text-2xl font-bold text-green-400 mt-2">{nlhRake.toLocaleString()} 🪙</p>
          <p className="text-xs text-sun-gold/40 mt-1">{Number(summary?.nlh_hands || 0).toLocaleString()} มือ</p>
        </div>
        <div className="stat-card">
          <p className="text-sun-gold/60 text-sm">🀄 ไพ่สามกอง (OFC)</p>
          <p className="text-2xl font-bold text-blue-400 mt-2">{ofcRake.toLocaleString()} 🪙</p>
          <p className="text-xs text-sun-gold/40 mt-1">{Number(summary?.ofc_hands || 0).toLocaleString()} มือ</p>
        </div>
        <div className="stat-card">
          <p className="text-sun-gold/60 text-sm">📊 Rake เฉลี่ย/มือ</p>
          <p className="text-2xl font-bold text-sun-gold-light mt-2">{totalHands > 0 ? (totalRake / totalHands).toFixed(1) : 0} 🪙</p>
          <p className="text-xs text-sun-gold/40 mt-1">5.5% จากกองกลาง</p>
        </div>
      </div>

      {/* By Table */}
      <div className="card mb-6">
        <h2 className="text-lg font-bold text-sun-gold-light mb-4">📋 Rake แยกตามห้อง</h2>
        {byTable.length > 0 ? (
          <div className="overflow-x-auto">
          <table className="w-full text-sm min-w-[500px]">
            <thead>
              <tr className="text-sun-gold/60 border-b border-sun-gold/20">
                <th className="text-left py-2">ห้อง</th>
                <th className="text-left py-2">ประเภท</th>
                <th className="text-right py-2">จำนวนมือ</th>
                <th className="text-right py-2">Rake รวม</th>
                <th className="text-right py-2">เฉลี่ย/มือ</th>
              </tr>
            </thead>
            <tbody>
              {byTable.map((t: any, i: number) => (
                <tr key={i} className="table-row">
                  <td className="py-2 font-bold text-white">{t.table_name}</td>
                  <td className="py-2">
                    <span className={`text-xs px-2 py-0.5 rounded ${t.game_type === 'chinese' || t.game_type_name?.includes('Chinese') ? 'bg-blue-900 text-blue-300' : 'bg-green-900 text-green-300'}`}>
                      {t.game_type === 'chinese' || t.game_type_name?.includes('Chinese') ? '🀄 OFC' : '🃏 NLH'}
                    </span>
                  </td>
                  <td className="py-2 text-right">{Number(t.hand_count).toLocaleString()}</td>
                  <td className="py-2 text-right text-sun-gold-light font-bold">{Number(t.total_rake).toLocaleString()} 🪙</td>
                  <td className="py-2 text-right text-sun-gold/60">{(Number(t.total_rake) / Number(t.hand_count || 1)).toFixed(1)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          </div>
        ) : <p className="text-sun-gold/30">ยังไม่มีข้อมูล Rake (จะมีเมื่อเล่นห้องจริง)</p>}
      </div>

      {/* Daily */}
      <div className="card mb-6">
        <h2 className="text-lg font-bold text-sun-gold-light mb-4">📅 Rake รายวัน</h2>
        {daily.length > 0 ? (
          <div className="overflow-x-auto">
          <table className="w-full text-sm min-w-[400px]">
            <thead>
              <tr className="text-sun-gold/60 border-b border-sun-gold/20">
                <th className="text-left py-2">วันที่</th>
                <th className="text-right py-2">จำนวนมือ</th>
                <th className="text-right py-2">Rake รวม</th>
                <th className="text-right py-2">เฉลี่ย/มือ</th>
              </tr>
            </thead>
            <tbody>
              {daily.map((d: any, i: number) => (
                <tr key={i} className="table-row">
                  <td className="py-2">{new Date(d.date).toLocaleDateString("th")}</td>
                  <td className="py-2 text-right">{Number(d.total_hands_raked).toLocaleString()}</td>
                  <td className="py-2 text-right text-sun-gold-light font-bold">{Number(d.total_rake).toLocaleString()} 🪙</td>
                  <td className="py-2 text-right text-sun-gold/60">{Number(d.avg_rake_per_hand || 0).toFixed(1)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          </div>
        ) : <p className="text-sun-gold/30">ยังไม่มีข้อมูล</p>}
      </div>

      {/* Agent Commission from Rake */}
      <div className="card">
        <h2 className="text-lg font-bold text-sun-gold-light mb-4">🤝 Commission Agent จาก Rake</h2>
        <p className="text-sun-gold/50 text-xs mb-4">Agent ได้ commission เป็น % จาก Rake ที่หักได้ ตามลำดับ Master → Super Agent → Agent</p>
        <div className="bg-sun-black/50 rounded-lg p-4 text-sm space-y-2">
          <p className="text-white">💰 Rake ทั้งหมด: <strong className="text-sun-gold-light">{totalRake.toLocaleString()} 🪙</strong></p>
          <p className="text-sun-gold/60">→ ดูรายละเอียด Commission ที่หน้า <a href="/agent-commission" className="text-sun-gold-light underline">💰 Commission แฮนด์</a></p>
          <p className="text-sun-gold/40 text-xs mt-2">หมายเหตุ: Commission คำนวณจากจำนวนแฮนด์ × อัตรา% ที่ตั้งไว้ หรือจะใช้ Rake จริง × % ก็ได้ (ปรับได้ที่หน้า Commission)</p>
        </div>
      </div>
    </div>
  );
}
