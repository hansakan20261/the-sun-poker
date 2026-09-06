"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";

export default function AgentWalletPage() {
  const [earnings, setEarnings] = useState<any[]>([]);
  const [withdrawals, setWithdrawals] = useState<any[]>([]);
  useEffect(() => {
    Promise.all([api("/api/agent-portal/earnings"), api("/api/agent-portal/withdrawals")])
      .then(([e, w]) => { setEarnings(e.by_channel || []); setWithdrawals(w.withdrawals || []); });
  }, []);
  return <div>
    <h1 className="text-2xl font-bold text-sun-gold-light mb-6">Agent Wallet</h1>
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
      <div className="card"><h2 className="text-sun-gold-light font-bold mb-3">รายได้ตามช่องทาง</h2>{earnings.map((row, i) => <div key={i} className="flex justify-between py-2 border-b border-sun-gold/10"><span>{row.channel_name || "Default"}</span><span>{Number(row.total_earned || 0).toLocaleString()}</span></div>)}</div>
      <div className="card"><h2 className="text-sun-gold-light font-bold mb-3">คำขอถอน</h2>{withdrawals.map((row) => <div key={row.id} className="flex justify-between py-2 border-b border-sun-gold/10"><span>{Number(row.amount || 0).toLocaleString()}</span><span>{row.status}</span></div>)}</div>
    </div>
  </div>;
}
