"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";

export default function ClubDashboardPage() {
  const [clubs, setClubs] = useState<any[]>([]);
  useEffect(() => { api("/api/clubs/my").then((d) => setClubs(d.clubs || [])); }, []);
  return <div>
    <h1 className="text-2xl font-bold text-sun-gold-light mb-6">Club Dashboard</h1>
    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">{clubs.map((club) => <div key={club.id} className="card"><h2 className="text-xl text-sun-gold-light">{club.name}</h2><p className="text-sun-gold/60 mt-2">บทบาท: {club.role}</p><p className="text-sun-gold/60">สมาชิก: {club.member_count || 0}</p></div>)}</div>
  </div>;
}
