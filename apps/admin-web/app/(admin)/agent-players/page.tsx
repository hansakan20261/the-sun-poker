"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";

export default function AgentPlayersPage() {
  const [customers, setCustomers] = useState<any[]>([]);
  const [error, setError] = useState("");
  useEffect(() => { api("/api/agent-portal/customers").then((d) => setCustomers(d.customers || [])).catch((e) => setError(e.error || "โหลดข้อมูลไม่สำเร็จ")); }, []);
  return <div>
    <h1 className="text-2xl font-bold text-sun-gold-light mb-6">ลูกค้าของฉัน</h1>
    {error && <div className="card text-red-300 mb-4">{error}</div>}
    <div className="card overflow-x-auto"><table className="w-full text-sm"><thead><tr className="text-sun-gold/60"><th className="text-left py-2">ผู้ใช้</th><th className="text-right">ยอดเงิน</th><th className="text-right">สมัครเมื่อ</th></tr></thead><tbody>
      {customers.map((customer) => <tr key={customer.id} className="table-row"><td className="py-2">{customer.display_name || customer.username}</td><td className="text-right">{Number(customer.balance || 0).toLocaleString()}</td><td className="text-right">{customer.referred_at ? new Date(customer.referred_at).toLocaleDateString("th-TH") : "-"}</td></tr>)}
    </tbody></table></div>
  </div>;
}
