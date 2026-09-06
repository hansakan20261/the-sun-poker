"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";

export default function ClubTablesPage() {
  const [groups, setGroups] = useState<any[]>([]);
  useEffect(() => { api("/api/clubs/my").then(async (data) => {
    const clubs = data.clubs || [];
    const tables = await Promise.all(clubs.map(async (club: any) => ({ club, tables: (await api(`/api/clubs/${club.id}/tables`)).tables || [] })));
    setGroups(tables);
  }); }, []);
  return <div><h1 className="text-2xl font-bold text-sun-gold-light mb-6">โต๊ะในคลับ</h1>{groups.map(({ club, tables }) => <div key={club.id} className="card mb-4"><h2 className="text-sun-gold-light font-bold mb-3">{club.name}</h2>{tables.map((table: any) => <div key={table.id} className="flex justify-between py-2 border-b border-sun-gold/10"><span>{table.name}</span><span>{table.player_count}/{table.max_players}</span></div>)}</div>)}</div>;
}
