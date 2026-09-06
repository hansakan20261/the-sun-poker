"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";

export default function AgentDashboardPage() {
  const [data, setData] = useState<any>(null);
  const [error, setError] = useState("");
  useEffect(() => { api("/api/agent-portal/dashboard").then(setData).catch((e) => setError(e.error || "โหลดข้อมูลไม่สำเร็จ")); }, []);
  if (error) return <div className="card text-red-300">{error}</div>;
  if (!data) return <div className="card text-sun-gold/60">Loading...</div>;
  return <div>
    <h1 className="text-2xl font-bold text-sun-gold-light mb-6">Agent Dashboard</h1>
    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
      <div className="stat-card"><p className="text-sun-gold/60">Agent</p><p className="text-xl text-white">{data.agent?.display_name}</p></div>
      <div className="stat-card"><p className="text-sun-gold/60">รายได้รวม</p><p className="text-xl text-green-400">{Number(data.agent?.total_earned || 0).toLocaleString()}</p></div>
      <div className="stat-card"><p className="text-sun-gold/60">ยอดถอนได้</p><p className="text-xl text-sun-gold-light">{Number(data.agent?.available_balance || 0).toLocaleString()}</p></div>
    </div>
  </div>;
}
